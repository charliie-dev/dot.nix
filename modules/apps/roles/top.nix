{ pkgs, ... }:
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
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      s-tui # Stress-Terminal UI monitoring tool
      iotop-c # Top-like UI for monitoring I/O usage (C port of iotop)
      wavemon # ncurses Wi-Fi signal and statistics monitor
    ]
    ++ lib.optional (lib.meta.availableOn stdenv.hostPlatform gpufetch) gpufetch
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      docker-client # Docker CLI (client only, no daemon)
      docker-credential-helpers # docker-credential-osxkeychain (credsStore in ~/.config/docker/config.json)
      macpm # Perf monitoring CLI tool for Apple Silicon
    ];
}
