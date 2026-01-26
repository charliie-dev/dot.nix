{ pkgs, ... }:
{
  packages = with pkgs; [
    # Good CLIs
    eva # Calculator REPL
    fzy # Better fuzzy finder
    git-ignore # Qucikly and easily fetch .gitignore templates from gitignore.io
    jq # JSON parser
    # ripsecrets # Prevent committing secret keys into your source code
    # sd # Intuitive find & replace CLI (sed alternative)
    # xh # Friendly and fast tool for sending HTTP requests
    jless # JSON viewer designed for reading, exploring, and searching through JSON data
    witr # Why is this running?

    # yazi
    # ffmpeg # for video thumbnails
    poppler # for PDF preview
    resvg # for SVG preview
    imagemagick # for Font, HEIC, and JPEG XL preview
    hexyl # Command-line hex viewer
    glow # nur.repos.charmbracelet.glow # Render markdown on the CLI, with pizzazz
    yq-go # jq but for YAML, JSON, XML, CSV, TOML

  ];
}
