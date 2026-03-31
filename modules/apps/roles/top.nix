{ pkgs, ... }:
{
  packages = with pkgs; [
    htop # Interactive process viewer
    iftop # Display bandwidth usage on a network interface
    dua # Tool to learn about the disk usage of directories

    # System info
    fastfetch # System info tool
    onefetch # Git repo summary
    cpufetch # CPU architecture info
  ];
}
