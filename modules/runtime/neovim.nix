{
  config,
  pkgs,
  lib,
  ...
}:
let
  nvimdotsUrl = "charliie-dev/nvimdots.lua.git";
  nvimDir = "${config.xdg.configHome}/nvim";
in
{
  home.activation.nvimdotsClone = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "${nvimDir}" ]; then
      run ${pkgs.git}/bin/git clone "https://github.com/${nvimdotsUrl}" "${nvimDir}"
    fi
    run ${pkgs.git}/bin/git -C "${nvimDir}" remote set-url origin "git@github.com:${nvimdotsUrl}"
  '';
}
