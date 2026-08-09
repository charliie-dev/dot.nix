{
  config,
  pkgs,
  lib,
  src,
  ...
}:
lib.mkMerge [
  (lib.mkIf pkgs.stdenv.isDarwin {
    launchd.agents =
      (import "${src}/modules/services/colima.nix" { inherit config pkgs; })
      // (import "${src}/modules/services/brew-env.nix" { inherit config pkgs; })
      // {
        nh-clean = {
          # StartCalendarInterval only fires long after login, so the /bin/wait4path
          # wrapper buys nothing and just hides the agent as "sh" in Login Items.
          waitForNixStore = false;
          config = {
            # launchd inherits a minimal PATH; nh shells out to `nix --version`.
            EnvironmentVariables.PATH = "/nix/var/nix/profiles/default/bin:${config.home.profileDirectory}/bin";
            # Upstream HM passes extraArgs as one list element, which HM then shell-quotes
            # into a single token and clap errors out. mkForce (listOf merges by
            # concatenation, so a plain definition would append) with the args split.
            ProgramArguments = lib.mkForce (
              [
                "${pkgs.nh}/bin/nh"
                "clean"
                "user"
              ]
              ++ lib.splitString " " config.programs.nh.clean.extraArgs
            );
          };
        };
      }
      # Agents owned by upstream modules — only flip the wrapper off so they show
      # under their own name. All are `gui` domain, i.e. they start after GUI login,
      # by which point the (FileVault-encrypted) Nix Store volume is mounted.
      //
        lib.genAttrs
          [
            "git-maintenance-hourly"
            "git-maintenance-daily"
            "git-maintenance-weekly"
            "sops-nix"
          ]
          (_: {
            waitForNixStore = false;
          });
    # NOTE: the former `unloadHMAgentsBeforeSetup` pre-bootout workaround was
    # removed — current home-manager's setupLaunchAgents is domain-aware and
    # boots each agent out of its old domain before bootstrapping (the exact
    # EIO race the workaround guarded against).
  })
  (lib.mkIf pkgs.stdenv.isLinux {
    home = {
      packages = [ pkgs.ghostty.terminfo ];
      sessionVariables = {
        TERMINFO_DIRS = "${config.home.profileDirectory}/share/terminfo\${TERMINFO_DIRS:+:}\${TERMINFO_DIRS}:/usr/share/terminfo";
        GTK_RC_FILES = "${config.xdg.configHome}/gtk-1.0/gtkrc";
        GTK2_RC_FILES = "${config.xdg.configHome}/gtk-2.0/gtkrc";
      };
    };
    # systemd user units don't source /etc/profile.d/nix.sh; nh shells out to `nix --version`.
    systemd.user.services.nh-clean.Service.Environment =
      "PATH=/nix/var/nix/profiles/default/bin:${config.home.profileDirectory}/bin";
  })
]
