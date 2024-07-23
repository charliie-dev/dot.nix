# Antidote Setup
export ANTIDOTE_HOME="$XDG_CACHE_HOME"/antidote
zstyle ':antidote:bundle' use-friendly-names 'yes'
antidote_dir="$XDG_STATE_HOME"/nix/profile/share/antidote
source ${antidote_dir}/antidote.zsh
# Set the root name of the plugins files (.txt and .zsh) antidote will use.
zsh_plugins=${ZDOTDIR:-~}/zsh_plugins
# Ensure the .zsh_plugins.txt file exists so you can add plugins.
[[ -f ${zsh_plugins}.txt ]] || touch ${zsh_plugins}.txt
# Lazy-load antidote from its functions directory.
fpath=("$antidote_dir"functions $fpath)
autoload -Uz antidote
# Generate a new static file whenever .zsh_plugins.txt is updated.
if [[ ! ${zsh_plugins}.zsh -nt ${zsh_plugins}.txt ]]; then
  antidote bundle <${zsh_plugins}.txt >|${zsh_plugins}.zsh
fi
# Source your static plugins file.
source ${zsh_plugins}.zsh
unset antidote_dir

# Plugin Keybinds
bindkey '^[[a' history-substring-search-up
bindkey '^[[b' history-substring-search-down
bindkey ',' autosuggest-accept

# Init mise
[[ $(uname -s) == MSYS_NT* ]] || eval "$(mise activate zsh)"

# Init vfox
# eval "$(vfox activate zsh)"

# Init zoxide
eval "$(zoxide init zsh)"
export _ZO_DATA_DIR="$XDG_DATA_HOME"/zoxide
export _ZO_EXCLUDE_DIRS="$XDG_CACHE_HOME;$XDG_DATA_HOME;$XDG_STATE_HOME"

# Init Starship
eval "$(starship init zsh)"

# vim: set ft=zsh :
