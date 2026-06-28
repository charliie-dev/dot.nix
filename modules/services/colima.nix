{ config, pkgs, ... }:
let
  logDir = "${config.home.homeDirectory}/Library/Logs/colima";
in
{
  colima = {
    enable = true;
    # Keep the option's `gui` domain default — do NOT move to `user`. The
    # `--vm-type vz` backend (Apple Virtualization.framework) requires the
    # graphical Aqua session; bootstrapping into the background `user` domain
    # fails with `Bootstrap failed: 5: Input/output error`. Verified 2026-06-28.
    config = {
      Label = "com.github.abiosoft.colima";
      ProgramArguments = [
        "${pkgs.colima}/bin/colima"
        "start"
        "--foreground"
        "--cpu"
        "6"
        "--memory"
        "12"
        "--disk"
        "100"
        "--vm-type"
        "vz"
        "--mount-type"
        "virtiofs"
        "--mount-inotify"
      ];
      EnvironmentVariables = {
        PATH = "${pkgs.colima}/bin:${pkgs.docker-client}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        COLIMA_HOME = "${config.xdg.dataHome}/colima";
        DOCKER_CONFIG = "${config.xdg.configHome}/docker";
      };
      RunAtLoad = true;
      KeepAlive = {
        SuccessfulExit = false;
      };
      ThrottleInterval = 60;
      StandardOutPath = "${logDir}/colima.log";
      StandardErrorPath = "${logDir}/colima.log";
    };
  };
}
