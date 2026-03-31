# Set completion options.
setopt always_to_end        # Move cursor to the end of a completed word.
setopt auto_list            # Automatically list choices on ambiguous completion.
setopt auto_menu            # Show completion menu on a successive tab press.
setopt auto_param_slash     # If completed parameter is a directory, add a trailing slash.
setopt complete_in_word     # Complete from both ends of a word.
setopt path_dirs            # Perform path search even on command names with slashes.
setopt NO_flow_control      # Disable start/stop characters in shell editor.
setopt NO_menu_complete     # Do not autoselect the first completion entry.


# auto-convert case
zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}'
# error correction
zstyle ':completion:*' completer _complete _match _approximate
zstyle ':completion:*:match:*' original only
zstyle ':completion:*:approximate:*' max-errors 2 numeric

# fzf-tab configs

# set descriptions format to enable group support
# NOTE: don't use escape sequences (like '%F{red}%d%f') here, fzf-tab will ignore them
zstyle ':completion:*:descriptions' format '[%d]'
# set list-colors to enable filename colorizing
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
## force zsh not to show completion menu, which allows fzf-tab to capture the unambiguous prefix
zstyle ':completion:*' menu no
# To make fzf-tab follow FZF_DEFAULT_OPTS.
# NOTE: This may lead to unexpected behavior since some flags break this plugin. See Aloxaf/fzf-tab#455.
zstyle ':fzf-tab:*' use-fzf-default-opts no
zstyle ':fzf-tab:*' fzf-flags --height 60% --reverse --margin=3% --style=full \
    --border=rounded --border-label=' fzf-tab ' \
    --prompt='$ > ' --input-border --input-label=' Input ' \
    --list-border --highlight-line --gap --pointer='>' \
    --preview-border --preview-label=' Previewing ' \
    --color 'border:#ca9ee6,label:#cba6f7' \
    --color 'input-border:#ea999c,input-label:#eba0ac' \
    --color 'list-border:#81c8be,list-label:#94e2d5' \
    --color 'preview-border:#f2d5cf,preview-label:#f5e0dc' \
    --color 'info:#cba6f7,pointer:#f5e0dc,spinner:#f5e0dc,hl:#f38ba8' \
    --color 'marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8' \
    --color 'selected-bg:#45475a'

# # zstyle ':fzf-tab:*' fzf-preview 'pistol ${(Q)realpath}'
# switch group using `<` and `>`
zstyle ':fzf-tab:*' switch-group '<' '>'
# # zstyle ':fzf-tab:*' accept-line enter # don't trigger enter after selected

# show environment variable
zstyle ':fzf-tab:complete:(-command-|-parameter-|-brace-parameter-|export|unset|expand):*' \
    fzf-preview 'echo ${(P)word}'

# disable preview for alias (runs in subprocess, no access to parent shell aliases)
zstyle ':fzf-tab:complete:(alias|unalias):*' fzf-preview ''

# ssh host preview (match by Host or HostName)
zstyle ':fzf-tab:complete:(ssh|scp|rsync):*' fzf-preview \
  'awk -v w="${word% }" '"'"'/^Host /{if(m){print b;d=1;exit}b=$0;m=($2==w);next}{b=b"\n"$0;if($1=="HostName"&&$2==w)m=1}END{if(m&&!d)print b}'"'"' ~/.ssh/host_configuration 2>/dev/null | bat --color=always --style=plain --language=ssh_config'

# man page preview
zstyle ':fzf-tab:complete:(\\|)run-help:*' fzf-preview 'MANPAGER=cat MANWIDTH=$FZF_PREVIEW_COLUMNS man ${word% } 2>/dev/null'
zstyle ':fzf-tab:complete:(\\|*/|)man:*' fzf-preview 'MANPAGER=cat MANWIDTH=$FZF_PREVIEW_COLUMNS man ${word% } 2>/dev/null'

# universal preview via pistol
zstyle ':fzf-tab:complete:*:*' fzf-preview \
  'f=${realpath:-$PWD/${word% }}; [[ -e $f ]] && pistol $f 2>/dev/null'

# carapace config
zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
zstyle ':completion:*:git:*' group-order 'main commands' 'alias commands' 'external commands'

# disable sort when completing `git checkout`
zstyle ':completion:*:git-checkout:*' sort false

# SSH completion: disable zsh's _ssh, let carapace handle it (with overlay for Host-only completion)
compdef -d ssh scp rsync
