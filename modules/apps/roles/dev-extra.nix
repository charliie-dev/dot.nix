{ pkgs, ... }:
{
  packages = with pkgs; [
    git-fame # CLI tool that helps u summarize and pretty-print collaborators based on contributions
    git-filter-repo # Quickly rewrite git repository history
    tokei # Count your code, quickly
    act # Run your GitHub Actions locally
    kompose # A conversion tool for Docker Compose to container orchestrators such as Kubernetes (or OpenShift).

    # Good TUIs
    jqp # TUI plaground to experiment with jq

  ];
}
