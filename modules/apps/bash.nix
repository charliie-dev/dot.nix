{ config, ... }:
{
  bash = {
    enable = true;
    package = null;
    historyFile = "${config.xdg.stateHome}/bash/history";
  };
}
