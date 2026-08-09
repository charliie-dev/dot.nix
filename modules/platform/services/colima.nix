{
  config,
  lib,
  pkgs,
  ...
}:

# Colima is the Darwin Docker host; Linux uses its system Docker service.
lib.mkIf pkgs.stdenv.isDarwin {
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

  # services.colima only forwards DOCKER_CONFIG when programs.docker-cli is
  # enabled. Our mutable config.json is managed by modules/runtime/docker.nix so
  # docker login can update it; make the launch agent use that same XDG path.
  launchd.agents.colima-default.config.EnvironmentVariables.DOCKER_CONFIG =
    "${config.xdg.configHome}/docker";

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
