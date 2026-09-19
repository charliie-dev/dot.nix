{ lib, ... }:

{
  initContent = lib.mkOrder 1300 ''
    bindkey '^K' kill-whole-line
    bindkey '^A' beginning-of-line
    bindkey '^E' end-of-line
    bindkey '^D' delete-char
    bindkey '^F' forward-char
    bindkey '^B' backward-char
    bindkey '^[[2~' vi-insert
    bindkey '^[[3~' delete-char

    # Use terminfo instead of terminal-specific lowercase escape sequences.
    zmodload -F zsh/terminfo +p:terminfo 2>/dev/null
    [[ -n "''${terminfo[kcuu1]-}" ]] && \
      bindkey -- "''${terminfo[kcuu1]}" history-substring-search-up
    [[ -n "''${terminfo[kcud1]-}" ]] && \
      bindkey -- "''${terminfo[kcud1]}" history-substring-search-down
    bindkey '^ ' autosuggest-accept

    autoload -Uz edit-command-line
    zle -N edit-command-line
    bindkey '^X^E' edit-command-line
    bindkey ' ' magic-space

    # Restore the shell cursor after TUIs, including shells inside multiplexers.
    autoload -Uz add-zle-hook-widget
    _hm_zle_cursor_shape() {
      case $KEYMAP in
        vicmd|visual) printf '\e[2 q' ;;
        *) printf '\e[5 q' ;;
      esac
    }
    add-zle-hook-widget line-init _hm_zle_cursor_shape
    add-zle-hook-widget keymap-select _hm_zle_cursor_shape
  '';
}
