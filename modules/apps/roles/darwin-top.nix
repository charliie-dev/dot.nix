{ pkgs, ... }:
{
  packages = with pkgs; [
    colima # Container runtimes on macOS with minimal setup
    docker-client # Docker CLI (client only, no daemon)
    macpm # Perf monitoring CLI tool for Apple Silicon, ; previously named 'asitop'
  ];
}
