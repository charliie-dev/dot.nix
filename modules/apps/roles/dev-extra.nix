{ pkgs, ... }:
{
  packages = with pkgs; [
    git-fame # CLI tool that helps u summarize and pretty-print collaborators based on contributions
    git-filter-repo # Quickly rewrite git repository history
    snyk # Scans and monitors projects for security vulnerabilities
    tokei # Count your code, quickly
  ];
}
