# History options should be set in .zshrc and after oh-my-zsh sourcing.
# See https://github.com/nix-community/home-manager/issues/177.
HISTSIZE="10000"
SAVEHIST="10000"

HISTFILE="$XDG_CACHE_HOME"/zsh/zsh_history
mkdir -p "$(dirname "$HISTFILE")"
