{
  lib,
  pkgs,
  ...
}:
let
  configFile = (pkgs.formats.yaml { }).generate "glow.yml" {
    style = "tokyo-night";
    mouse = true;
    pager = true;
    width = 80;
  };
  configHome = pkgs.runCommand "glow-config" { } ''
    mkdir -p "$out/glow"
    ln -s ${configFile} "$out/glow/glow.yml"
  '';
  wrappedGlow = pkgs.writeShellScriptBin "glow" ''
    export XDG_CONFIG_HOME=${lib.escapeShellArg configHome}
    exec ${lib.getExe pkgs.glow} "$@"
  '';
in
{
  home.packages = [ wrappedGlow ];
}
