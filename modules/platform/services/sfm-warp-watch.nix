{
  config,
  lib,
  pkgs,
  ...
}:
let
  source = pkgs.writeText "sfm-warp-watch.py" (
    builtins.readFile ../../../conf.d/sfm-warp-maintenance/watch.py
  );
  watch = pkgs.writeShellApplication {
    name = "sfm-watch";
    text = ''
      exec ${pkgs.python3}/bin/python3 -IS ${source} "$@"
    '';
  };
  agent = {
    enable = true;
    waitForNixStore = false;
    config = {
      ProgramArguments = [
        "${watch}/bin/sfm-watch"
        "check"
        "--allow-sfm-direct-probe"
      ];
      EnvironmentVariables.XDG_STATE_HOME = config.xdg.stateHome;
      StartInterval = 60;
      RunAtLoad = true;
      ProcessType = "Background";
    };
  };
in
lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
  home.packages = [ watch ];
  launchd.agents.sfm-warp-watch = agent;
}
