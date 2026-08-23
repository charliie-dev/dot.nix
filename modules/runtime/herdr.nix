{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Bootstrap 後的官方 binary 位於 ~/.local/bin,但 activation script 的
  # PATH 沒有這個目錄。用絕對路徑維持 switch 後的 auto reload。
  xdg.configFile."herdr/config.toml".onChange = lib.mkForce ''
    ${config.home.homeDirectory}/.local/bin/herdr server reload-config || true
  '';

  # Existing native installs can shadow the profile stub. Refresh generated
  # assets during switch without bootstrapping a missing binary.
  home.activation.herdrNativeAssets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -z "''${DRY_RUN_CMD:-}" ] && [ -x "${config.home.homeDirectory}/.local/bin/herdr" ]; then
      HOME="${config.home.homeDirectory}" \
        XDG_DATA_HOME="${config.xdg.dataHome}" \
        XDG_STATE_HOME="${config.xdg.stateHome}" \
        ${lib.getExe pkgs.herdr} --version > /dev/null || true
    fi
  '';
}
