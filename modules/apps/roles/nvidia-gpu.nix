{ pkgs, ... }:
{
  packages = with pkgs; [
    nvtopPackages.nvidia # GPU process monitor (htop-like) for NVIDIA
  ];
}
