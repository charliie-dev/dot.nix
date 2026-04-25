{
  config,
  pkgs,
  lib,
  src,
  roles ? [ ],
  enableSecrets ? false,
  ...
}:
let
  nvimdots_url = "charliie-dev/nvimdots.lua.git";
  inherit (import "${src}/modules/apps/_common.nix" { inherit pkgs; }) common_apps;
  role_pkgs = lib.concatMap (
    r: (import "${src}/modules/apps/roles/${r}.nix" { inherit config pkgs; }).packages
  ) roles;
  merged_pkgs = lib.unique (common_apps ++ role_pkgs);
in
lib.mkMerge [
  {
    inherit (import "${src}/modules/nix-config.nix" { inherit pkgs; }) nix;

    manual = {
      manpages.enable = false;
      json.enable = false;
      html.enable = false;
    };

    home = {
      packages = merged_pkgs;
      shell.enableZshIntegration = true;
      sessionPath = [ "/nix/var/nix/profiles/default/bin" ];
      sessionVariables = {
        # Disable Determinate Nix telemetry
        # https://docs.determinate.systems/guides/telemetry/
        NIX_SENTRY_ENDPOINT = "";
        DETSYS_IDS_TELEMETRY = "disabled";
      };
      file = {
        ".config/parallel/will-cite" = {
          text = "";
        };
        ".config/terraform/terraformrc" = {
          text = ''
            plugin_cache_dir   = "$HOME/.local/share/terraform/plugin-cache"
            disable_checkpoint = true
          '';
        };
        ".config/tirith/policy.yaml" = {
          source = "${src}/conf.d/tirith/policy.yaml";
        };
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
        nvimdotsClone = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
          if [ ! -d ${config.xdg.configHome}/nvim ]; then
            ${pkgs.git}/bin/git clone https://github.com/${nvimdots_url} ${config.xdg.configHome}/nvim
          fi
          cd ${config.xdg.configHome}/nvim
          ${pkgs.git}/bin/git remote set-url origin git@github.com:${nvimdots_url}
        '';
        initDataDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          # SSH
          mkdir -p ${config.home.homeDirectory}/.ssh
          chmod 700 ${config.home.homeDirectory}/.ssh

          # GPG
          mkdir -p ${config.xdg.dataHome}/gnupg
          chmod 700 ${config.xdg.dataHome}/gnupg
          if [ -n "$(ls -A ${config.xdg.dataHome}/gnupg/ 2>/dev/null)" ]; then
            chmod 600 ${config.xdg.dataHome}/gnupg/*
          fi

          # Tool data dirs
          mkdir -p ${config.xdg.dataHome}/dotnet
          mkdir -p ${config.xdg.dataHome}/aws
        '';
        topgradeCopy = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [ ! -f ${config.xdg.configHome}/topgrade.d/disable.toml ]; then
            mkdir -p ${config.xdg.configHome}/topgrade.d
            cp "${src}/conf.d/topgrade/disable.toml" ${config.xdg.configHome}/topgrade.d/disable.toml
          fi
        '';
      };
    };

    inherit
      (import "${src}/modules/xdg-config.nix" {
        inherit
          config
          pkgs
          lib
          src
          ;
      })
      xdg
      ;
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
      inherit (import "${src}/modules/apps/gh-dash.nix") gh-dash;
      inherit (import "${src}/modules/apps/gh.nix" { inherit pkgs; }) gh;
      inherit (import "${src}/modules/apps/git.nix" { inherit config; }) git;
      inherit (import "${src}/modules/apps/hstr.nix") hstr;
      inherit (import "${src}/modules/apps/hwatch.nix") hwatch;
      inherit (import "${src}/modules/apps/lazydocker.nix") lazydocker;
      inherit (import "${src}/modules/apps/lazygit.nix") lazygit;
      inherit (import "${src}/modules/apps/lsd.nix") lsd;
      inherit (import "${src}/modules/apps/man.nix") man;
      inherit (import "${src}/modules/apps/mise.nix") mise;
      inherit (import "${src}/modules/apps/neovim.nix" { inherit pkgs lib; }) neovim;
      inherit (import "${src}/modules/apps/nh.nix" { inherit config; }) nh;
      inherit (import "${src}/modules/apps/nix-index.nix") nix-index;
      inherit (import "${src}/modules/apps/nix-search-tv.nix") nix-search-tv;
      inherit (import "${src}/modules/apps/pistol.nix") pistol;
      inherit (import "${src}/modules/apps/ripgrep-all.nix") ripgrep-all;
      inherit (import "${src}/modules/apps/ripgrep.nix") ripgrep;
      inherit (import "${src}/modules/apps/snitch.nix") snitch;
      inherit (import "${src}/modules/apps/ssh.nix" { inherit config; }) ssh;
      inherit (import "${src}/modules/apps/starship.nix" { inherit config lib; }) starship;
      inherit (import "${src}/modules/apps/television.nix") television;
      inherit (import "${src}/modules/apps/tirith.nix") tirith;
      inherit (import "${src}/modules/apps/tmux.nix" { inherit pkgs src; }) tmux;
      inherit (import "${src}/modules/apps/topgrade.nix") topgrade;
      inherit (import "${src}/modules/apps/vivid.nix") vivid;
      inherit (import "${src}/modules/apps/yazi.nix" { inherit pkgs; }) yazi;
      inherit (import "${src}/modules/apps/zoxide.nix") zoxide;
      inherit (import "${src}/modules/apps/zsh.nix" { inherit config pkgs src; }) zsh;
    };

    services = {
      inherit (import "${src}/modules/services/home-manager.nix" { }) home-manager;
    };
  }
  (lib.mkIf pkgs.stdenv.isDarwin {
    launchd.agents = import "${src}/modules/services/colima.nix" { inherit config pkgs; };
    home.activation.unloadColimaAgent = lib.hm.dag.entryBefore [ "setupLaunchAgents" ] ''
      if /bin/launchctl print gui/$(id -u)/com.github.abiosoft.colima &>/dev/null; then
        /bin/launchctl bootout gui/$(id -u)/com.github.abiosoft.colima
      fi
    '';
  })
  (lib.mkIf enableSecrets (
    let
      sopsConfig = import "${src}/modules/sops.nix" { inherit config src; };
      dopplerConfig = import "${src}/modules/doppler.nix" { inherit config pkgs lib; };
    in
    {
      inherit (sopsConfig) sops;

      home = {
        inherit (dopplerConfig.doppler) packages;
        activation = dopplerConfig.doppler.activation // {
          ssh = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
            if [ -f ${config.home.homeDirectory}/.ssh/id_ed25519.pub ]; then
              if [ ! -f ${config.home.homeDirectory}/.ssh/authorized_keys ]; then
                touch ${config.home.homeDirectory}/.ssh/authorized_keys
              fi
              # Compare key type + body (cols 1-2), ignoring the comment field
              read -r ktype kbody _ < ${config.home.homeDirectory}/.ssh/id_ed25519.pub
              if ! grep -qF "$ktype $kbody" ${config.home.homeDirectory}/.ssh/authorized_keys; then
                cat ${config.home.homeDirectory}/.ssh/id_ed25519.pub >> ${config.home.homeDirectory}/.ssh/authorized_keys
              fi
            fi
          '';
        };
      };

      programs = {
        git.signing.key = "${config.sops.secrets.ssh_ed25519_pub.path}";
        git.settings.gpg.ssh.allowedSignersFile = "${config.sops.secrets.allowed_signers.path}";
        ssh.matchBlocks."*".identityFile = "${config.sops.secrets.ssh_ed25519.path}";
        zsh.envExtra = ''
          # Load Doppler secrets (application-layer)
          if [ -r "${config.xdg.dataHome}/doppler/env" ]; then
            set -a
            source "${config.xdg.dataHome}/doppler/env"
            set +a
          fi
        '';
      };
    }
  ))
]
