{ config, lib, ... }:

{
  sessionVariables = {
    _ZO_DATA_DIR = "${config.xdg.dataHome}/zoxide";
    # zoxide uses ':' on Unix; ';' is only for Windows.
    _ZO_EXCLUDE_DIRS = "${config.xdg.cacheHome}:${config.xdg.dataHome}:${config.xdg.stateHome}";
    _ZO_FZF_OPTS =
      "--select-1 --height=40% --reverse --margin=3% --style=full "
      + "--border=rounded --border-label=' zoxide ' "
      + "--prompt='$ > ' --input-border --input-label=' Input ' "
      + "--list-border --highlight-line --gap --pointer='>' "
      + "--color 'border:#ca9ee6,label:#cba6f7' "
      + "--color 'input-border:#ea999c,input-label:#eba0ac' "
      + "--color 'list-border:#81c8be,list-label:#94e2d5' "
      + "--color 'info:#cba6f7,pointer:#f5e0dc,spinner:#f5e0dc,hl:#f38ba8' "
      + "--color 'marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8' "
      + "--color 'selected-bg:#45475a'";
  };

  # Antidote loads zsh-smartcache at order 550. Keep these manual integrations
  # cached instead of enabling each Home Manager module's direct zsh hook.
  initContent = lib.mkOrder 1000 ''
    smartcache eval zoxide init zsh
    smartcache eval starship init zsh
    # CTRL-T / CTRL-R / ALT-C widgets. fzf-tab (deferred) rebinds TAB later,
    # so fzf's own `**` completion trigger is not reachable.
    smartcache eval fzf --zsh
    # Open the widgets in a tmux floating pane (tmux 3.7+). `--popup` is
    # ignored outside tmux, so the same command works in a plain terminal.
    __fzfcmd() { echo "fzf --popup=80%,60% -- "; }
  '';
}
