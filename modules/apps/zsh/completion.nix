{ lib, ... }:

{
  setOptions = [
    "always_to_end"
    "auto_list"
    "auto_menu"
    "auto_param_slash"
    "complete_in_word"
    "path_dirs"
    "NO_flow_control"
    "NO_menu_complete"
  ];

  initContent = lib.mkMerge [
    (lib.mkOrder 560 ''
      # Completion matching and error correction.
      zstyle ':completion:*' matcher-list "" 'm:{a-zA-Z}={A-Za-z}'
      zstyle ':completion:*' completer _complete _match _approximate
      zstyle ':completion:*:match:*' original only
      zstyle ':completion:*:approximate:*' max-errors 2 numeric

      # fzf-tab configuration. It is deferred until after compinit, but these
      # styles are safe to declare before either component is loaded.
      zstyle ':completion:*:descriptions' format '[%d]'
      zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}
      zstyle ':completion:*' menu no
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
      zstyle ':fzf-tab:*' switch-group '<' '>'

      zstyle ':fzf-tab:complete:(-command-|-parameter-|-brace-parameter-|export|unset|expand):*' \
        fzf-preview 'echo ''${(P)word}'
      zstyle ':fzf-tab:complete:(alias|unalias):*' fzf-preview ""

      # Match an SSH config block by Host or HostName.
      zstyle ':fzf-tab:complete:(ssh|scp|rsync):*' fzf-preview \
        'awk -v w="''${word% }" '"'"'/^Host /{if(m){print b;d=1;exit}b=$0;m=($2==w);next}{b=b"\n"$0;if($1=="HostName"&&$2==w)m=1}END{if(m&&!d)print b}'"'"' ~/.ssh/host_configuration 2>/dev/null | bat --color=always --style=plain --language=ssh_config'

      zstyle ':fzf-tab:complete:(\\|)run-help:*' fzf-preview \
        'MANPAGER=cat MANWIDTH=$FZF_PREVIEW_COLUMNS man ''${word% } 2>/dev/null'
      zstyle ':fzf-tab:complete:(\\|*/|)man:*' fzf-preview \
        'MANPAGER=cat MANWIDTH=$FZF_PREVIEW_COLUMNS man ''${word% } 2>/dev/null'

      # Universal file preview via pistol.
      zstyle ':fzf-tab:complete:*:*' fzf-preview \
        'f=''${realpath:-$PWD/''${word% }}; [[ -e $f ]] && pistol $f 2>/dev/null'

      zstyle ':fzf-tab:complete:mr:*' fzf-preview \
        'if mise tasks ls --no-header 2>/dev/null | awk "{print \$1}" | grep -qx "$word"; then
          mise tasks info "$word"
        else
          mise shell-alias ls 2>/dev/null | awk -v n="$word" "\$1==n {for(i=2;i<=NF;i++) printf \"%s \",\$i; print \"\"}"
        fi'

      # Carapace grouping and git ordering.
      zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
      zstyle ':completion:*:git:*' group-order 'main commands' 'alias commands' 'external commands'
      zstyle ':completion:*:git-checkout:*' sort false
    '')

    (lib.mkOrder 1050 ''
      # Disable zsh's built-in SSH completers after compinit; carapace supplies
      # these commands, including the Host-only overlay.
      compdef -d ssh scp rsync
    '')
  ];
}
