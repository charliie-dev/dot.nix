{
  config,
  lib,
  src,
  ...
}:
{
  home.activation.topgradeCopy = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Intentionally copy only once: each host owns its mutable overrides.
    if [ -z "''${DRY_RUN_CMD:-}" ] && [ ! -f ${config.xdg.configHome}/topgrade.d/disable.toml ]; then
      mkdir -p ${config.xdg.configHome}/topgrade.d
      cp "${src}/conf.d/topgrade/disable.toml" ${config.xdg.configHome}/topgrade.d/disable.toml
    fi
  '';
}
