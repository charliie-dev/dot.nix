{ config, ... }:
{
  home-manager = {
    autoUpgrade = {
      enable = true;
      useFlake = true;
      flakeDir = "${config.xdg.configHome}/home-manager";
      frequency = "weekly";
    };
    autoExpire = {
      store = {
        cleanup = true;
        options = "--delete-older-than 7d";
        timestamp = "-7 days";
      };
      frequency = "weekly";
    };
  };
}
