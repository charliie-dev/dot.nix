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
    tree-sitter # Parser generator tool and an incremental parsing library
    # xh # Friendly and fast tool for sending HTTP requests

    # yazi
    # ffmpeg # for video thumbnails
    poppler # for PDF preview
    resvg # for SVG preview
    perl540Packages.ImageMagick # for Font, HEIC, and JPEG XL preview, >= 7.1.1
    hexyl # Command-line hex viewer
    nur.repos.charmbracelet.glow # Render markdown on the CLI, with pizzazz
    yq-go # jq but for YAML, JSON, XML, CSV, TOML

    # nix language server, formatter, linter
    # alejandra # The Uncompromising Nix Code Formatter
    deadnix # Scan Nix files for dead code
    nil # installed for crush
    nixfmt-rfc-style # nixfmt was renamed to nixfmt-classic. The nixfmt attribute may be used for the new RFC 166-style formatter in the future, which is currently available as nixfmt-rfc-style
    statix # lints and suggestions for the nix

  ];
}
