{ pkgs, ... }:
{
  packages = with pkgs; [
    macpm # Perf monitoring CLI tool for Apple Silicon, ; previously named 'asitop'
  ];
}
