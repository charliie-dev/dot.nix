{ pkgs, ... }:
{
  packages = with pkgs; [
    git-fame # CLI tool that helps u summarize and pretty-print collaborators based on contributions
    git-filter-repo # Quickly rewrite git repository history
    tokei # Count your code, quickly
    scc # Code counter with complexity estimates (tokei alternative, cross-checks it)
    act # Run your GitHub Actions locally
    kompose # A conversion tool for Docker Compose to container orchestrators such as Kubernetes (or OpenShift).

    # Data wrangling (CSV/TSV); SQL-on-files and terminal plots stay ad-hoc:
    # nix shell nixpkgs#duckdb -c duckdb / nix shell nixpkgs#youplot -c uplot
    qsv # CSVs sliced, diced & analyzed
    miller # Like awk/sed/cut/join/sort for CSV, TSV, JSON

    # Good TUIs
    jqp # TUI plaground to experiment with jq

  ];
}
