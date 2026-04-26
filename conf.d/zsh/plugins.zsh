# zoxide settings
export _ZO_DATA_DIR="$XDG_DATA_HOME"/zoxide
export _ZO_EXCLUDE_DIRS="$XDG_CACHE_HOME;$XDG_DATA_HOME;$XDG_STATE_HOME"
# use `zi` to open fzf search
export _ZO_FZF_OPTS="--select-1 --height=40% --reverse --margin=3% --style=full \
  --border=rounded --border-label=' zoxide ' \
  --prompt='$ > ' --input-border --input-label=' Input ' \
  --list-border --highlight-line --gap --pointer='>' \
  --color 'border:#ca9ee6,label:#cba6f7' \
  --color 'input-border:#ea999c,input-label:#eba0ac' \
  --color 'list-border:#81c8be,list-label:#94e2d5' \
  --color 'info:#cba6f7,pointer:#f5e0dc,spinner:#f5e0dc,hl:#f38ba8' \
  --color 'marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8' \
  --color 'selected-bg:#45475a'"

# Init micromamba
if (( $+commands[micromamba] )); then
    export MAMBA_ROOT_PREFIX="$HOME"/.local/bin
    eval "$($MAMBA_ROOT_PREFIX/micromamba shell hook -s zsh)"
    mkdir -p "$MAMBA_ROOT_PREFIX"/envs/completion
fi

# Use QuarticCat/zsh-smartcache to speedup zsh loading time
smartcache eval zoxide init zsh
smartcache eval starship init zsh
smartcache eval mise activate zsh

# Transient Prompt — simplify previous prompt after command execution
# _transient_prompt_accept_line() {
#     local _saved_prompt="$PROMPT"
#     local _saved_rprompt="$RPROMPT"
#     local _saved_prompt2="$PROMPT2"
#     PROMPT='%F{#a6adc8}%~%f %(?.%B%F{#a6e3a1}.%B%F{#f38ba8})❯%f%b '
#     RPROMPT=''
#     PROMPT2='   '
#     zle reset-prompt
#     PROMPT="$_saved_prompt"
#     RPROMPT="$_saved_rprompt"
#     PROMPT2="$_saved_prompt2"
#     zle .accept-line
# }
# zle -N accept-line _transient_prompt_accept_line

# vim: set ft=zsh :
