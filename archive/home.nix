{
  # inputs,
  pkgs,
  lib,
  config,
  ...
}:
with lib;
{
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # outputs.homeManagerModules.example

    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default

    # You can also split up your configuration and import pieces of it here:
    # ./nvim.nix
    # inputs.catppuccin.homeManagerModules.catppuccin
  ];

  nix = {
    package = pkgs.nix;
    checkConfig = true;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      use-xdg-base-directories = true;
      cores = 0; # use all available cores
      max-jobs = 10;
      auto-optimise-store = true;
      warn-dirty = false;
      http-connections = 50;
      trusted-users = "charles";
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d --max-freed $((1 * 1024**3))"; # 1 GB
    };
  };

  nixpkgs = {
    overlays = [ ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
    };
  };

  # Nicely reload system units when changing configs
  # systemd.user.startServices = "sd-switch";

  # services = {
  #   ssh-tpm-agent = {
  #     enable = true;
  #   };
  # };

  home = {
    # home.username = lib.strings.removeSuffix "\n" (builtins.readFile /etc/hostname);
    username = "charles";
    homeDirectory = "/home/charles";
    stateVersion = "25.05";
    shell.enableZshIntegration = true;
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
    wget2
    fastfetch
    xdg-ninja
    mermaid-cli
    # xpdf # xpdf_4.05 is not secure, with lots of CVE
    # TOPs
    htop
    s-tui
    iftop
    iotop-c
    wavemon

    # c/c++ cli
    fzy
    jq
    lnav
    # snyk
    # https://wiki.nixos.org/wiki/Python#Using_micromamba
    # micromamba # conda replacement, don't install via nix, install directly
    # python cli
    git-fame
    git-filter-repo
    # golang cli
    glow
    lazydocker
    lazyssh
    nix-search-cli
    pistol
    yq-go # jq but for YAML, JSON, XML, CSV, TOML
    jqp # TUI plaground to experiment with jq
    # vfox ## TODO: https://github.com/version-fox/vfox/issues/53
    # rust cli
    alejandra
    delta
    difftastic
    dua
    git-lfs
    git-ignore # sondr3/git-ignore
    eva
    fd
    lsd
    mise
    ripgrep
    # ripgrep-all
    # ripsecrets
    # sd
    starship
    statix # lints and suggestions for the nix
    deadnix # Scan Nix files for dead code
    nixfmt-rfc-style # nixfmt was renamed to nixfmt-classic. The nixfmt attribute may be used for the new RFC 166-style formatter in the future, which is currently available as nixfmt-rfc-style
    tokei
    topgrade
    tree-sitter
    xh
    zoxide
    hwatch
  ];

  home.file = {
    # ".ssh/config".source = ./conf.d/ssh/config;
    ".config/topgrade.toml".source = ./conf.d/topgrade/topgrade.toml;
    ".local/bin" = {
      recursive = true;
      source = ./conf.d/Usercommand;
    };
  };

  xdg.enable = true;
  xdg.configFile = {
    # core-utils
    "git" = {
      recursive = true;
      source = ./conf.d/git;
    };
    # lang-vms
    # "mise" = {
    #   recursive = true;
    #   source = ./conf.d/mise;
    # };
    "conda" = {
      recursive = true;
      source = ./conf.d/conda;
    };
    "python" = {
      recursive = true;
      source = ./conf.d/python;
    };
    # cli-utils
    "glow" = {
      recursive = true;
      source = ./conf.d/glow;
    };
    "lazydocker" = {
      recursive = true;
      source = ./conf.d/lazydocker;
    };
    "lsd" = {
      recursive = true;
      source = ./conf.d/lsd;
    };
    "pistol" = {
      recursive = true;
      source = ./conf.d/pistol;
    };
    "npm" = {
      recursive = true;
      source = ./conf.d/npm;
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
  };

  catppuccin = {
    # accent = "green";
    flavor = "mocha";
    bat = {
      enable = true;
    };
    btop = {
      enable = true;
    };
    delta = {
      enable = true;
    };
    gh-dash = {
      enable = true;
    };
    lazygit = {
      enable = true;
    };
    lsd = {
      enable = true;
    };
    tmux = {
      enable = true;
      flavor = "macchiato"; # or frappe, macchiato, mocha
      extraConfig = ''
        set -g @catppuccin_window_tabs_enabled on
        set -g @catppuccin_host "on"
      '';
    };
    yazi = {
      enable = true;
      flavor = "macchiato";
    };
    zsh-syntax-highlighting = {
      enable = true;
      flavor = "frappe";
    };
  };

  home.activation.nvimdotsActivatioinAction = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d ~/.config/nvim ]; then
      ${pkgs.git}/bin/git clone https://github.com/CharlesChiuGit/nvimdots.lua.git ~/.config/nvim
    fi
  '';

  programs = {
    home-manager.enable = true;
    bat = {
      enable = true;
      extraPackages = with pkgs.bat-extras; [
        batgrep
        batwatch
        prettybat
      ];
      config = {
        paging = "auto";
        pager = "less --RAW-CONTROL-CHARS --quit-if-one-screen --mouse";
        color = "always";
        decorations = "always";
        italic-text = "always";
        style = "changes,header-filename,header-filesize,grid,numbers,snip";
      };
    };

    btop = {
      enable = true;
      extraConfig = ''
        #* Set to True to enable "h,j,k,l,g,G" keys for directional control in lists.
        #* Conflicting keys for h:"help" and k:"kill" is accessible while holding shift.
        vim_keys = True

        #* Update time in milliseconds, recommended 2000 ms or above for better sample times for graphs.
        update_ms = 100

        #* Show processes as a tree.
        proc_tree = True

        #* Use a darkening gradient in the process list.
        proc_gradient = False

        log_level = "WARNING"
      '';
    };

    fd = {
      enable = true;
      hidden = true;
      ignores = [
        ".git/"
        "/mnt/c/"
      ];
    };

    fzf = {
      enable = true;
      # enableZshIntegration = true;
      # defaultCommand = ""
      defaultOptions = [
        "--reverse --margin=3% --style=full"
        "--border=rounded"
        "--prompt='$ > '"
        "--input-border"
        "--input-label=' Input '"
        "--header-border"
        # "--header-label=' File Type '"
        "--list-border --multi --highlight-line --gap --pointer='>'"
        "--preview-border"
        "--preview='pistol {}'"
        "--bind 'focus:transform-preview-label:[ -n {} ] && printf \\\" Previewing [{}] \\\"'"
        # "--bind 'focus:+transform-header:file --brief {} || echo \\\" No file selected \\\"'"
      ];
      colors = {
        border = "#ca9ee6";
        label = "#cba6f7";
        preview-border = "#f2d5cf";
        preview-label = "#f5e0dc";
        list-border = "#81c8be";
        list-label = "#94e2d5";
        input-border = "#ea999c";
        input-label = "#eba0ac";
        header-border = "#85c1dc";
        header-label = "#74c7ec";
        info = "#cba6f7";
        pointer = "#f5e0dc";
        spinner = "#f5e0dc";
        hl = "#f38ba8";
        marker = "#b4befe";
        "fg+" = "#cdd6f4";
        prompt = "#cba6f7";
        "hl+" = "#f38ba8";
        selected-bg = "#45475a";
      };
      changeDirWidgetCommand = "fd --type d"; # ALT-C
      fileWidgetCommand = "fd --type f"; # CTRL-T
      # CTRL-R
      historyWidgetOptions = [
        "--sort"
        "--exact"
      ];
      tmux = {
        enableShellIntegration = true;
        shellIntegrationOptions = [ "-d 60%" ];
      };
    };

    gh = {
      enable = true;
      gitCredentialHelper = {
        enable = true;
        hosts = [ "https://github.com" ];
      };
      extensions = with pkgs; [
        gh-actions-cache
        gh-cal
        gh-contribs
        gh-copilot
        gh-dash
        gh-eco
        gh-f
        gh-i
        gh-markdown-preview
        gh-notify
        gh-poi
        gh-s
        gh-screensaver
      ];
      settings = {
        git_protocol = "ssh";
        editor = "nvim";
        aliases = { };
      };
    };

    gh-dash = {
      enable = true;
    };

    lazygit = {
      enable = true;
      settings = {
        gui = {
          mouseEvents = true;
          language = "en";
          timeFormat = "2022-11-03 15:04"; # https://pkg.go.dev/time#Time.Format
          shortTimeFormat = "15:04";
          showRandomTip = false;
          nerdFontsVersion = "3";
          useHunkModeInStagingView = true;
        };
        git = {
          paging = {
            pager = "delta --dark --paging=never";
            externalDiffCommand = "difft --color=always";
          };
          commit = {
            signoff = false;
            autoWrapCommitMessage = true;
            autoWrapWidth = 72;
          };
          parseEmoji = true;
        };
        update = {
          method = "never";
        };
        refresher = {
          fetchInterval = 600;
        };
        os = {
          openDirInEditor = "nvim";
          editPreset = "nvim";
        };
        notARepository = "skip"; # one of: 'prompt' | 'create' | 'skip' | 'quit'
        promptToReturnFromSubprocess = false;
      };
    };

    neovim = {
      enable = true;
      # package = pkgs.neovim-nightly;
      withNodeJs = true;
      withPython3 = true;
      withRuby = false;
      extraPackages = with pkgs; [
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
        lua5_1
        luajitPackages.luarocks-nix
      ];
      extraWrapperArgs = [
        "--suffix"
        "LIBRARY_PATH"
        ":"
        "${lib.makeLibraryPath [
          # manylinux
          pkgs.bzip2
          pkgs.curl
          pkgs.libsodium
          pkgs.libssh
          pkgs.libxml2
          pkgs.openssl
          pkgs.stdenv.cc.cc
          pkgs.stdenv.cc.cc.lib
          pkgs.util-linux
          pkgs.xz
          pkgs.zlib
          pkgs.zstd
          # Packages not included in `nix-ld`'s NixOSModule
          pkgs.glib
          pkgs.libcxx
        ]}"
        "--suffix"
        "PKG_CONFIG_PATH"
        ":"
        "${lib.makeSearchPathOutput "dev" "lib/pkgconfig" [
          # manylinux
          pkgs.bzip2
          pkgs.curl
          pkgs.libsodium
          pkgs.libssh
          pkgs.libxml2
          pkgs.openssl
          pkgs.stdenv.cc.cc
          pkgs.stdenv.cc.cc.lib
          pkgs.util-linux
          pkgs.xz
          pkgs.zlib
          pkgs.zstd
          # Packages not included in `nix-ld`'s NixOSModule
          pkgs.glib
          pkgs.libcxx
        ]}"
      ];
      extraPython3Packages =
        pyPkgs: with pyPkgs; [
          docformatter
          pynvim
        ];
      extraLuaPackages =
        luajitPackages: with luajitPackages; [
          sqlite
          luv
          luasnip
          fzf-lua
          fzy
        ];
    };

    nix-search-tv = {
      enable = true;
      enableTelevisionIntegration = true;
      settings = {
        experimental = {
          render_docs_indexes = {
            nvf = "https://notashelf.github.io/nvf/options.html";
          };
        };
      };
    };

    television = {
      enable = true;
      enableZshIntegration = true;
    };

    tmux = {
      enable = true;
      clock24 = true;
      mouse = true;
      secureSocket = true;
      terminal = "tmux-256-color";
      plugins = with pkgs; [
        tmuxPlugins.better-mouse-mode
        tmuxPlugins.tmux-fzf # prefix + F
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

    yazi = {
      enable = true;
      # enableZshIntegration = true;
      settings = {
        mgr = {
          ratio = [
            2
            4
            3
          ];
          show_hidden = true;
          sort_by = "natural";
          sort_dir_first = true;
        };
      };
    };

    vivid = {
      enable = true;
      enableZshIntegration = true;
      filetypes = {
        text = {
          licenses = [
            "LICENCE"
            "COPYRIGHT"
          ];
          special = [
            "CHANGELOG.md"
            "CODE_OF_CONDUCT.md"
            "CONTRIBUTING.md"
          ];
          todo = [
            "TODO.md"
            "TODO.txt"
          ];
        };
      };
      activeTheme = "tokyonight-moon";
    };

    zsh = {
      enable = true;
      dotDir = "${config.xdg.configHome}/zsh";
      zprof.enable = false;
      enableCompletion = false;
      enableVteIntegration = true;
      # defaultKeymap = "vicmd";
      antidote = {
        enable = true;
        useFriendlyNames = true;
        plugins = [
          # oh-my-zsh plugins
          "getantidote/use-omz" # handle OMZ dependencies
          "ohmyzsh/ohmyzsh path:lib" # load OMZ's library
          "ohmyzsh/ohmyzsh path:plugins/colored-man-pages kind:defer" # load OMZ plugins
          # lazy-loading `kind:defer`
          "QuarticCat/zsh-smartcache" # better mroth/evalcache
          "zsh-users/zsh-completions kind:fpath"
          "belak/zsh-utils path:completion"
          "Aloxaf/fzf-tab kind:defer" # needs to load after `compinit`, but before wrap widgets, such as `zsh-autosuggestions` or `fast-syntax-highlighting`
          "zsh-users/zsh-autosuggestions kind:defer"
          "zdharma-continuum/fast-syntax-highlighting kind:defer" # add before zsh-history-substring-search to prevent breaking
          "zpm-zsh/colorize kind:defer" # Colorize the output of various programs
          "zpm-zsh/colors" # Enhanced colors for zsh
          "Freed-Wu/zsh-help" # colorize `XXX --help`
          "zsh-users/zsh-history-substring-search kind:defer"
          "MichaelAquilina/zsh-you-should-use kind:defer"
          # "MichaelAquilina/zsh-autoswitch-virtualenv kind:defer" # Auto-switch python venv, pipenv, poetry
          "sunlei/zsh-ssh kind:defer"
        ];
      };
      initContent = ''
        ${builtins.readFile ./conf.d/zsh/completion.zsh}
        ${builtins.readFile ./conf.d/zsh/setopt.zsh}
        ${builtins.readFile ./conf.d/zsh/exports.zsh}
        ${builtins.readFile ./conf.d/zsh/history.zsh}
        ${builtins.readFile ./conf.d/zsh/functions.zsh}
        ${builtins.readFile ./conf.d/zsh/bindkeys.zsh}
        ${builtins.readFile ./conf.d/zsh/history.zsh}
        ${builtins.readFile ./conf.d/zsh/plugins.zsh}
        ${builtins.readFile ./conf.d/zsh/aliases.zsh}
        ${builtins.readFile ./conf.d/zsh/macos.zsh}
        ${builtins.readFile ./conf.d/zsh/hashdirs.zsh}
      '';
    };
  };
}
