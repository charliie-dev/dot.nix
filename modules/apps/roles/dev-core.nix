{ pkgs, ... }:
{
  packages = with pkgs; [
    # Good CLIs
    difftastic # Syntax-aware diff

    eva # Calculator REPL
    fzy # Better fuzzy finder
    jq # JSON parser
    delta # Syntax-highlighting pager for git
    git-lfs # Git extension for versioning large files
    git-ignore # Qucikly and easily fetch .gitignore templates from gitignore.io
    # ripsecrets # Prevent committing secret keys into your source code
    # sd # Intuitive find & replace CLI (sed alternative)
    tree-sitter # Parser generator tool and an incremental parsing library
    xh # Friendly and fast tool for sending HTTP requests

    # pistol
    hexyl # Command-line hex viewer
    nur.repos.charmbracelet.glow # Render markdown on the CLI, with pizzazz
    lnav # Logfile Navigator
    chafa # terminal image viewer
    poppler-utils # pdftotext
    yq-go # jq but for YAML, JSON, XML, CSV, TOML

    # nix language server, formatter, linter
    nil # installed for crush
    # alejandra
    statix # lints and suggestions for the nix
    deadnix # Scan Nix files for dead code
    nixfmt-rfc-style # nixfmt was renamed to nixfmt-classic. The nixfmt attribute may be used for the new RFC 166-style formatter in the future, which is currently available as nixfmt-rfc-style

  ];
}
