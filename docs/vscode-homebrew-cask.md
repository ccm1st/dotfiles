# Visual Studio Code on nix-darwin

How this machine gets VS Code into `/Applications` with a working `code` command, what went wrong the first time, and how to diagnose the same class of problem later.

This is an operational note, not a second source of truth for the live config. The live config is [configuration.nix](../configuration.nix). Deliberate decisions that agents must not revert are in [AGENTS.md](../AGENTS.md).

## End state

Three things have to be true at once:

1. Homebrew owns the app as cask `visual-studio-code`.
2. `/Applications/Visual Studio Code.app` is a real app bundle directory, not a Finder alias or symlink.
3. `code` is on PATH via a Nix wrapper, not Homebrew's `/opt/homebrew/bin/code` shim.

Do not install VS Code from a zip in [bootstrap.sh](../bootstrap.sh). Do not use `pkgs.vscode`. Do not soften `homebrew.onActivation.cleanup = "zap"`.

## Required config

In [configuration.nix](../configuration.nix):

```nix
homebrew = {
  enable = true;
  onActivation.cleanup = "zap";
  onActivation.autoUpdate = true;
  onActivation.extraFlags = [ "--force" ];
  caskArgs = { appdir = "/Applications"; };
  casks = [ "wezterm" "claude-code" "visual-studio-code" ];
};

environment.systemPackages = [
  (pkgs.writeShellScriptBin "code" ''
    exec "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" "$@"
  '')
];
```

Why each piece exists:

- The cask is what puts a GUI app in `/Applications`. Zap will not remove it because it is listed.
- `caskArgs.appdir = "/Applications"` is Homebrew's default, but set it explicitly so the install target cannot silently become `~/Applications`.
- The Nix wrapper is required because this config does not source `brew shellenv`. Homebrew's `code` shim lives in `/opt/homebrew/bin`, which is not on PATH. The wrapper execs the binary inside the app bundle, so CLI and GUI stay on the same install.

`home.nix` must not also install VS Code. One owner only.

## Issues faced

### 1. `code` working is not the same as Applications search working

Symptom: `code --version` succeeded, `open -Ra "Visual Studio Code"` succeeded, Finder showed something named Visual Studio Code in `/Applications`, but Launchpad and the Applications window search did not find it.

Cause: `/Applications/Visual Studio Code.app` was a root-owned symlink to Caskroom:

```text
/Applications/Visual Studio Code.app
  -> /opt/homebrew/Caskroom/visual-studio-code/<version>/Visual Studio Code.app
```

Finder renders that as a shortcut/alias. Spotlight indexes almost no application metadata on that symlink (`kMDItemKind` missing, `kMDItemFSSize=1`). Launch Services can still open the target, so CLI and `open` look fine.

WezTerm in the same folder was the correct shape: a real `Directory` owned by the user, with `kMDItemKind = Application`.

This is not a missing Nix option. The cask + wrapper were already correct. The on-disk Homebrew artifact was wrong.

### 2. Homebrew `app` artifacts must be moved, not linked into `/Applications`

Homebrew's `App` artifact inherits `Moved`. A successful install:

1. Moves or copies `Visual Studio Code.app` into `/Applications` as a directory.
2. Runs `chmod -R a+rX` on that bundle.
3. Leaves a reverse symlink in Caskroom pointing at `/Applications`.

The broken install was the inverse: Applications was the symlink, Caskroom held the real bundle. That can happen after adopting a previous zip/link, a failed move that fell back to linking, or a root-owned leftover that Homebrew would not replace.

A symlink in `/Applications` is a common-looking Homebrew leftover. It is not the intended cask app install.

### 3. Mixing a zip install with the cask is dangerous under zap

An earlier path installed VS Code from a bootstrap zip, then the cask tried to own the same `/Applications/Visual Studio Code.app` path. With `cleanup = "zap"`, undeclared Homebrew packages disappear on switch, and a half-adopted zip/cask mix can leave the Applications entry as a link instead of a moved bundle.

Keep one installer. The cask is that installer.

### 4. Spotlight can keep stale names after a copy

Copying the bundle through a temporary name such as `Visual Studio Code.app.nix-fix` and then renaming it can leave Spotlight metadata pointing at the temp name (`kMDItemKind = Folder`). After the final bundle is in place, re-register and reimport:

