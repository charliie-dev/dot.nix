{ config, pkgs, ... }:
{
  packages = with pkgs; [
    (config.lib.nixGL.wrappers.nvidiaPrime nvtopPackages.nvidia)
  ];
}
