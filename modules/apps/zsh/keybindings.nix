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

    # Tirith must initialize before deferred plugins so widget wrappers form a
    # valid chain. Its zle -A snapshots are synthetic builtin widgets; F-Sy-H
    # tries to call a nonexistent dot-widget when wrapping those. Re-register
    # both snapshots as user widgets that delegate to the real builtins.
    if (( $+commands[tirith] )); then
      eval "$(tirith init --shell zsh)"
      if (( ''${+widgets[_tirith_original_accept_line]} )); then
        _tirith_orig_accept_line() { zle .accept-line "$@"; }
        zle -N _tirith_original_accept_line _tirith_orig_accept_line
      fi
      if (( ''${+widgets[_tirith_original_bracketed_paste]} )); then
        _tirith_orig_bp() { zle .bracketed-paste "$@"; }
        zle -N _tirith_original_bracketed_paste _tirith_orig_bp
      fi
    fi
  '';
}
