{
  config,
  pkgs,
  lib,
  src,
  roles ? [ ],
  ...
}:
let
  nvimdots_url = "CharlesChiuGit/nvimdots.lua.git";
  inherit (import "${src}/modules/apps/_common.nix" { inherit pkgs; }) common_apps;
  role_pkgs = lib.concatMap (
    r: (import "${src}/modules/apps/roles/${r}.nix" { inherit config pkgs; }).packages
  ) roles;
  merged_pkgs = lib.unique (common_apps ++ role_pkgs);
in
{
  inherit (import "${src}/modules/nix-config.nix" { inherit pkgs; }) nix;

  home = {
    packages = merged_pkgs;
    file = {
      "self-made commands" = {
        enable = true;
        recursive = true;
        executable = true;
        # 1. don't quote "../conf.d/Usercommand" for `source` needs to be `absolute path`
        # 2. use "${config.xdg.configHome}/home-manager/conf.d/Usercommand" will need to use `home-manager switch --impure`
        source = "${src}/conf.d/Usercommand";
        target = ".local/bin";
      };
    };
    activation = {
      nvimdotsClone = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -d ${config.xdg.configHome}/nvim ]; then
          ${pkgs.git}/bin/git clone https://github.com/${nvimdots_url} ${config.xdg.configHome}/nvim
        fi
        cd ${config.xdg.configHome}/nvim
        ${pkgs.git}/bin/git remote set-url origin git@github.com:${nvimdots_url}
      '';
      gpgFixup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -d ${config.xdg.dataHome}/gnupg ]; then
          mkdir -p ${config.xdg.dataHome}/gnupg
        fi
        chmod 600 ${config.xdg.dataHome}/gnupg/*
        chmod 700 ${config.xdg.dataHome}/gnupg
      '';
      dotnetFixup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -d ${config.xdg.dataHome}/dotnet ]; then
          mkdir -p ${config.xdg.dataHome}/dotnet
        fi
      '';
      topgradeCopy = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -f ${config.xdg.configHome}/topgrade.d/disable.toml ]; then
          cd ${config.xdg.configHome}/home-manager/conf.d/
          cp "${src}/conf.d/topgrade/disable.toml" ${config.xdg.configHome}/topgrade.d/disable.toml
        fi
      '';
      sshCopy = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -f ${config.home.homeDirectory}/.ssh/config ]; then
          cd ${config.xdg.configHome}/home-manager/conf.d/
          cp "${src}/conf.d/ssh/config" ${config.home.homeDirectory}/.ssh/config
        fi
      '';
    };
  };

  inherit (import "${src}/modules/xdg-config.nix" { inherit src; }) xdg;
  inherit (import "${src}/modules/catppuccin.nix") catppuccin;

  programs = {
    inherit (import "${src}/modules/apps/home-manager.nix") home-manager;
    inherit (import "${src}/modules/apps/bat.nix" { inherit pkgs; }) bat;
    inherit (import "${src}/modules/apps/btop.nix") btop;
    inherit (import "${src}/modules/apps/fd.nix") fd;
    inherit (import "${src}/modules/apps/fzf.nix") fzf;
    inherit (import "${src}/modules/apps/gh-dash.nix") gh-dash;
    inherit (import "${src}/modules/apps/gh.nix" { inherit pkgs; }) gh;
    inherit (import "${src}/modules/apps/git.nix") git;
    inherit (import "${src}/modules/apps/hwatch.nix") hwatch;
    inherit (import "${src}/modules/apps/lazydocker.nix") lazydocker;
    inherit (import "${src}/modules/apps/lazygit.nix") lazygit;
    inherit (import "${src}/modules/apps/lsd.nix") lsd;
    inherit (import "${src}/modules/apps/mise.nix") mise;
    inherit (import "${src}/modules/apps/neovim.nix" { inherit pkgs lib; }) neovim;
    inherit (import "${src}/modules/apps/nix-search-tv.nix") nix-search-tv;
    inherit (import "${src}/modules/apps/pistol.nix") pistol;
    inherit (import "${src}/modules/apps/ripgrep-all.nix") ripgrep-all;
    inherit (import "${src}/modules/apps/ripgrep.nix") ripgrep;
    inherit (import "${src}/modules/apps/starship.nix" { inherit config lib; }) starship;
    inherit (import "${src}/modules/apps/television.nix") television;
    inherit (import "${src}/modules/apps/tmux.nix" { inherit pkgs src; }) tmux;
    inherit (import "${src}/modules/apps/topgrade.nix") topgrade;
    inherit (import "${src}/modules/apps/vivid.nix") vivid;
    inherit (import "${src}/modules/apps/yazi.nix") yazi;
    inherit (import "${src}/modules/apps/zoxide.nix") zoxide;
    inherit (import "${src}/modules/apps/zsh.nix" { inherit config pkgs src; }) zsh;
  };
}
