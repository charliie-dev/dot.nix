# nix-hm-config

# install curl, openssl

# create ~/.condig/nix/nix.conf
```sh
mkdir -p ~/.config/nix
cat <<EOF >>~/.config/nix/nix.conf
experimental-features = nix-command flakes
use-xdg-base-directories = true
cores = 0 # use all available cores
auto-optimise-store = true
http2 = true
EOF
```

# install nix
```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```
and open another shell.

# check nix xdg location
```sh
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
```

# install home-manager
```sh
nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs-unstable
nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
nix-channel --update
nix-shell -p home-manager git # nix-env -iA nixpkgs.home-manager nixpkg.git
git clone https://github.com/CharlesChiuGit/nix-hm-config.git ~/.config/home-manager
nix run home-manager/master -- init --switch --impure 
```

ref: https://github.com/ryantm/home-manager-template/blob/master/README.md

ref: https://github.com/the-argus/spicetify-nix/blob/master/home-manager-install.md

# remove snap on ubuntu
https://www.baeldung.com/linux/snap-remove-disable

ref: https://tech.aufomm.com/my-nix-journey-use-nix-with-ubuntu/
