{ pkgs, ... }:
{
  common = with pkgs; [
    curl # Command-line tool for transferring data with URLs
    unzip # Extraction utility for .zip archives
    ouch # Painless compression and decompression in the terminal
    xdg-ninja # Audits $HOME for files violating XDG Base Directory Spec
    tree # List directory contents in a tree-like format
    lazyjournal # TUI for journalctl, filesystem logs, and Docker container logs
    gum # Tool for glamorous shell scripts (prompts, spinners, styling)
    antidote # Zsh plugin manager

    # Secrets Management
    age # Modern, secure file encryption tool
    sops # Secrets management tool for editing encrypted YAML/JSON/ENV/INI files

    # Nix Utils
    nvd # Nix/NixOS package version diff tool
    nix-output-monitor # Pipe your nix-build output through the nix-output-monitor to get additional information while building.
    ### nix-build --log-format internal-json -v |& nom --json
    nix-tree # Interactively browse dependency graphs of Nix derivations.
    dix # A blazingly fast tool to diff Nix related things.

    # LSP
    clang-tools # clangd and clang-format
    nil # Nix language server
    nixd # Nix language server with advanced completion
    systemd-lsp # Systemd unit language server

    # Formatters
    mdsf # Markdown code-block formatter
    nixfmt # Official Nix formatter

    # Linters
    deadnix # Find unused Nix code
    selene # Lua linter
    statix # Find and fix Nix antipatterns
  ];

  roles = {
    "dev-core" = with pkgs; [
      # Good CLIs
      eva # Calculator REPL
      fzy # Better fuzzy finder
      git-ignore # Qucikly and easily fetch .gitignore templates from gitignore.io
      # ripsecrets # Prevent committing secret keys into your source code
      # xh # Friendly and fast tool for sending HTTP requests
      jless # JSON viewer designed for reading, exploring, and searching through JSON data
      witr # Why is this running?

      # Modern CLI replacements (see global CLAUDE.md preferred tools table)
      hyperfine # Command-line benchmarking tool (ad-hoc timing loops)
      dust # More intuitive du written in Rust
      duf # Better df with a nicer table output
      procs # Modern replacement for ps written in Rust
      choose # Human-friendly alternative to cut and awk field picking
      sd # Intuitive find & replace (sed alternative) for batch edits

      # yazi
      # ffmpeg # for video thumbnails
      poppler # for PDF preview
      resvg # for SVG preview
      imagemagick # for Font, HEIC, and JPEG XL preview
      hexyl # Command-line hex viewer
      chafa # Terminal graphics for images
      lnav # Log file navigator
      yq-go # jq but for YAML, JSON, XML, CSV, TOML
    ];

    "dev-extra" = with pkgs; [
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
    ];

    top =
      with pkgs;
      [
        iftop # Display bandwidth usage on a network interface
        dua # Tool to learn about the disk usage of directories

        # System info
        onefetch # Git repo summary
        cpufetch # CPU architecture info
      ]
      ++ lib.optionals stdenv.hostPlatform.isLinux [
        s-tui # Stress-Terminal UI monitoring tool
        iotop-c # Top-like UI for monitoring I/O usage (C port of iotop)
        wavemon # ncurses Wi-Fi signal and statistics monitor
      ]
      ++ lib.optional (lib.meta.availableOn stdenv.hostPlatform gpufetch) gpufetch
      ++ lib.optionals stdenv.hostPlatform.isDarwin [
        macpm # Perf monitoring CLI tool for Apple Silicon
      ];
  };

  capabilities.nvidiaGpu = with pkgs; [
    nvtopPackages.nvidia # GPU process monitor (htop-like) for NVIDIA
  ];
}
