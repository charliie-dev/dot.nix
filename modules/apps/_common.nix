{ pkgs, ... }:
{
  common_apps = with pkgs; [
    curl # Command-line tool for transferring data with URLs
    gnupg # Complete and free implementation of the OpenPGP standard
    vim # Vi-compatible text editor
    unzip # Extraction utility for .zip archives
    ouch # Painless compression and decompression in the terminal
    wget # Tool for retrieving files via HTTP/HTTPS/FTP
    wget2 # Successor of GNU Wget with parallel connections and HTTP/2
    xdg-ninja # Audits $HOME for files violating XDG Base Directory Spec
    tree # List directory contents in a tree-like format
    parallel # Shell tool for executing jobs in parallel
    lazyjournal # TUI for journalctl, filesystem logs, and Docker container logs
    gum # Tool for glamorous shell scripts (prompts, spinners, styling)

    # Secrets Management
    age # Modern, secure file encryption tool
    sops # Secrets management tool for editing encrypted YAML/JSON/ENV/INI files

    # Nix Utils
    nvd # Nix/NixOS package version diff tool
    nix-output-monitor # Pipe your nix-build output through the nix-output-monitor to get additional information while building.
    ### nix-build --log-format internal-json -v |& nom --json
    nix-tree # Interactively browse dependency graphs of Nix derivations.
    dix # A blazingly fast tool to diff Nix related things.
    nixd # Nix language server
    nil # Yet another language server for Nix

  ];
}
