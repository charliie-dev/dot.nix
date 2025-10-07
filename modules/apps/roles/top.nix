{ pkgs, ... }:
{
  packages = with pkgs; [
    htop # Interactive process viewer
    s-tui # Stress-Terminal UI monitoring tool
    iftop # Display bandwidth usage on a network interface
    dua # Tool to learn about the disk usage of directories
  ];
}
