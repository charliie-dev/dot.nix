{
  config,
  lib,
  ...
}:
let
  palettes = lib.importJSON "${config.catppuccin.sources.palette}/palette.json";
  colors = palettes.${config.catppuccin.flavor}.colors;
  hardwareColor = colors.peach.hex;
  softwareColor = colors.blue.hex;
  sectionBorder = format: {
    type = "custom";
    inherit format;
    outputColor = colors.mauve.hex;
  };
  infoModule = keyColor: type: {
    inherit type keyColor;
  };
in
{
  fastfetch = {
    enable = true;
    settings = {
      logo.padding.right = 2;
      display = {
        separator = "  ";
        brightColor = false;
        key.type = "icon";
        color = {
          keys = colors.mauve.hex;
          title = colors.blue.hex;
          output = colors.text.hex;
          separator = colors.overlay0.hex;
        };
      };
      modules = [
        "title"
        "break"
        (sectionBorder "┌────────────────── Hardware ──────────────────┐")
        (infoModule hardwareColor "host")
        (infoModule hardwareColor "cpu")
        (infoModule hardwareColor "gpu")
        (infoModule hardwareColor "memory")
        (infoModule hardwareColor "disk")
        (infoModule hardwareColor "display")
        (sectionBorder "└──────────────────────────────────────────────┘")
        "break"
        (sectionBorder "┌────────────────── Software ──────────────────┐")
        (infoModule softwareColor "os")
        (infoModule softwareColor "kernel")
        (infoModule softwareColor "packages")
        (infoModule softwareColor "shell")
        (infoModule softwareColor "terminal")
        (infoModule softwareColor "uptime")
        (sectionBorder "└──────────────────────────────────────────────┘")
        "break"
        {
          type = "colors";
          symbol = "circle";
          paddingLeft = 2;
        }
      ];
    };
  };
}
