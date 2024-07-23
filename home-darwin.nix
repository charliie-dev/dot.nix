{ inputs, outputs, config, pkgs, lib, ... }:
with lib;
{
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # outputs.homeManagerModules.example

    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default

    # You can also split up your configuration and import pieces of it here:
    # ./nvim.nix
  ];

  nix = {
    package = pkgs.nix;
    checkConfig = true;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      use-xdg-base-directories = true;
      cores = 0; # use all available cores
      max-jobs = 10;
      auto-optimise-store = true;
      warn-dirty = false;
      http-connections = 50;
      trusted-users = "charles";
      use-case-hack = true; # only for macOS
    };
    gc = {
      automatic = true;
      options = "--max-freed $((64 * 1024**3))";
    };
  };


  nixpkgs = {
    overlays = [
    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
    };
  };

  # Nicely reload system units when changing configs
  # systemd.user.startServices = "sd-switch";

  home = {
    # home.username = lib.strings.removeSuffix "\n" (builtins.readFile /etc/hostname);
    username = "charles";
    homeDirectory = "/Users/charles";
    stateVersion = "24.11";
  };

  # https://search.nixos.org/packages?query=
  # https://home-manager-options.extranix.com/?query=
  home.packages = with pkgs; [
    chafa
    curl
    git
    gnupg
    gnutar
    gzip
    hstr
    unzip
    vim
    wget
    xdg-ninja
    antidote #zsh-framwork
    # c/c++ cli
    btop
    fzy
    jq
    lnav
    # python cli
    git-fame
    git-filter-repo
    # golang cli
    fzf
    glow
    lazydocker
    lazygit
    nix-search-cli
    pistol
    # vfox ## TODO: https://github.com/version-fox/vfox/issues/53
    # rust cli
    # joshuto
    # xq
    bat
    delta
    dua
    eva
    eza
    fd
    fh # official CLI for FlakeHub
    jaq
    lsd
    mise
    ripgrep
    ripgrep-all
    ripsecrets
    rye # like cargo but for python
    sd
    starship
    tokei
    topgrade
    tree-sitter
    uv # pip in rust
    xh
    yazi
    zellij
    zoxide
  ];

  home.file = {
    # ".ssh/config".source = ./conf.d/ssh/config;
    ".config/topgrade.toml".source = ./conf.d/topgrade/topgrade.toml;
    ".local/bin" = {
      recursive = true;
      source = ./conf.d/Usercommand;
    };
  };
  programs.home-manager.enable = true;

  xdg.enable = true;
  xdg.configFile = {
    # core-utils
    "zsh" = {
      recursive = true;
      source = ./conf.d/zsh;
    };
    "git" = {
      recursive = true;
      source = ./conf.d/git;
    };
    # lang-vms
    "mise" = {
      recursive = true;
      source = ./conf.d/mise;
    };
    "conda" = {
      recursive = true;
      source = ./conf.d/conda;
    };
    # cli-utils
    "bat" = {
      recursive = true;
      source = ./conf.d/bat;
    };
    "btop" = {
      recursive = true;
      source = ./conf.d/btop;
    };
    "fd" = {
      recursive = true;
      source = ./conf.d/fd;
    };
    "glow" = {
      recursive = true;
      source = ./conf.d/glow;
    };
    "htop" = {
      recursive = true;
      source = ./conf.d/htop;
    };
    "lazygit" = {
      recursive = true;
      source = ./conf.d/lazygit;
    };
    "lsd" = {
      recursive = true;
      source = ./conf.d/lsd;
    };
    "npm" = {
      recursive = true;
      source = ./conf.d/npm;
    };
    "pistol" = {
      recursive = true;
      source = ./conf.d/pistol;
    };
    "starship" = {
      recursive = true;
      source = ./conf.d/starship;
    };
    "wget" = {
      recursive = true;
      source = ./conf.d/wget;
    };
    "yarn" = {
      recursive = true;
      source = ./conf.d/yarn;
    };
    "yazi" = {
      recursive = true;
      source = ./conf.d/yazi;
    };
    "zellij" = {
      recursive = true;
      source = ./conf.d/zellij;
    };
  };

  home.activation.nvimdotsActivatioinAction = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d ~/.config/nvim ]; then
      ${pkgs.git}/bin/git clone https://github.com/CharlesChiuGit/nvimdots.lua.git ~/.config/nvim
    fi
  '';

  programs.neovim = {
    enable = true;
    # package = pkgs.neovim-nightly;

    withNodeJs = true;
    withPython3 = true;
    withRuby = false;

    extraPackages = with pkgs;[
      # Dependent packages used by default plugins
      doq
      cargo
      clang
      cmake
      gcc
      gnumake
      go
      ninja
      pkg-config
      yarn
      lua51Packages.luarocks
    ];

    extraPython3Packages = pyPkgs: with pyPkgs; [
      docformatter
      pynvim
    ];

    # extraLuaPackages = luaPkgs: with luaPkgs; [
    # luarocks # doesn't work, put in extraPackages
    # ];
    viAlias = true;
    vimdiffAlias = true;
  };

  programs.tmux = {
    enable = true;
    clock24 = true;
    mouse = true;
    secureSocket = true;
    plugins = with pkgs; [
      tmuxPlugins.better-mouse-mode
      tmuxPlugins.tmux-fzf # prefix + F
      {
        plugin = tmuxPlugins.catppuccin;
        extraConfig = ''
          set -g @catppuccin_flavour 'macchiato' # or frappe, macchiato, mocha
          set -g @catppuccin_window_tabs_enabled on
          set -g @catppuccin_host "on"
        '';
      }
      {
        # automatically saves sessions for you every 15 minutes
        # `prefix+Ctrl+s` to save, `prefix+Ctrl+r` to restore
        plugin = tmuxPlugins.continuum;
        extraConfig = ''
          set -g @continuum-save-interval '15'
          set -g @continuum-restore 'off'
        '';
      }
      {
        plugin = tmuxPlugins.prefix-highlight;
        extraConfig = ''
          set -g @prefix_highlight_prefix_prompt 'Wait'
          set -g @prefix_highlight_copy_prompt 'Copy'
          set -g @prefix_highlight_sync_prompt 'Sync'
        '';
      }
      {
        # persist tmux sessions after computer restart
        plugin = tmuxPlugins.resurrect;
        extraConfig = ''
          set -g @resurrect-capture-pane-contents 'on'
          set -g @resurrect-dir "$XDG_DATA_HOME/tmux/resurrect"
        '';
      }
      {
        # add zoxide and fzf support for tmux session
        # `prefix + T` to open session wizard
        plugin = tmuxPlugins.session-wizard;
        extraConfig = ''
          set -g @session-wizard 'T'
        '';
      }
      {
        plugin = tmuxPlugins.yank;
        extraConfig = ''
          set -g @yank_selection 'chipboard'
          set -g @yank_selection_mouse 'clipboard'
          set -g @custom_copy_command 'yank > #{pane_tty}'
        '';
      }
    ];

    extraConfig = ''
      ${builtins.readFile ./conf.d/tmux/tmux.conf}
    '';
  };

  programs.zsh = {
    enable = true;
    dotDir = ".config/zsh";
    zprof.enable = false;
    antidote = {
      enable = true;
      useFriendlyNames = true;
      plugins = [
        # lazy-loading `kind:defer`
        "Aloxaf/fzf-tab kind:defer"
        "zsh-users/zsh-autosuggestions kind:defer"
        "zsh-users/zsh-completions kind:fpath"
        "belak/zsh-utils path:completion"
        "zsh-users/zsh-history-substring-search kind:defer"
        "zdharma-continuum/fast-syntax-highlighting kind:defer"
        "MichaelAquilina/zsh-you-should-use kind:defer"
        "hlissner/zsh-autopair"
        "mroth/evalcache"
        # oh-my-zsh plugins
        "getantidote/use-omz" # handle OMZ dependencies
        "ohmyzsh/ohmyzsh path:lib" # load OMZ's library
        "ohmyzsh/ohmyzsh path:plugins/colored-man-pages kind:defer" # load OMZ plugins
        "ohmyzsh/ohmyzsh path:plugins/magic-enter kind:defer"
      ];
    };
    initExtra = ''
      ${builtins.readFile ./conf.d/zsh/setopt.zsh}
      ${builtins.readFile ./conf.d/zsh/exports.zsh}
      ${builtins.readFile ./conf.d/zsh/history.zsh}
      ${builtins.readFile ./conf.d/zsh/functions.zsh}
      ${builtins.readFile ./conf.d/zsh/bindkeys.zsh}
      ${builtins.readFile ./conf.d/zsh/history.zsh}
      ${builtins.readFile ./conf.d/zsh/plugins.zsh}
      ${builtins.readFile ./conf.d/zsh/aliases.zsh}
      ${builtins.readFile ./conf.d/zsh/completion.zsh}
      ${builtins.readFile ./conf.d/zsh/hashdirs.zsh}
    '';
  };
}
