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
          # SchemaStore's patterns for the global config, so the rendered
          # ~/.config/mise/config.toml is validated when opened too.
          "**/mise/config.toml"
          "**/mise/config.*.toml"
          "**/mise/conf.d/*.toml"
        ];
      }
    ];
  };
}
