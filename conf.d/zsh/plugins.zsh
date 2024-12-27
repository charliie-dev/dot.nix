# Init mise
[[ $(uname -s) == MSYS_NT* ]] || eval "$(mise activate zsh)"

# Init vfox
# eval "$(vfox activate zsh)"

# Init zoxide
# eval "$(zoxide init zsh)"
# Use mroth/evalcache to speedup zsh loading time
export _ZO_DATA_DIR="$XDG_DATA_HOME"/zoxide
export _ZO_EXCLUDE_DIRS="$XDG_CACHE_HOME;$XDG_DATA_HOME;$XDG_STATE_HOME"
export _ZO_FZF_OPTS="\
    --ansi --height 40% --layout=reverse --border --separator='╸' --scrollbar '▌▐' --select-1"
    # --color=border:#cba6f7,label:#cba6f7,separator:#a6e3a1 \
    # --color=bg+:#313244,bg:,spinner:#f5e0dc,hl:#f38ba8 \
    # --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
    # --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8" # use `zi` to open fzf search

# Init Starship
# eval "$(starship init zsh)"

# Init micromamba
if (( $+commands[micromamba] )); then
  export MAMBA_ROOT_PREFIX="$HOME"/.local/bin
  eval "$($MAMBA_ROOT_PREFIX/micromamba shell hook -s zsh)"
  mkdir -p "$MAMBA_ROOT_PREFIX"/envs/completion
fi

# Use mroth/evalcache to speedup zsh loading time
smartcache eval zoxide init zsh
smartcache eval starship init zsh
(( $OSTYPE[(I)msys] )) && smartcache eval mise activate zsh

# belak/zsh-utils xdg config
zstyle ':zsh-utils:*:*' use-xdg-basedirs 'yes'
# vim: set ft=zsh :
