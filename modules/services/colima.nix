{ config, ... }:
{
  colima = {
    enable = true;
    config = {
      Label = "com.github.abiosoft.colima";
      ProgramArguments = [
        "colima"
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
        COLIMA_HOME = "${config.xdg.dataHome}/colima";
        PATH = "${config.home.homeDirectory}/.local/state/nix/profile/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
      RunAtLoad = true;
      KeepAlive = false;
      StandardOutPath = "/tmp/colima.stdout.log";
      StandardErrorPath = "/tmp/colima.stderr.log";
    };
  };
}
