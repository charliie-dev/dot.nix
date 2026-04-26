# set https://github.com/victor-gp/cmd-help-sublime-syntax
export MANPAGER='batman'
# alias bathelp="sed 's/.\x08//g' | bat --plain --language=help --strip-ansi=always --theme='Monokai Extended'"
alias bathelp="sed 's/.\x08//g' | bat --plain --language=help --strip-ansi=always"
help() {
    "$@" --help 2>&1 | bathelp
}
alias -g -- --help='--help 2>&1 | bathelp'
alias -g -- -h='-h 2>&1 | bathelp'

# List directory contents on cd
chpwd() {
    ls -a
}

wdym() {
    echo -n "$1 means: " && grep -i "^$1\`" <(curl -fsSL https://raw.githubusercontent.com/Ashpex/Slang-Word/master/slang.txt) | awk -F'`' '{ print $2 }'
}

# mise run with fzf-tab completion
mr() {
    local name="$1"
    [[ -z "$name" ]] && { echo "usage: mr <task|shell-alias> [args...]"; return 1; }
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
}

_mr() {
    local -a tnames tdisp anames adisp
    local line name rest expl
    local sep=$'\t'

    for line in ${(f)"$(mise tasks ls --no-header 2>/dev/null | awk '{
        match($0, /[[:space:]]+/)
        print substr($0,1,RSTART-1) "\t" substr($0,RSTART+RLENGTH)
    }')"}; do
        name=${line%%$sep*}
        rest=${line#*$sep}
        tnames+=("$name")
        tdisp+=("${(r:28:)name} -- $rest")
    done

    for line in ${(f)"$(mise shell-alias ls 2>/dev/null | awk '{
        match($0, /[[:space:]]+/)
        print substr($0,1,RSTART-1) "\t" substr($0,RSTART+RLENGTH)
    }')"}; do
        name=${line%%$sep*}
        rest=${line#*$sep}
        anames+=("$name")
        adisp+=("${(r:28:)name} -- shell-alias→ $rest")
    done

    (( ${#tnames} )) && _wanted tasks expl 'task' compadd -ld tdisp -a tnames
    (( ${#anames} )) && _wanted aliases expl 'shell-alias' compadd -ld adisp -a anames
}
compdef _mr mr

_cct_current() {
    if [[ -n "$CLAUDE_CODE_USE_VERTEX" ]]; then
        echo "vertex"
    elif [[ -n "$CLAUDE_CODE_USE_BEDROCK" ]]; then
        echo "bedrock"
    elif [[ -n "$CLAUDE_CODE_USE_FOUNDRY" ]]; then
        echo "azure"
    else
        echo "team"
    fi
}

claude-code-toggle() {
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
        team)    echo "→ Team Plan mode" ;;
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
}

# vim: set ft=zsh :
