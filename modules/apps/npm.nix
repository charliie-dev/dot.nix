{ config, ... }:

{
  npm = {
    enable = true;
    # Node.js is managed by mise; only use Home Manager for npm's config.
    package = null;
    settings = {
      fund = false;
      color = true;
      prefix = "${config.xdg.dataHome}/npm";
      cache = "${config.xdg.cacheHome}/npm";
    };
  };
}
