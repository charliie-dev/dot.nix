{
  config,
  lib,
  pkgs,
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

  # Existing native installs can shadow the profile stub. Refresh generated
  # assets during switch without bootstrapping a missing binary.
  home.activation.topgradeNativeAssets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -z "''${DRY_RUN_CMD:-}" ] && [ -x "${config.home.homeDirectory}/.local/share/topgrade/bin/topgrade" ]; then
      HOME="${config.home.homeDirectory}" \
        XDG_DATA_HOME="${config.xdg.dataHome}" \
        XDG_STATE_HOME="${config.xdg.stateHome}" \
        ${lib.getExe pkgs.topgrade} --version > /dev/null || true
    fi
  '';
}
