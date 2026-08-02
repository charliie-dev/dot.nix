{ pkgs, ... }:
{
  packages = with pkgs; [
    git-fame # CLI tool that helps u summarize and pretty-print collaborators based on contributions
    git-filter-repo # Quickly rewrite git repository history
    tokei # Count your code, quickly
    scc # Code counter with complexity estimates (tokei alternative, cross-checks it)
    act # Run your GitHub Actions locally
    kompose # A conversion tool for Docker Compose to container orchestrators such as Kubernetes (or OpenShift).

    # Cloudflare。互動式 CLI,任何目錄都可能用到,所以取 latest 放這裡。
    # opentofu 與 cf-terraforming 刻意不放 —— 它們跟 tofu state 格式綁在
    # 一起,鍵死在 home-lab 的 cloudflare/.mise/tasks/cf/* 的 #MISE tools
    # header,免得 flake.lock 一更新就連帶升級 state。
    flarectl # Cloudflare zone/DNS/firewall CLI
    wrangler # Cloudflare Workers/Pages/R2/KV/D1 CLI

    # Data wrangling (CSV/TSV); SQL-on-files and terminal plots stay ad-hoc:
    # nix shell nixpkgs#duckdb -c duckdb / nix shell nixpkgs#youplot -c uplot
    qsv # CSVs sliced, diced & analyzed
    miller # Like awk/sed/cut/join/sort for CSV, TSV, JSON

    # Good TUIs
    jqp # TUI plaground to experiment with jq

  ];
}
