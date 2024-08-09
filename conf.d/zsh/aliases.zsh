#!/bin/sh

# Core Aliases
alias sozsh='source ~/.zshenv && source ~/.config/zsh/.zshrc && zsh_recompile'
alias rm='rm -iv'
alias mkdir='mkdir -pv'
alias ps='ps auxf'
alias ping='ping -c 5'
alias less='less -R'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias bd='cd "$OLDPWD"' # cd to the previous directory
alias nv='nvim'
alias vim='vim -i NONE'
alias ips="ifconfig -a | grep -o 'inet6\? \(addr:\)\?\s\?\(\(\([0-9]\+\.\)\{3\}[0-9]\+\)\|[a-fA-F0-9:]\+\)' | awk '{ sub(/inet6? (addr:)? ?/, \"\"); print }'"
alias wget='wget2'

# Extanded Aliases
alias yarn='yarn --use-yarnrc "$XDG_CONFIG_HOME/yarn/config"'
alias py='python3'
alias ls='lsd -l'
alias lg='lazygit'
alias lzd='lazydocker'
alias conda='micromamba'
alias CA='conda activate'
alias CD='conda deactivate'
alias tb='tensorboard --logdir'
alias fzz='zoxide query | fzf'
alias fzp='cat /etc/services | fzf'
alias tree='tree -CAF --dirsfirst'
alias treed='tree -CAFd'
alias cargobin='cargo binstall --no-discover-github-token -y'
alias z='zi' # map z to zoxide interactive selection
alias yz='yazi'

# Nix Aliases
alias nixup='cd $HOME/.config/home-manager && nix flake update && home-manager switch --impure && cd "$OLDPWD"'
alias nixclean='nix-collect-garbage -d && nix-env --delete-generations old && nix-store --gc && nix-store --optimise'
alias nixsearch='nix search nixpkgs'

# Docker Aliases
alias docker_restart='docker compose down --remove-orphans && docker compose up -d'

# Network Aliases
alias openports='netstat -nape --inet' # show open ports
alias flsof4="lsof -Pni4 | awk '{printf \"%10s %6s %5s %4s %-20s\n\", \$1, \$2, \$3, \$8, \$9}' | fzf --header-lines=1 --cycle"

# Archive Aliases
alias mktar='tar -cvf'
alias mkbz2='tar -cvjf'
alias mkgz='tar -cvzf'
alias untar='tar -xvf'
alias unbz2='tar -xvjf'
alias ungz='tar -xvzf'

# vim: set ft=sh :
