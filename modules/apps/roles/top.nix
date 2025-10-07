{ pkgs, ... }:
{
  packages = with pkgs; [
    htop # Interactive process viewer
    iftop # Display bandwidth usage on a network interface
    dua # Tool to learn about the disk usage of directories
  ];
}
