{ pkgs, ... }:
{
  packages = with pkgs; [
    nvtopPackages.nvidia
  ];
}
