# Architectural Overview

## Directory Structure

```

├── conf.d/                  # config directory
│   ├── Usercommand/         # custom scripts to placed in ~/.local/bin
│   ├── ages/                # age-encrypted files
│   ├── conda/               # conda global config
│   ├── glow/                # glow config
│   ├── npm/                 # npm global config
│   ├── python/              # python global config
│   ├── tmux/                # extra tmux config
│   ├── topgrade/            # extra topgrade config
│   ├── wget/                # wget global config
│   ├── yarn/                # yarn global config
│   └── zsh/                 # *.zsh files that will be used in `/modules/apps/zsh.nix`
├── modules/
│   ├── apps/                # every `*.nix` file is a home-manager `programs.*` settings
│   │   ├── roles/           # `pkgs.*` that should only be used when assign with certain roles
│   │   └── _common.nix      # `pkgs.*` that should be used in every host machines
│   ├── hosts/               # host machine's config, roles are defined in here
│   ├── services/            # every `*.nix` file is a home-manager `services.*` settings
│   ├── targets/             # darwin config and genericLinux(-gpu) config
│   ├── agenix.nix           # agenix config that works with `secrets.nix`
│   ├── catppuccin.nix       # catppuccin colorschme config for supported apps
│   ├── core.nix             # combine and inherit other config file to a universal entry
│   ├── nix-config.nix       # nix config
│   └── xdg-config.nix       # xdg config
├── README.md
├── flake.lock               # lockfile for the flake inputs
├── flake.nix                # define flake inputs
├── mise.toml                # define lang version, env and tasks with mise
└── secrets.nix              # works with `/conf.d/ages` and `agenix.nix`
```
