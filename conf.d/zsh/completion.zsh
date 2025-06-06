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
# force zsh not to show completion menu, which allows fzf-tab to capture the unambiguous prefix
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

# zstyle ':fzf-tab:*' fzf-preview 'pistol ${(Q)realpath}'
# switch group using `<` and `>`
zstyle ':fzf-tab:*' switch-group '<' '>'
# zstyle ':fzf-tab:*' accept-line enter # don't trigger enter after selected

# show systemd unit status
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview 'SYSTEMD_COLORS=1 systemctl status $word'

# show environment variable
zstyle ':fzf-tab:complete:(-command-|-parameter-|-brace-parameter-|export|unset|expand):*' \
  fzf-preview 'echo ${(P)word}'

# show alias
zstyle ':fzf-tab:complete:alias:*' fzf-preview 'alias $word'

# man or help
zstyle ':fzf-tab:complete:(\\|)run-help:*' fzf-preview 'run-help $word'
zstyle ':fzf-tab:complete:(\\|*/|)man:*' fzf-preview 'man $word'

# disable sort when completing `git checkout`
zstyle ':completion:*:git-checkout:*' sort false

# Better --SSH--/Rsync/SCP Autocomplete, use `sunlei/zsh-ssh` for ssh
zstyle ':completion:*:(scp|rsync):*' tag-order ' hosts:-ipaddr:ip\ address hosts:-host:host files'
zstyle ':completion:*:(scp|rsync):*:hosts-host' ignored-patterns '*(.|:)*' loopback ip6-loopback localhost ip6-localhost broadcasthost
zstyle ':completion:*:(scp|rsync):*:hosts-ipaddr' ignored-patterns '^(<->.<->.<->.<->|(|::)([[:xdigit:].]##:(#c,2))##(|%*))' '127.0.0.<->' '255.255.255.255' '::1' 'fe80::*'


# NOTE: Completions should be configured before compinit
autoload -U compinit; compinit
