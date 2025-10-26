{ pkgs, ... }:
{
  bat = {
    enable = true;
    extraPackages = with pkgs.bat-extras; [
      # batdiff
      # batgrep
      batman
      # batpipe
      # batwatch
      # prettybat
    ];
    config = {
      # theme = "TwoDark"; # handover by catppuccin
      paging = "auto";
      pager = "less --RAW-CONTROL-CHARS --quit-if-one-screen --mouse";
      color = "always";
      decorations = "always";
      italic-text = "always";
      style = "changes,header-filename,header-filesize,grid,numbers,snip";
      map-syntax = [
        "*.ino:C++"
        ".ignore:Git Ignore"
        "*.jenkinsfile:Groovy"
        "*.props:Java Properties"
      ];
    };
  };
}
