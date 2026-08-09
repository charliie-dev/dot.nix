{ lib, ... }:

{
  sessionVariables = {
    # batman must run in pager mode when invoked by man(1); otherwise it enters
    # its fzf-search branch and discards stdin.
    MANPAGER = "env BATMAN_IS_BEING_MANPAGER=yes batman";
    MANROFFOPT = "-c";
  };

  siteFunctions = {
    bathelp = ''
      sed 's/.\x08//g' | bat --plain --language=help --strip-ansi=always
    '';

    help = ''
      "$@" --help 2>&1 | bathelp
    '';

    open-default = ''
      if [[ "$OSTYPE" == darwin* ]] && (( $+commands[open] )); then
        command open "$@"
      elif (( $+commands[xdg-open] )); then
        command xdg-open "$@"
      elif (( $+commands[gio] )); then
        command gio open "$@"
      elif (( $+commands[open] )); then
        command open "$@"
      else
        print -u2 -- "open-default: no supported opener found"
        return 127
      fi
    '';

    clipcopy = ''
      if (( $+commands[pbcopy] )); then
        command pbcopy
      elif [[ -n "''${WAYLAND_DISPLAY:-}" ]] && (( $+commands[wl-copy] )); then
        command wl-copy
      elif (( $+commands[xclip] )); then
        command xclip -selection clipboard
      elif (( $+commands[xsel] )); then
        command xsel --clipboard --input
      else
        print -u2 -- "clipcopy: no supported clipboard command found"
        return 127
      fi
    '';

    zsh-list-on-chpwd = ''
      command ls -a
      return 0
    '';

    wdym = ''
      echo -n "$1 means: " && grep -i "^$1\`" <(
        curl -fsSL https://raw.githubusercontent.com/Ashpex/Slang-Word/master/slang.txt
      ) | awk -F'`' '{ print $2 }'
    '';

    mr = ''
      local name="$1"
      [[ -z "$name" ]] && {
        echo "usage: mr <task|shell-alias> [args...]"
        return 1
      }
      shift

      if mise tasks ls --no-header 2>/dev/null | awk '{print $1}' | grep -qx "$name"; then
        print -s "mise run $name $*"
        mise run "$name" "$@"
      elif mise shell-alias ls 2>/dev/null | awk '{print $1}' | grep -qx "$name"; then
        local cmd
        cmd=$(mise shell-alias ls 2>/dev/null | awk -v n="$name" '$1==n {$1=""; print substr($0,2)}')
        print -s "$name $*"
        eval "$cmd" "$@"
      else
        echo "mr: unknown task or shell-alias: $name" >&2
        return 1
      fi
    '';

    _mr = ''
      local -a tnames tdisp anames adisp
      local line name rest expl
      local sep=$'\t'

      for line in ''${(f)"$(mise tasks ls --no-header 2>/dev/null | awk '{
          match($0, /[[:space:]]+/)
          print substr($0,1,RSTART-1) "\t" substr($0,RSTART+RLENGTH)
      }')"}; do
        name=''${line%%$sep*}
        rest=''${line#*$sep}
        tnames+=("$name")
        tdisp+=("''${(r:28:)name} -- $rest")
      done

      for line in ''${(f)"$(mise shell-alias ls 2>/dev/null | awk '{
          match($0, /[[:space:]]+/)
          print substr($0,1,RSTART-1) "\t" substr($0,RSTART+RLENGTH)
      }')"}; do
        name=''${line%%$sep*}
        rest=''${line#*$sep}
        anames+=("$name")
        adisp+=("''${(r:28:)name} -- shell-alias→ $rest")
      done

      (( ''${#tnames} )) && _wanted tasks expl 'task' compadd -ld tdisp -a tnames
      (( ''${#anames} )) && _wanted aliases expl 'shell-alias' compadd -ld adisp -a anames
    '';

    _cct_current = ''
      if [[ -n "$CLAUDE_CODE_USE_VERTEX" ]]; then
        echo "vertex"
      elif [[ -n "$CLAUDE_CODE_USE_BEDROCK" ]]; then
        echo "bedrock"
      elif [[ -n "$CLAUDE_CODE_USE_FOUNDRY" ]]; then
        echo "azure"
      else
        echo "team"
      fi
    '';

    claude-code-toggle = ''
      local choice="$1"
      local current
      current=$(_cct_current)

      if [[ -z "$choice" ]]; then
        if command -v gum &>/dev/null; then
          choice=$(gum choose \
            --header "Claude backend (current: $current)" \
            "team" "vertex" "bedrock" "azure")
        else
          echo "current: $current" >&2
          echo "usage: cct <team|vertex|bedrock|azure>" >&2
          return 1
        fi
      fi

      [[ -z "$choice" ]] && return 0
      unset CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_FOUNDRY

      case "$choice" in
        team) echo "→ Team Plan mode" ;;
        vertex)
          export CLAUDE_CODE_USE_VERTEX=1
          echo "→ Vertex AI mode"
          ;;
        bedrock)
          export CLAUDE_CODE_USE_BEDROCK=1
          echo "→ Amazon Bedrock mode"
          ;;
        azure)
          export CLAUDE_CODE_USE_FOUNDRY=1
          echo "→ Microsoft Foundry mode"
          ;;
        *)
          echo "cct: unknown backend '$choice'" >&2
          echo "backends: team, vertex, bedrock, azure" >&2
          return 1
          ;;
      esac
    '';

    # Claude Code remote control needs feature-flag evaluation. Keep the global
    # DNT policy for other tools, but remove it only for this executable.
    claude = ''
      env -u DO_NOT_TRACK claude "$@"
    '';
  };

  initContent = lib.mkOrder 1050 ''
    autoload -Uz add-zsh-hook
    add-zsh-hook chpwd zsh-list-on-chpwd
    compdef _mr mr
  '';
}
