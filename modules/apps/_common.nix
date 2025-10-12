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

    # Secrets Management
    age
    agenix

    # https://wiki.nixos.org/wiki/Python#Using_micromamba
    # micromamba # conda replacement, don't install via nix, install directly
  ];
}
