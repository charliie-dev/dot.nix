{ config, ... }:
{
  nh = {
    enable = true;
    homeFlake = "${config.xdg.configHome}/home-manager";
    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = "--keep 5 --keep-since 3d";
    };
  };
}
