# ENVs
typeset -U PATH path # make sure $PATH is unique
export PATH
[ -d /opt/homebrew/bin/ ] && path=(/opt/homebrew/bin/ "$path[@]")

export XDG_CONFIG_HOME="$HOME"/.config # analogous to /etc
export XDG_CACHE_HOME="$HOME"/.cache # analogous to /var/cache
export XDG_DATA_HOME="$HOME"/.local/share # analogous to /usr/share
export XDG_STATE_HOME="$HOME"/.local/state # analogous to /var/lib
export XDG_RUNTIME_DIR=/tmp/users/$UID
export HISTFILE="$XDG_STATE_HOME"/zsh_history
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
export EDITOR='nvim'

add_path() {
    case ":${PATH}:" in
        *:"$*":*)
            ;;
    *)
        path=("$PATH" "$path[@]")
            ;;
    esac
}

autoload -Uz add_path
add_path "$HOME"/.local/bin
add_path "$CARGO_HOME"/bin
add_path "$GOPATH"/bin
add_path "$PNPM_HOME"

# set cuda path if nvidia gpus 
if command -v nvidia-smi &> /dev/null; then
    add_path "/usr/local/cuda/bin"
    export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
fi

# nixpkgs and nix home manager
if [ -e "$XDG_STATE_HOME"/nix/profile/etc/profile.d/nix.sh ]; then 
    . "$XDG_STATE_HOME"/nix/profile/etc/profile.d/nix.sh; 
    . "$XDG_STATE_HOME"/nix/profile/etc/profile.d/hm-session-vars.sh;
fi

# Only source this once
if [[ -z "$__HM_ZSH_SESS_VARS_SOURCED" ]]; then
  export __HM_ZSH_SESS_VARS_SOURCED=1
fi

