{ config, pkgs, ... }:
let
  logDir = "${config.home.homeDirectory}/Library/Logs/colima";
in
{
  colima = {
    enable = true;
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
