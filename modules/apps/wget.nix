{
  lib,
  pkgs,
  ...
}:
let
  wrappedWget2 = pkgs.writeShellScriptBin "wget2" ''
    exec ${lib.getExe pkgs.wget2} --no-hsts "$@"
  '';
in
{
  home.packages = [ wrappedWget2 ];
}