```sh
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Visual Studio Code.app"
mdimport -i "/Applications/Visual Studio Code.app"
```

Then confirm `mdls` reports `kMDItemKind = Application` and `kMDItemContentType = com.apple.application-bundle`.

The bundle's `CFBundleName` / `CFBundleDisplayName` is `Code`. Launch Services accepts `open -Ra "Visual Studio Code"` from the filename, but `open -Ra "Code"` may fail. Search in Applications should still find it once Spotlight indexes the bundle.

### 5. A rebuild assertion on `postUserActivation` is a different problem

nix-darwin 26.05 removed `system.activationScripts.postUserActivation`. An earlier `sudo darwin-rebuild switch` failed on that assertion. User-level `darwin-rebuild build` later succeeded; a leftover `extraUserPostActivation` alias can exist and be empty. That does not mean `? postUserActivation` is set.

Do not add `postUserActivation` to this config. Do not treat that assertion as a VS Code cask failure. If switch cannot be run from an agent session, it is usually because `sudo` needs a password.

## Resolution used here

Config was already the end-state shape: cask `visual-studio-code`, `appdir = "/Applications"`, Nix `code` wrapper.

The GUI fix was on disk, not in Nix:

1. Confirm the Applications entry is a symlink, and compare with WezTerm.
2. Copy the real bundle from Caskroom onto `/Applications/Visual Studio Code.app` as a directory owned by the user.
3. `chmod -R a+rX` the bundle.
4. `lsregister -f` and `mdimport -i` the final path.
5. Verify Spotlight and Launch Services, not only `code --version`.

A future clean machine should not need that copy if Homebrew's move phase succeeds on first install. If a rebuild still leaves a symlink, reinstall the cask after quitting VS Code:

```sh
brew reinstall --cask --force visual-studio-code
```

Then re-check `stat`. If it is still a symlink, look at App Management / Full Disk Access for the terminal running `darwin-rebuild`, and whether a root-owned leftover is blocking the move.

## Verify

```sh
stat -f 'vscode: type=%HT owner=%Su:%Sg' "/Applications/Visual Studio Code.app"
stat -f 'wez:    type=%HT owner=%Su:%Sg' "/Applications/WezTerm.app"
mdls -name kMDItemKind -name kMDItemContentType -name kMDItemFSName \
  "/Applications/Visual Studio Code.app"
mdfind 'kMDItemFSName == "Visual Studio Code.app"'
open -Ra "Visual Studio Code"
command -v code
code --version
```

Expected:

- VS Code `type=Directory`, not `Symbolic Link`.
- WezTerm also `Directory`.
- `kMDItemKind = Application`.
- `mdfind` prints `/Applications/Visual Studio Code.app`.
- `code` is `/run/current-system/sw/bin/code` (or another Nix profile path), not `/opt/homebrew/bin/code`.

If Finder still shows an old alias icon, close the Applications window and open it again.

## Playbook for the next GUI cask

Use this whenever a Homebrew cask "installed" but Launchpad / Applications search cannot find it.

1. Do not trust CLI success. Check the Applications path type with `stat -f '%HT'`.
2. Compare with a known-good cask in the same folder. In this repo that is WezTerm.
3. Healthy: `/Applications/Foo.app` is a directory; Caskroom may contain a reverse symlink back to it.
4. Unhealthy: `/Applications/Foo.app` is a symlink into Caskroom. Spotlight will usually miss it.
5. Fix the artifact (reinstall/move/copy), then `lsregister` / `mdimport`. Do not add Nix packages or PATH hacks to paper over a bad bundle.
6. Keep one owner. Cask or Nix package or zip, never two. With zap, the undeclared owner loses.
7. For CLI shims that live under `/opt/homebrew/bin`, add a Nix wrapper only if `brew shellenv` is not on PATH. Point the wrapper at the app-bundle binary, not at a second copy of the app.

## Anti-patterns

- Treating a Finder shortcut in `/Applications` as success.
- Installing `pkgs.vscode` "to make `code` work".
- Putting VS Code back in `bootstrap.sh` as a zip.
- Changing zap to `uninstall` or `none` so an ad-hoc install survives.
- Searching Spotlight for the bundle display name `Code` and concluding the app is missing.
- Assuming `open -Ra` success means Launchpad will show the app.
