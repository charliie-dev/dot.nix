# To see the key combo you want to use just do:
# cat > /dev/null
# And press it

bindkey "^K"      kill-whole-line                      # ctrl-k
bindkey "^A"      beginning-of-line                    # ctrl-a
bindkey "^E"      end-of-line                          # ctrl-e
bindkey "^D"      delete-char                          # ctrl-d
bindkey "^F"      forward-char                         # ctrl-f
bindkey "^B"      backward-char                        # ctrl-b
bindkey "^[[2~"   vi-insert                            # Key: Insert
bindkey "^[[3~"   delete-char                          # Key: Delete

# Plugin Keybinds
bindkey '^[[a' history-substring-search-up
bindkey '^[[b' history-substring-search-down
bindkey ',' autosuggest-accept
bindkey '^j' jq-complete

# Open the current command in your $EDITOR (e.g., neovim)
# Press Ctrl+X followed by Ctrl+E to trigger
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line

# Expands history expressions like !! or !$ when you press space
bindkey ' ' magic-space

# Init tirith BEFORE deferred plugins so their widget wrapping chains correctly
if (( $+commands[tirith] )); then
  eval "$(tirith init --shell zsh)"
  # Fix: tirith's zle -A creates _tirith_original_bracketed_paste as builtin type.
  # FSH wraps ALL widgets; for builtin type it calls zle .<name> which fails
  # because ._tirith_original_bracketed_paste isn't a real built-in.
  # Re-register as user widget so FSH uses the user-widget path instead.
  if (( ${+widgets[_tirith_original_bracketed_paste]} )); then
    _tirith_orig_bp() { zle .bracketed-paste "$@"; }
    zle -N _tirith_original_bracketed_paste _tirith_orig_bp
  fi
fi

# vim: set ft=zsh :
