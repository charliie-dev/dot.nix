# Nix Home-Manager dotfiles

> [!IMPORTANT]
> Make sure `curl`, `openssl`, `zsh`, `age` is already installed.

## make `age` key

```sh
mkdir -p ~/.config/age
## gen age key
age-keygen -o ~/.config/age/keys.txt
## echo age pubkey
age-keygen -y ~/.config/age/keys.txt
## rekey on old machine
agenix -r -i ~/.config/age/keys.txt
```

## create `~/.config/nix/nix.conf`

```sh
mkdir -p ~/.config/nix
cat <<EOF >>~/.config/nix/nix.conf
experimental-features = nix-command flakes
use-xdg-base-directories = true
cores = 0 # use all available cores
max-jobs = 10
auto-optimise-store = true
warn-dirty = false
http-connections = 50
trusted-users = charles
use-case-hack = true # only for macOS
EOF
```

## Install nix(DeterminateSystems/nix-installer)

```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
```

### add `trusted-users`

edit `/etc/nix/nix.custom.conf`:

```conf
trusted-users = charles
```

restart daemon:

on macOS:

```sh
sudo launchctl unload /Library/LaunchDaemons/systems.determinate.nix-daemon.plist
sudo launchctl load /Library/LaunchDaemons/systems.determinate.nix-daemon.plist
```

on Ubuntu:

```sh
sudo systemctl restart nix-daemon
```

and open another shell.

## Check Nix XDG Location

<details>
  <summary>Expand here</summary>

````
```bash
nix_state_home=${XDG_STATE_HOME-$HOME/.local/state}/nix

if [[! -d $nix_state_home]]; then
mkdir -p $nix_state_home
fi

if [[-f $HOME/.nix-profile]]; then
mv $HOME/.nix-profile $nix_state_home/profile
fi
if [[-f $HOME/.nix-defexpr]]; then
mv $HOME/.nix-defexpr $nix_state_home/defexpr
fi
if [[-f $HOME/.nix-channels]]; then
mv $HOME/.nix-channels $nix_state_home/channels
fi
```
````

</details>

## Install `home-manager`

```sh
nix run home-manager/master -- init --switch
exit
# nix-channel --add https://nixos.org/channels/nixpkgs-unstable unstable
# nix-channel --update
# nix-env -iA unstable.git
git clone https://github.com/charliie-dev/dot.nix.git ~/.config/home-manager
# nix-env -e git
cd ~/.config/home-manager && nix build
# add `trusted-users `: trusted-users = charles in `/etc/nix/nix.conf`
rm ~/.config/nix/nix.conf
~/.config/home-manager/result/bin/home-manager switch --flake ~/.config/home-manager --impure
home-manager switch --impure # this will prevent current generations get clean up w/ gc`
determinate-nixd version
```

ref: https://github.com/ryantm/home-manager-template/blob/master/README.md

ref: https://github.com/the-argus/spicetify-nix/blob/master/home-manager-install.md

## Update Flakes

```sh
nix flake update
home-manager switch --flake .
```

## Upgrade Nix

- On macOS:

```sh
sudo determinate-nixd upgrade
```

- On Ubuntu:

```sh
sudo visudo
# add `/nix/var/nix/profiles/default/bin` to `Defaults secure_path=`
sudo nix upgrade-nix
```

## Uninstall Nix

- DeterminateSystems/nix-installer:

  ```sh
  /nix/nix-installer uninstall
  ```

- Uninstall original Nix: [Nix Reference Manual/unistall](https://nix.dev/manual/nix/2.22/installation/uninstall)

## Resources

### Shorthands

- [Nixpkgs Pull Request Tracker](https://nixpk.gs/pr-tracker.html?pr=)
- [Home Manager Option Search](https://home-manager-options.extranix.com/)
- [mynixos.com](https://mynixos.com/) - all-in-one site for search flakes, categories, options and packages
- [nix-versions](https://lazamar.co.uk/nix-versions/) - search nixpkgs version on different branches
- [nix.catppuccin.com](https://nix.catppuccin.com/) - catppuccin options for home-manager
- [noogle.dev/](https://noogle.dev/) - search nix functions

### Documentations

- [nixos.org](https://nixos.org/)
- [nix.dev](https://nix.dev/)
- [DeterminateSystems/nix(2.23)](https://github.com/DeterminateSystems/nix-installer)
- [my-nix-journey-use-nix-with-ubuntu](https://tech.aufomm.com/my-nix-journey-use-nix-with-ubuntu/)
- [DeterminateSystems/zero-to-nix](https://zero-to-nix.com/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [NixOS Wiki](https://wiki.nixos.org/wiki/NixOS_Wiki)
- [manix](https://github.com/nix-community/manix)
- [NixOS & Flakes Book - An unofficial book for beginners](https://nixos-and-flakes.thiscute.world/)
- [Nix Pills](https://nixos.org/guides/nix-pills/)
- [nix-tutorial](https://nix-tutorial.gitlabpages.inria.fr/nix-tutorial/getting-started.html)
- [LnL7/nix-darwin](https://github.com/LnL7/nix-darwin)
