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
  inherit (import "${src}/modules/agenix.nix" { inherit config src; }) age;

  home = {
    packages = merged_pkgs;
    shell.enableZshIntegration = true;
    sessionPath = [ "/nix/var/nix/profiles/default/bin" ];
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
      sshDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -d ${config.home.homeDirectory}/.ssh ]; then
          mkdir -p ${config.home.homeDirectory}/.ssh
        fi
        chmod 700 ${config.home.homeDirectory}/.ssh
      '';
      ssh = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
        if [ ! -f ${config.home.homeDirectory}/.ssh/authorized_keys ]; then
          touch ${config.home.homeDirectory}/.ssh/authorized_keys
        fi
        if grep -q "charles@home-manager" "${config.home.homeDirectory}/.ssh/authorized_keys"; then
          exit 0
        else
          (cat ${config.home.homeDirectory}/.ssh/id_ed25519.pub) >> ${config.home.homeDirectory}/.ssh/authorized_keys
        fi
      '';
      gpgFixup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -d ${config.xdg.dataHome}/gnupg ]; then
          mkdir -p ${config.xdg.dataHome}/gnupg
        fi
        if [ "$(ls -A ${config.xdg.dataHome}/gnupg/)" ]; then
          chmod 600 ${config.xdg.dataHome}/gnupg/*
        fi
        chmod 700 ${config.xdg.dataHome}/gnupg
      '';
      dotnetFixup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -d ${config.xdg.dataHome}/dotnet ]; then
          mkdir -p ${config.xdg.dataHome}/dotnet
        fi
      '';
      awsFixup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -d ${config.xdg.dataHome}/aws ]; then
          mkdir -p ${config.xdg.dataHome}/aws
        fi
      '';
      topgradeCopy = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -f ${config.xdg.configHome}/topgrade.d/disable.toml ]; then
          cd ${config.xdg.configHome}/home-manager/conf.d/
          cp "${src}/conf.d/topgrade/disable.toml" ${config.xdg.configHome}/topgrade.d/disable.toml
        fi
      '';
    };
  };

  inherit (import "${src}/modules/xdg-config.nix" { inherit src; }) xdg;
  inherit (import "${src}/modules/catppuccin.nix") catppuccin;

  programs = {
    inherit (import "${src}/modules/apps/home-manager.nix") home-manager;
    inherit (import "${src}/modules/apps/asciinema.nix") asciinema;
    inherit (import "${src}/modules/apps/bat.nix" { inherit pkgs; }) bat;
    inherit (import "${src}/modules/apps/btop.nix") btop;
    inherit (import "${src}/modules/apps/carapace.nix") carapace;
    inherit (import "${src}/modules/apps/delta.nix") delta;
    inherit (import "${src}/modules/apps/difftastic.nix") difftastic;
    inherit (import "${src}/modules/apps/fd.nix") fd;
    inherit (import "${src}/modules/apps/fzf.nix") fzf;
    # inherit (import "${src}/modules/apps/gcc.nix") gcc;
    inherit (import "${src}/modules/apps/gh-dash.nix") gh-dash;
    inherit (import "${src}/modules/apps/gh.nix" { inherit pkgs; }) gh;
    inherit (import "${src}/modules/apps/git.nix" { inherit config; }) git;
    inherit (import "${src}/modules/apps/hwatch.nix") hwatch;
    inherit (import "${src}/modules/apps/lazydocker.nix") lazydocker;
    inherit (import "${src}/modules/apps/lazygit.nix") lazygit;
    inherit (import "${src}/modules/apps/lsd.nix") lsd;
    inherit (import "${src}/modules/apps/mise.nix") mise;
    inherit (import "${src}/modules/apps/neovim.nix" { inherit pkgs lib; }) neovim;
    inherit (import "${src}/modules/apps/nix-index.nix") nix-index;
    inherit (import "${src}/modules/apps/nix-search-tv.nix") nix-search-tv;
    inherit (import "${src}/modules/apps/pistol.nix") pistol;
    inherit (import "${src}/modules/apps/ripgrep-all.nix") ripgrep-all;
    inherit (import "${src}/modules/apps/ripgrep.nix") ripgrep;
    inherit (import "${src}/modules/apps/ssh.nix" { inherit config; }) ssh;
    inherit (import "${src}/modules/apps/starship.nix" { inherit config lib; }) starship;
    inherit (import "${src}/modules/apps/television.nix") television;
    inherit (import "${src}/modules/apps/tmux.nix" { inherit pkgs src; }) tmux;
    inherit (import "${src}/modules/apps/topgrade.nix") topgrade;
    inherit (import "${src}/modules/apps/vivid.nix") vivid;
    inherit (import "${src}/modules/apps/yazi.nix") yazi;
    inherit (import "${src}/modules/apps/zoxide.nix") zoxide;
    inherit (import "${src}/modules/apps/zsh.nix" { inherit config pkgs src; }) zsh;
  };

  # services = {
  #   inherit (import "${src}/modules/services/ssh-agent.nix") ssh-agent;
  # };
}
