{ config, ... }:
{
  zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";
    zprof.enable = false;
    enableCompletion = false;
    enableVteIntegration = true;
    # defaultKeymap = "vicmd";
    antidote = {
      enable = true;
      useFriendlyNames = true;
      plugins = [
        # oh-my-zsh plugins
        "getantidote/use-omz" # handle OMZ dependencies
        "ohmyzsh/ohmyzsh path:lib" # load OMZ's library
        "ohmyzsh/ohmyzsh path:plugins/colored-man-pages kind:defer" # load OMZ plugins
        # lazy-loading `kind:defer`
        "QuarticCat/zsh-smartcache" # better mroth/evalcache
        "zsh-users/zsh-completions kind:fpath"
        "belak/zsh-utils path:completion"
        "Aloxaf/fzf-tab kind:defer" # needs to load after `compinit`, but before wrap widgets, such as `zsh-autosuggestions` or `fast-syntax-highlighting`
        "zsh-users/zsh-autosuggestions kind:defer"
        "zdharma-continuum/fast-syntax-highlighting kind:defer" # add before zsh-history-substring-search to prevent breaking
        "zpm-zsh/colorize kind:defer" # Colorize the output of various programs
        "zpm-zsh/colors" # Enhanced colors for zsh
        "Freed-Wu/zsh-help" # colorize `XXX --help`
        "zsh-users/zsh-history-substring-search kind:defer"
        "MichaelAquilina/zsh-you-should-use kind:defer"
        # "MichaelAquilina/zsh-autoswitch-virtualenv kind:defer" # Auto-switch python venv, pipenv, poetry
        "sunlei/zsh-ssh kind:defer"
      ];
    };
    initContent = ''
      ${builtins.readFile ../../conf.d/zsh/completion.zsh}
      ${builtins.readFile ../../conf.d/zsh/setopt.zsh}
      ${builtins.readFile ../../conf.d/zsh/exports.zsh}
      ${builtins.readFile ../../conf.d/zsh/history.zsh}
      ${builtins.readFile ../../conf.d/zsh/functions.zsh}
      ${builtins.readFile ../../conf.d/zsh/bindkeys.zsh}
      ${builtins.readFile ../../conf.d/zsh/history.zsh}
      ${builtins.readFile ../../conf.d/zsh/plugins.zsh}
      ${builtins.readFile ../../conf.d/zsh/aliases.zsh}
      ${builtins.readFile ../../conf.d/zsh/macos.zsh}
      ${builtins.readFile ../../conf.d/zsh/hashdirs.zsh}
    '';
  };
}
