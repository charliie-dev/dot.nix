{
  config,
  lib,
  pkgs,
  ...
}:
{
  jqp = {
    enable = true;
    package = pkgs.writeShellScriptBin "jqp" ''
      exec ${lib.getExe pkgs.jqp} -t ${lib.escapeShellArg "catppuccin-${config.catppuccin.flavor}"} "$@"
    '';
  };
}
