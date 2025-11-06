{ pkgs, ... }:
{
  common_apps = with pkgs; [
    curl
    git
    gnupg
    gnutar
    gzip
    hstr
    unzip
    vim
    wget
    wget2
    fastfetch
    xdg-ninja
    tree
    lazyjournal

    # Secrets Management
    age
    agenix

    # Nix Utils
    nvd # Nix/NixOS package version diff tool
    nix-output-monitor # Pipe your nix-build output through the nix-output-monitor to get additional information while building.
    ### nix-build --log-format internal-json -v |& nom --json
    nix-tree # Interactively browse dependency graphs of Nix derivations.
    nh # Yet another Nix CLI helper.(search and clean)

  ];
}
