{
  config,
  lib,
  pkgs,
  ...
}:

# Colima is the Darwin Docker host; Linux uses its system Docker service.
let
  profile = config.services.colima.profiles.default;
in
lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
  services.colima = {
    enable = true;

    profiles.default = {
      isActive = true;
      isService = true;
      # The active Docker context selects Colima. Avoid an environment variable
      # that would override all contexts and remain stale across VM migrations.
      setDockerHost = false;

      settings = {
        cpu = 6;
        memory = 12;
        disk = 100;
        runtime = "docker";
        kubernetes.enabled = false;
        vmType = "vz";
        mountType = "virtiofs";
        mountInotify = true;
      };
    };
  };

  launchd.agents.colima-default = {
    # Colima uses the GUI domain for VZ. Skip HM's /bin/sh wait4path wrapper so
    # the agent appears as colima-default rather than sh.
    waitForNixStore = false;
    config = {
      # services.colima only forwards DOCKER_CONFIG when programs.docker-cli is
      # enabled. Use the mutable XDG config managed by modules/runtime/docker.nix.
      EnvironmentVariables.DOCKER_CONFIG = "${config.xdg.configHome}/docker";
      # Lima leaves vz.pid/ha.pid behind when the host agent dies on shutdown. After
      # a reboot the PID can be reused by an unrelated process. Lima then refuses
      # to start ("vz driver is running but host agent is not"). Before starting,
      # drop pid files whose process is not limactl. mkForce replaces upstream's
      # ProgramArguments, so the exec line mirrors its `colima start` flags; Lima
      # names the default profile's instance "colima".
      ProgramArguments = lib.mkForce [
        "${pkgs.writeShellScript "colima-default-start" ''
          for pidfile in "''${LIMA_HOME:-$COLIMA_HOME/_lima}"/colima/{vz,ha}.pid; do
            [ -f "$pidfile" ] || continue
            comm=$(/bin/ps -p "$(<"$pidfile")" -o comm= 2>/dev/null)
            case "$comm" in
              # nixpkgs runs it as .limactl-wrapped
              *limactl*) ;;
              *) echo "removing stale $pidfile (pid owner: ''${comm:-none})"; rm -f "$pidfile" ;;
            esac
          done
          exec ${lib.getExe config.services.colima.package} start default -f \
            --activate=${lib.boolToString profile.isActive} \
            --save-config=${lib.boolToString (profile.settings == { })}
        ''}"
      ];
      # Upstream only restarts on exit 0; also retry after failures, throttled.
      KeepAlive = lib.mkForce true;
      ThrottleInterval = 30;
    };
  };

  # launchd does not create parents for StandardOutPath. Ensure the native
  # module's default $XDG_STATE_HOME/colima/default.log can be opened before the
  # agent is bootstrapped.
  home.activation.colimaStateDir =
    lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ]
      ''
        mkdir -p "${config.xdg.stateHome}/colima"
        chmod 700 "${config.xdg.stateHome}/colima"
      '';
}
