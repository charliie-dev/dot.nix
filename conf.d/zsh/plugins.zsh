# Init mise
# [[ $(uname -s) == MSYS_NT* ]] || eval "$(mise activate zsh)"

# Init vfox
# eval "$(vfox activate zsh)"

# Init zoxide
# eval "$(zoxide init zsh)"
# Use mroth/evalcache to speedup zsh loading time
export _ZO_DATA_DIR="$XDG_DATA_HOME"/zoxide
export _ZO_EXCLUDE_DIRS="$XDG_CACHE_HOME;$XDG_DATA_HOME;$XDG_STATE_HOME"

# Init Starship
# eval "$(starship init zsh)"

# Init micromamba
export MAMBA_ROOT_PREFIX="$HOME"/.local/state/nix/profile/bin
eval "$($MAMBA_ROOT_PREFIX/micromamba shell hook -s zsh)"

# Use mroth/evalcache to speedup zsh loading time
smartcache eval zoxide init zsh
smartcache eval starship init zsh
(( $OSTYPE[(I)msys] )) && smartcache eval mise activate zsh

# belak/zsh-utils xdg config
zstyle ':zsh-utils:*:*' use-xdg-basedirs 'yes'
# vim: set ft=zsh :
