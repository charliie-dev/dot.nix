{ pkgs, ... }:
let
  inherit (pkgs) lib stdenv;
in
{
  packages =
    with pkgs;
    [
      htop # Interactive process viewer
      iftop # Display bandwidth usage on a network interface
      dua # Tool to learn about the disk usage of directories

      # System info
      fastfetch # System info tool
      onefetch # Git repo summary
      cpufetch # CPU architecture info
    ]
    ++ lib.optionals stdenv.isLinux [
      s-tui # Stress-Terminal UI monitoring tool
      iotop-c
      wavemon
      gpufetch # GPU architecture info
    ]
    ++ lib.optionals stdenv.isDarwin [
      colima # Container runtimes on macOS with minimal setup
      docker-client # Docker CLI (client only, no daemon)
      macpm # Perf monitoring CLI tool for Apple Silicon
    ];
}
