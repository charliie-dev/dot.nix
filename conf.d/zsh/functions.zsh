zsh_recompile() {
	autoload -U zrecompile
	rm -rf ~/.config/zsh/*.zwc
	[[ -f ~/.zshenv.zwc ]] && rm -rf ~/.zshenv.zwc
	[[ -f ~/.zshenv ]] && zrecompile -p ~/.zshenv

	for f in "$XDG_CONFIG_HOME"/zsh; do
		[[ -f "$f".zwc ]] && rm -rf "$f".zwc
		zrecompile -p "$f"
	done

	[[ -f "$ZSH_COMPDUMP".zwc ]] && rm -rf "$ZSH_COMPDUMP".zwc
	[[ -f "$ZSH_COMPDUMP" ]] && zrecompile -p "$ZSH_COMPDUMP"

        source ~/.zshenv
}

extract() {
  echo Extracting "$1" ...
  if [ -f "$1" ] ; then
      case $1 in
          *.tar.bz2)   tar xjf "$1"  ;;
          *.tar.gz)    tar xzf "$1"  ;;
          *.bz2)       bunzip2 "$1"  ;;
          *.rar)       unrar x "$1"  ;;
          *.gz)        gunzip "$1"   ;;
          *.tar)       tar xf "$1"   ;;
          *.tbz2)      tar xjf "$1"  ;;
          *.tgz)       tar xzf "$1"  ;;
          *.zip)       unzip "$1"   ;;
          *.Z)         uncompress "$1"  ;;
          *.7z)        7z x "$1"  ;;
          *)        echo "'$1' cannot be extracted via extract()" ;;
      esac
  else
      echo "'$1' is not a valid file"
  fi
}

# restart cloudflared daemon to fix ssh login errors
cfd_reload() {
	if (( $OSTYPE[(I)darwin] )); then
		sudo launchctl stop com.cloudflare.cloudflared && sudo launchctl start com.cloudflare.cloudflared
		echo "Darwin/cloudflared reload!"
	elif (( $OSTYPE[(I)linux-gnu] )); then
		sudo systemctl restart cloudflared
		echo "Linux/cloudflared reload!"
	else
		echo 'Unknown OS!'
	fi
}

nix_reload() {
	if (( $OSTYPE[(I)darwin] )); then
		sudo launchctl remove org.nixos.nix-daemon && sudo launchctl load /Library/LaunchDaemons/org.nixos.nix-daemon.plist
		echo "Darwin/nix-daemon reload!"
	elif (( $OSTYPE[(I)linux-gnu] )); then
		sudo systemctl daemon-reload && sudo systemctl restart nix-daemon
		echo "Linux/nix-daemon reload!"
	else
		echo 'Unknown OS!'
	fi
}

# vim: set ft=zsh :
