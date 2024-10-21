# Nix Home-Manager dotfiles

> [!IMPORTANT]  
> Make sure `curl` and `openssl` is already installed.

## create `~/.condig/nix/nix.conf`

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
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

and open another shell.

## Check Nix XDG Location

<details>
  <summary>Expand here</summary>
    
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

</details>

## Install `home-manager`

```sh
nix-channel --add https://nixos.org/channels/nixpkgs-unstable unstable
nix-channel --update
nix-env -iA unstable.git
git clone https://github.com/CharlesChiuGit/nix-hm-config.git ~/.config/home-manager
nix-env -e git
cd ~/.config/home-manager && nix build
# add `trusted-users `: trusted-users = charles in `/etc/nix/nix.conf`
~/.config/home-manager/result/bin/home-manager switch --flake ~/.config/home-manager --impure
home-manager switch --impure # this will prevent current generations get clean up w/ gc`
```

ref: https://github.com/ryantm/home-manager-template/blob/master/README.md

ref: https://github.com/the-argus/spicetify-nix/blob/master/home-manager-install.md

## Uninstall Nix

- DeterminateSystems/nix-installer:

  ```sh
  /nix/nix-installer uninstall
  ```

- Uninstall original Nix: [Nix Reference Manual/unistall](https://nix.dev/manual/nix/2.22/installation/uninstall)

## Resources

- [nixos.org](https://nixos.org/)
- [Home Manager Option Search](https://home-manager-options.extranix.com/)
- [nix.dev](https://nix.dev/)
- [DeterminateSystems/nix(2.23)](https://github.com/DeterminateSystems/nix-installer)
- [my-nix-journey-use-nix-with-ubuntu](https://tech.aufomm.com/my-nix-journey-use-nix-with-ubuntu/)
- [FlakeHub](https://flakehub.com/)
- [DeterminateSystems/zero-to-nix](https://zero-to-nix.com/)
- [Home Manager Manual(24.05)](https://nix-community.github.io/home-manager/)
- [NixOS Wiki](https://wiki.nixos.org/wiki/NixOS_Wiki)
- [mynixos.com](https://mynixos.com/)
- [manix](https://github.com/nix-community/manix)
- [NixOS & Flakes Book - An unofficial book for beginners](https://nixos-and-flakes.thiscute.world/)
- [Nix Pills](https://nixos.org/guides/nix-pills/)
- [nix-tutorial](https://nix-tutorial.gitlabpages.inria.fr/nix-tutorial/getting-started.html)
- [LnL7/nix-darwin](https://github.com/LnL7/nix-darwin)
