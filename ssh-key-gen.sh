#!/usr/bin/env bash
ssh-keygen -t ed25519 -C ccm1st@gmail.com -f ~/.ssh/id_ed25519 -N ""
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
pbcopy < ~/.ssh/id_ed25519.pub