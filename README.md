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

# Install nix(DeterminateSystems/nix-installer)
```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```
and open another shell.

# Check Nix XDG Location
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

# Install `home-manager`
```sh
nix-channel --add https://nixos.org/channels/nixpkgs-unstable unstable
nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz hm
nix-channel --update
nix-env -iA unstable.git
git clone https://github.com/CharlesChiuGit/nix-hm-config.git ~/.config/home-manager
cd ~/.config/home-manager && nix build
# add `trusted-users `: trusted-users = charles in `/etc/nix/nix.conf`
~/.config/home-manager/result/bin/home-manager switch --flake ~/.config/home-manager --impure
home-manager switch --impure # this will prevent current generations get clean up w/ gc`
```

ref: https://github.com/ryantm/home-manager-template/blob/master/README.md

ref: https://github.com/the-argus/spicetify-nix/blob/master/home-manager-install.md

# Remove Snap on Ubuntu
https://www.baeldung.com/linux/snap-remove-disable

# Uninstall Nix
DeterminateSystems/nix-installer:
```sh
/nix/nix-installer uninstall
```
original Nix:
- [](https://nix.dev/manual/nix/2.22/installation/uninstall)

# Resources
- [Nix Reference Manual(2.22)](https://nix.dev/manual/nix/2.22/introduction)
- [Ubuntu nix manpages(Ubuntu 24.04/2.18)](https://manpages.ubuntu.com/manpages/noble/man5/nix.conf.5.html)
- [DeterminateSystems/nix(2.23)](https://github.com/DeterminateSystems/nix-installer)
- [my-nix-journey-use-nix-with-ubuntu](https://tech.aufomm.com/my-nix-journey-use-nix-with-ubuntu/)
- [FlakeHub](https://flakehub.com/)
- 
