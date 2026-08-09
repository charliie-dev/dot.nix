{
  config,
  lib,
  pkgs,
  ...
}:

lib.mkIf pkgs.stdenv.isDarwin {
  sessionVariables = {
    COLIMA_HOME = "${config.xdg.dataHome}/colima";
    CLICOLOR = "1";
    LSCOLORS = "Gxfxcxdxbxegedabagacad";
    GREP_COLOR = "3;33";
  };

  shellAliases = {
    ps = "ps aux";
    openports = "lsof -nP -iTCP -sTCP:LISTEN";
  };

  # Prefer GNU coreutils when installed, otherwise expose compatible names for
  # the BSD tools included with macOS. Homebrew already provides _mole through
  # its site-functions directory, so no runtime completion generation is needed.
  initContent = lib.mkOrder 1110 ''
    (( $+commands[md5sum] )) || alias md5sum='md5'
    (( $+commands[sha1sum] )) || alias sha1sum='shasum'
  '';
}
