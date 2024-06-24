{ pkgs, lib, ... }:
with lib;
{
  # home.username = lib.strings.removeSuffix "\n" (builtins.readFile /etc/hostname);
  home.username = "charles";
  home.homeDirectory = builtins.getEnv "HOME";
  home.stateVersion = "24.05";
  programs.home-manager.enable = true;

  # https://search.nixos.org/packages?query=
  # https://home-manager-options.extranix.com/?query=
  home.packages = with pkgs; [
    gnutar
    gzip
    unzip
    xdg-ninja
    curl
    wget
    gnupg
    zsh
    git
    vim
    tmux
    chafa
    # c/c++ cli
    btop
    fzy
    lnav
    jq
    # python cli
    git-fame
    # golang cli
    fzf
    glow
    lazydocker
    lazygit
    lf
    nix-search-cli
    pistol
    # vfox ## TODO: https://github.com/version-fox/vfox/issues/53
    # rust cli
    bat
    eza
    delta
    dua
    eva
    fd
    ripgrep
    ripgrep-all
    ripsecrets
    sd
    tokei
    tree-sitter
    xh
    # xq
    jaq
    mise
    # joshuto
    lsd
    starship
    topgrade
    zellij
    zoxide
    rye # like cargo but for python
    uv # pip in rust
    fh # official CLI for FlakeHub
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
    "lf" = {
      recursive = true;
      source = ./conf.d/lf;
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
