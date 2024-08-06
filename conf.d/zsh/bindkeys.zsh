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
bindkey -v # Default to vi bindings

# Plugin Keybinds
bindkey '^[[a' history-substring-search-up
bindkey '^[[b' history-substring-search-down
bindkey ',' autosuggest-accept
bindkey '^j' jq-complete

# vim: set ft=zsh :
