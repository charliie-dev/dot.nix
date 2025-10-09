{
  config,
  pkgs,
  lib,
  roles ? [ ],
  ...
}:
let
  nvimdots_url = "CharlesChiuGit/nvimdots.lua.git";
  inherit (import ./apps/_common.nix { inherit pkgs; }) common_apps;
  role_pkgs = lib.concatMap (
    r: (import ./apps/roles/${r}.nix { inherit config pkgs; }).packages
  ) roles;
  merged_pkgs = lib.unique (common_apps ++ role_pkgs);
in
{
  inherit (import ./nix-config.nix { inherit pkgs; }) nix;

  home = {
    packages = merged_pkgs;
    file = {
      "self-made commands" = {
        enable = true;
        recursive = true;
        executable = true;
        # 1. don't quote "../conf.d/Usercommand" for `source` needs to be `absolute path`
        # 2. use "${config.xdg.configHome}/home-manager/conf.d/Usercommand" will need to use `home-manager switch --impure`
        source = ../conf.d/Usercommand;
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
          cp ./topgrade/disable.toml ${config.xdg.configHome}/topgrade.d/disable.toml
        fi
      '';
      sshCopy = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -f ${config.home.homeDirectory}/.ssh/config ]; then
          cd ${config.xdg.configHome}/home-manager/conf.d/
          cp ./ssh/config ${config.home.homeDirectory}/.ssh/config
        fi
      '';
    };
  };

  inherit (import ./xdg-config.nix) xdg;
  inherit (import ./catppuccin.nix) catppuccin;

  programs = {
    inherit (import ./apps/home-manager.nix) home-manager;
    inherit (import ./apps/bat.nix { inherit pkgs; }) bat;
    inherit (import ./apps/btop.nix) btop;
    inherit (import ./apps/fd.nix) fd;
    inherit (import ./apps/fzf.nix) fzf;
    inherit (import ./apps/gh-dash.nix) gh-dash;
    inherit (import ./apps/gh.nix { inherit pkgs; }) gh;
    inherit (import ./apps/hwatch.nix) hwatch;
    inherit (import ./apps/lazydocker.nix) lazydocker;
    inherit (import ./apps/lazygit.nix) lazygit;
    inherit (import ./apps/lsd.nix) lsd;
    inherit (import ./apps/mise.nix) mise;
    inherit (import ./apps/neovim.nix { inherit pkgs lib; }) neovim;
    inherit (import ./apps/nix-search-tv.nix) nix-search-tv;
    inherit (import ./apps/pistol.nix) pistol;
    inherit (import ./apps/ripgrep-all.nix) ripgrep-all;
    inherit (import ./apps/ripgrep.nix) ripgrep;
    inherit (import ./apps/starship.nix { inherit config lib; }) starship;
    inherit (import ./apps/television.nix) television;
    inherit (import ./apps/tmux.nix { inherit pkgs; }) tmux;
    inherit (import ./apps/topgrade.nix) topgrade;
    inherit (import ./apps/vivid.nix) vivid;
    inherit (import ./apps/yazi.nix) yazi;
    inherit (import ./apps/zoxide.nix) zoxide;
    inherit (import ./apps/zsh.nix { inherit config pkgs; }) zsh;
  };
}
