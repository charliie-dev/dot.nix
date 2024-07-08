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
    tmux
    unzip
    vim
    wget
    xdg-ninja
    zsh
    # c/c++ cli
    btop
    fzy
    jq
    lnav
    # python cli
    git-fame
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
    ".zshenv".source = ./conf.d/zsh/.zshenv;
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
    "tmux" = {
      recursive = true;
      source = ./conf.d/tmux;
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
}
