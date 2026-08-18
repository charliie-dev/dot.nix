{ pkgs, ... }:
{
  packages = with pkgs; [
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
}
