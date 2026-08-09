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
  # Generate a separate file for the Lua cpath/path. The Neovim configuration
  # imports this from init.lua.
  xdg.configFile."nvim/lua/hm-generated.lua".text = config.programs.neovim.initLua;

  home.activation.nvimdotsClone = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "${nvimDir}" ]; then
      run ${pkgs.git}/bin/git clone "https://github.com/${nvimdotsUrl}" "${nvimDir}"
    fi
    run ${pkgs.git}/bin/git -C "${nvimDir}" remote set-url origin "git@github.com:${nvimdotsUrl}"
  '';
}
