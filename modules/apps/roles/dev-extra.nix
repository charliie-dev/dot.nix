{ pkgs, ... }:
{
  packages = with pkgs; [
    git-fame # CLI tool that helps u summarize and pretty-print collaborators based on contributions
    git-filter-repo # Quickly rewrite git repository history
    snyk # Scans and monitors projects for security vulnerabilities
    tokei # Count your code, quickly

    # VPS SDKs
    awscli2
    azure-cli
    google-cloud-sdk

    # Good TUIs
    nur.repos.charmbracelet.crush
    jqp # TUI plaground to experiment with jq
    lazyssh # Terminal-based SSH manager

    # nix language server, formatter, linter
    nil # installed for crush
    # alejandra
    statix # lints and suggestions for the nix
    deadnix # Scan Nix files for dead code
    nixfmt-rfc-style # nixfmt was renamed to nixfmt-classic. The nixfmt attribute may be used for the new RFC 166-style formatter in the future, which is currently available as nixfmt-rfc-style
  ];
}
