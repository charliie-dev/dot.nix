# XDG ENVs
typeset -U path path cdpath fpath manpath
export XDG_CONFIG_HOME="$HOME"/.config     # analogous to /etc
export XDG_CACHE_HOME="$HOME"/.cache       # analogous to /var/cache
export XDG_DATA_HOME="$HOME"/.local/share  # analogous to /usr/share
export XDG_STATE_HOME="$HOME"/.local/state # analogous to /var/lib
export XDG_RUNTIME_DIR=/tmp/users/$UID
export ZDOTDIR="$XDG_CONFIG_HOME"/zsh
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
export DOTNET_CLI_HOME="$XDG_DATA_HOME"/dotnet
export CUDA_CACHE_PATH="$XDG_CACHE_HOME"/nv
export CONDARC="$XDG_CONFIG_HOME"/conda/condarc
export FZF_DEFAULT_OPTS="\
    --ansi --height 40% --layout=reverse --border --separator='╸' --header='E to edit' \
    --preview-label='┓ ⟪Preview⟫ ┏' --preview-window=border-bold --scrollbar '▌▐'\
    --color=border:#cba6f7,label:#cba6f7,separator:#a6e3a1 \
    --color=bg+:#313244,bg:,spinner:#f5e0dc,hl:#f38ba8 \
    --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
    --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"
export _ZO_FZF_OPTS="\
    --ansi --height 40% --layout=reverse --border --separator='╸' --scrollbar '▌▐' --select-1 \
    --color=border:#cba6f7,label:#cba6f7,separator:#a6e3a1 \
    --color=bg+:#313244,bg:,spinner:#f5e0dc,hl:#f38ba8 \
    --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
    --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8" # use `zi` to open fzf search

# Setup terminal, and turn on colors
[ "$TMUX" != "" ] && export TERM="tmux-256color"
export CLICOLOR=1
export LSCOLORS=Gxfxcxdxbxegedabagacad

# Enable color in grep
export GREP_OPTIONS='--color=auto'
export GREP_COLOR='3;33'

# TODO:
export LESS='--ignore-case --raw-control-chars'
# export PAGER='most'
export EDITOR='nvim'
# CTAGS Sorting in VIM/Emacs is better behaved with this in place
export LC_COLLATE=C

add_path() {
	# if arg_1 does not exist, exit function
	[ -e "$1" ] || return 1
	# if arg_1 is not a substring of $path, get full path and add it to $path
	# shellcheck disable=SC1087
	[[ ":$path:" == *" $1 "* ]] || path=("$(cd "$1" && pwd)" "$path[@]")
}

add_path "$HOME"/.local/bin
add_path "$CARGO_HOME"/bin
add_path "$GOPATH"/bin
add_path "$PNPM_HOME"
add_path "/opt/homebrew/bin"

# set cuda path if nvidia gpus exists
if command -v nvidia-smi &>/dev/null; then
	add_path "/usr/local/cuda/bin"
	[[ ":$LD_LIBRARY_PATH:" == *":/usr/local/cuda/lib64:"* ]] ||
		export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
fi

# set conda init
function set_conda_dir() {
	[ -d "/opt/anaconda3/" ] && export __conda_dir="/opt/anaconda3"
	[ -d "$HOME/anaconda3" ] && export __conda_dir="$HOME/anaconda3"
}
set_conda_dir
if command -v conda &>/dev/null; then
	eval "$("$__conda_dir"/bin/conda 'shell.zsh' 'hook' 2>/dev/null)"
else
	if [ -f "$__conda_dir/etc/profile.d/conda.sh" ]; then
		# shellcheck disable=SC1091
		. "$__conda_dir/etc/profile.d/conda.sh"
	else
		add_path "$__conda_dir/bin"
	fi
fi
unset __conda_dir

# nixpkgs and nix home manager
if [ -e "$XDG_STATE_HOME"/nix/profile/etc/profile.d/nix.sh ]; then
	. "$XDG_STATE_HOME"/nix/profile/etc/profile.d/nix.sh
	. "$XDG_STATE_HOME"/nix/profile/etc/profile.d/hm-session-vars.sh
fi

# Only source this once
if [[ -z "$__HM_ZSH_SESS_VARS_SOURCED" ]]; then
	export __HM_ZSH_SESS_VARS_SOURCED=1
fi

# vim: set ft=sh :
