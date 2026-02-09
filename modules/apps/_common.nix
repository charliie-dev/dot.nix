{ pkgs, ... }:
{
  common_apps = with pkgs; [
    curl
    gnupg
    vim
    unzip
    ouch # Painless compression and decompression in the terminal
    wget
    wget2
    fastfetch
    xdg-ninja
    tree
    lazyjournal
    tirith # Shell security tool that guards against homograph URL attacks, pip exploits, and other cli threats before they execxute

    # Secrets Management
    age
    agenix

    # Nix Utils
    nvd # Nix/NixOS package version diff tool
    nix-output-monitor # Pipe your nix-build output through the nix-output-monitor to get additional information while building.
    ### nix-build --log-format internal-json -v |& nom --json
    nix-tree # Interactively browse dependency graphs of Nix derivations.
    dix # A blazingly fast tool to diff Nix related things.

  ];
}
