{
  config,
  lib,
  pkgs,
  ...
}:

# Colima is the Darwin Docker host; Linux uses its system Docker service.
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
    # Colima uses the GUI domain for VZ; skip the wrapper so it appears under its own name.
    waitForNixStore = false;
    # services.colima only forwards DOCKER_CONFIG when programs.docker-cli is
    # enabled. Use the mutable XDG config managed by modules/runtime/docker.nix.
    config.EnvironmentVariables.DOCKER_CONFIG = "${config.xdg.configHome}/docker";
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
