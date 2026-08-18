{ pkgs, ... }:
{
  xdg.configFile."tombi/config.toml".source = (pkgs.formats.toml { }).generate "tombi-config.toml" {
    schemas = [
      {
        path = "https://mise.jdx.dev/schema/mise.json";
        include = [
          "mise.toml"
          ".mise.toml"
          ".mise/*.toml"
        ];
      }
    ];
  };
}
