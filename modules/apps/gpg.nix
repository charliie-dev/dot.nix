{ config, ... }:
{
  gpg = {
    enable = true;
    homedir = "${config.xdg.dataHome}/gnupg";
  };
}
