{
  config,
  pkgs,
  lib,
  roles ? [ ],
  ...
}:
let
  inherit (import ./apps/_common.nix { inherit pkgs; }) common_apps;
  inherit (import ./catppuccin.nix) catppuccin;
  special_config = (import ./xdg-config.nix).home.file;
  xdg_config = (import ./xdg-config.nix).xdg;
  role_pkgs = lib.concatMap (
    r: (import ./apps/roles/${r}.nix { inherit config pkgs; }).packages
  ) roles;
  merged_pkgs = lib.unique (common_apps ++ role_pkgs);
in
{
  inherit (import ./nix-config.nix { inherit pkgs; }) nix;

  home = {
    packages = merged_pkgs;
    file = special_config;

    activation.nvimdotsActivatioinAction = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -d ~/.config/nvim ]; then
        ${pkgs.git}/bin/git clone https://github.com/CharlesChiuGit/nvimdots.lua.git ~/.config/nvim
      fi
    '';
  };
  xdg = xdg_config;

  inherit catppuccin;

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
