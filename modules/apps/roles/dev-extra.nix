{ pkgs, ... }:
{
  packages = with pkgs; [
    git-fame # CLI tool that helps u summarize and pretty-print collaborators based on contributions
    git-filter-repo # Quickly rewrite git repository history
    snyk # Scans and monitors projects for security vulnerabilities
    tokei # Count your code, quickly
    act # Run your GitHub Actions locally

    # VPS SDKs
    awscli2
    azure-cli
    google-cloud-sdk

    # Good TUIs
    nur.repos.charmbracelet.crush
    jqp # TUI plaground to experiment with jq

  ];
}
