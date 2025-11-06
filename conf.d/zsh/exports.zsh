# XDG ENVs
export XDG_CONFIG_HOME="$HOME"/.config     # analogous to /etc
export XDG_CACHE_HOME="$HOME"/.cache       # analogous to /var/cache
export XDG_DATA_HOME="$HOME"/.local/share  # analogous to /usr/share
export XDG_STATE_HOME="$HOME"/.local/state # analogous to /var/lib
export XDG_RUNTIME_DIR="/run/user/$UID"
(( $OSTYPE[(I)darwin] )) && export XDG_RUNTIME_DIR="$TMPDIR"
# export ZDOTDIR="$XDG_CONFIG_HOME"/zsh    # now set via nix/hm
export LESSHISTFILE="$XDG_DATA_HOME"/less_lesshst
export LESSKEY="$XDG_DATA_HOME"/less_lesskey
export WGETRC="$XDG_CONFIG_HOME"/wget/wgetrc
export CARGO_HOME="$XDG_DATA_HOME"/cargo
export RUSTUP_HOME="$XDG_DATA_HOME"/rustup
export GOPATH="$XDG_DATA_HOME"/go
export GOMODCACHE="$XDG_CACHE_HOME"/go/mod
export _JAVA_OPTIONS=-Djava.util.prefs.userRoot="$XDG_CONFIG_HOME"/java
export STARSHIP_CONFIG="$XDG_CONFIG_HOME"/starship/starship.toml
export STARSHIP_CACHE="$XDG_CACHE_HOME"/starship
export DVDCSS_CACHE="$XDG_CACHE_HOME"/dvdcss
export NODE_REPL_HISTORY=""
export NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME"/npm/npmrc
export PNPM_HOME="$XDG_DATA_HOME"/pnpm
export DISCORD_USER_DATA_DIR="$XDG_DATA_HOME"
export DOCKER_CONFIG="$XDG_CONFIG_HOME"/docker
export MACHINE_STORAGE_PATH="$XDG_DATA_HOME"/docker-machine
export FFMPEG_DATADIR="$XDG_CONFIG_HOME"/ffmpeg
export ANSIBLE_CONFIG="$XDG_CONFIG_HOME"/ansible/ansible.cfg
export GTK_RC_FILES="$XDG_CONFIG_HOME"/gtk-1.0/gtkrc
export GTK2_RC_FILES="$XDG_CONFIG_HOME"/gtk-2.0/gtkrc
export ZELLIJ_CONFIG_DIR="$XDG_CONFIG_HOME"/zellij
export GNUPGHOME="$XDG_DATA_HOME"/gnupg
# [ -d "$GNUPGHOME" ] || mkdir -p "$GNUPGHOME" # move to nix/home-manager to manage it
export DOTNET_CLI_HOME="$XDG_DATA_HOME"/dotnet
# [ -d "$DOTNET_CLI_HOME" ] || mkdir -p "$DOTNET_CLI_HOME" # move to nix/home-manager to manage it
export CUDA_CACHE_PATH="$XDG_CACHE_HOME"/nv
export CONDARC="$XDG_CONFIG_HOME"/conda/condarc
export IPYTHONDIR="$XDG_CONFIG_HOME"/ipython
export JUPYTER_CONFIG_DIR="$XDG_CONFIG_HOME"/jupyter
export PYTHONSTARTUP="$XDG_CONFIG_HOME"/python/pythonrc
export BUNDLE_USER_CONFIG="$XDG_CONFIG_HOME"/bundle
export BUNDLE_USER_CACHE="$XDG_CACHE_HOME"/bundle
export BUNDLE_USER_PLUGIN="$XDG_DATA_HOME"/bundle
export EDITOR=nvim

# VPS
export AWS_SHARED_CREDENTIALS_FILE="$XDG_CONFIG_HOME"/aws/credentials
export AWS_CONFIG_FILE="$XDG_CONFIG_HOME"/aws/config
export AWS_PROFILE="default"
export AZURE_CONFIG_DIR="$XDG_DATA_HOME"/azure

# zsh plugins options
export ANTIDOTE_HOME="$XDG_CACHE_HOME"/antidote
export ZSH_SMARTCACHE_DIR="$XDG_CACHE_HOME"/zsh/smartcache
export ZSH_AUTOSUGGEST_USE_ASYNC="true"
export ZSH_COMPDUMP="$XDG_CACHE_HOME"/zsh/compdump

# Setup terminal, and turn on colors
[ "$TMUX" != "" ] && export TERM="tmux-256color"
export CLICOLOR=1 # for BSD-based distros, like macOS
export LSCOLORS=Gxfxcxdxbxegedabagacad # for BSD-based distros, like macOS
# export LS_COLORS="$(vivid generate catppuccin-mocha)" # for GNU-based distros


# Enable color in grep
export GREP_OPTIONS='--color=auto'
export GREP_COLOR='3;33'

# TODO:
export LESS='--ignore-case --raw-control-chars'
# export PAGER='most'
# CTAGS Sorting in VIM/Emacs is better behaved with this in place
export LC_COLLATE=C

add_path() {
	# if arg_1 does not exist, exit function
	[ -e "$1" ] || return 1
	# if $1 is not a substring of $path, get full path and add it to $path
	(( $path[(I)$1] )) || path=("$1" "$path[@]")
}

add_path "$HOME"/.local/bin
add_path "$CARGO_HOME"/bin
add_path "$GOPATH"/bin
add_path "$PNPM_HOME"
(( $OSTYPE[(I)darwin] )) && add_path "/opt/homebrew/bin"

# set cuda path if nvidia gpus exists
if (( $+commands[nvidia-smi] )); then
	add_path "/usr/local/cuda/bin"

	(( $LD_LIBRARY_PATH[(I)/usr/local/cuda/lib64] )) ||
		export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
fi

# set DOCKER_HOST for lazydocker if podman exists
if (( $+commands[podman] )); then
	if (( $OSTYPE[(I)darwin] )); then
		export DOCKER_HOST=unix://$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')
	elif (( $OSTYPE[(I)linux-gnu] )); then
    # rootless mode
    # systemctl --user enable --now podman.socket
    export DOCKER_HOST=unix://"$XDG_RUNTIME_DIR"/podman/podman.sock
	else
		echo 'Unknown OS for lazypodman!'
	fi
  alias docker='podman'
fi

# vim: set ft=sh :
