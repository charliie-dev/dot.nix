{ pkgs, ... }:
{
  home.packages = [ pkgs.hunk ];

  xdg.configFile."hunk/config.toml".source = (pkgs.formats.toml { }).generate "hunk-config.toml" {
    theme = "catppuccin-mocha";
    mode = "auto";
    exclude_untracked = false;
    line_numbers = true;
    agent_notes = true;
  };
}
