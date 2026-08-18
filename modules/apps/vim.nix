{
  config,
  lib,
  pkgs,
  ...
}:
{
  vim = {
    enable = true;
    packageConfigurable = pkgs.vim;
    plugins = lib.mkForce [ ];
    extraConfig = ''
      set viminfofile=${config.xdg.stateHome}/viminfo
    '';
  };
}
