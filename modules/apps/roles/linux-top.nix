{ pkgs, ... }:
{
  packages = with pkgs; [
    s-tui # Stress-Terminal UI monitoring tool
    iotop-c
    wavemon
  ];
}
