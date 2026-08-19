{
  config,
  lib,
  ...
}:
let
  pluginCacheDir = "${config.xdg.cacheHome}/terraform/plugin-cache";
in
{
  home.activation.terraformPluginCache = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${pluginCacheDir}"
  '';

  xdg.configFile."terraform/terraformrc".text = ''
    plugin_cache_dir   = "${pluginCacheDir}"
    disable_checkpoint = true
  '';
}
