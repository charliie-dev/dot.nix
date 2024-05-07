#!/usr/bin/env bash

# install curl, openssl

# create ~/.condig/nix/nix.conf
mkdir -p ~/.config/nix
cat <<EOF >>~/.config/nix/nix.conf
experimental-features = nix-command flakes
use-xdg-base-directories = true
cores = 0 # use all available cores
auto-optimise-store = true
http2 = true
EOF

# install nix
curl -L https://nixos.org/nix/install | sh -s -- --daemon

# check nix xdg location
nix_state_home=${XDG_STATE_HOME-$HOME/.local/state}/nix

if [[ ! -d $nix_state_home ]]; then
	mkdir -p $nix_state_home
fi

if [[ -f $HOME/.nix-profile ]]; then
	mv $HOME/.nix-profile $nix_state_home/profile
fi
if [[ -f $HOME/.nix-defexpr ]]; then
	mv $HOME/.nix-defexpr $nix_state_home/defexpr
fi
if [[ -f $HOME/.nix-channels ]]; then
	mv $HOME/.nix-channels $nix_state_home/channels
fi

# install home-manager
nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
nix-channel --update
nix-shell '<home-manager>' -A install

# clone configs
git clone https://github.com/CharlesChiuGit/nix-hm-config.git ~/.config/home-manager

# run home-manager switch
cd ~/.config/home-manager
nix flakes update && home-manager switch --impure
cd "$OLDPWD"
