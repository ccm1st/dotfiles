{ user, pkgs, ... }:

{
  # Determinate already manages the Nix daemon, so nix-darwin shouldn't.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin"; # use x86_64-darwin for Intel CPU

  system.primaryUser = user;
  users.users.${user} = {
    home = "/Users/${user}";
  };
  system.stateVersion = 6;
  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;          # fast key repeat
      InitialKeyRepeat = 15;  # short delay before repeat
      _HIHideMenuBar = true;  # auto-hide the menu bar
      AppleShowAllExtensions = true;
    };
    dock.autohide = true;
    finder.FXPreferredViewStyle = "Nlsv";  # list view by default
    finder.CreateDesktop = false;          # clean desktop
    trackpad.Clicking = true;              # tap to click
  };
  nix-homebrew = {
    enable = true;
    inherit user;
    autoMigrate = true;
  };
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";  # remove anything not listed here
    onActivation.autoUpdate = true;
    onActivation.extraFlags = [ "--force" ];
    caskArgs = {
      appdir = "/Applications";
    };
    brews = [
      "herdr"
      "node"
    ];
    casks = [
      "wezterm"
      "claude-code"
      "visual-studio-code"
    ];
  };

  # Homebrew's `code` shim lives in /opt/homebrew/bin, which is not on PATH
  # unless brew shellenv is sourced. This wrapper keeps `code` on the Nix PATH.
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "code" ''
      exec "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" "$@"
    '')
  ];

  
}
