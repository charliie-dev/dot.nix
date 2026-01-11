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
  ls
}

# use `ouch decompress` instead
# extract() {
#   echo Extracting "$1" ...
#   if [ -f "$1" ] ; then
#       case $1 in
#           *.tar.bz2)   tar xjf "$1"  ;;
#           *.tar.gz)    tar xzf "$1"  ;;
#           *.bz2)       bunzip2 "$1"  ;;
#           *.rar)       unrar x "$1"  ;;
#           *.gz)        gunzip "$1"   ;;
#           *.tar)       tar xf "$1"   ;;
#           *.tbz2)      tar xjf "$1"  ;;
#           *.tgz)       tar xzf "$1"  ;;
#           *.zip)       unzip "$1"   ;;
#           *.Z)         uncompress "$1"  ;;
#           *.7z)        7z x "$1"  ;;
#           *)        echo "'$1' cannot be extracted via extract()" ;;
#       esac
#   else
#       echo "'$1' is not a valid file"
#   fi
# }

wdym() {
  echo -n "$1 means: " && grep -i "^$1\`" <(curl -fsSL https://raw.githubusercontent.com/Ashpex/Slang-Word/master/slang.txt) | awk -F'`' '{ print $2 }'
}

# vim: set ft=zsh :
