#!/bin/zsh

# Flush the DNS cache. -> mattmc3/zephyr/tree/main/plugins/macos
# alias flushdns='dscacheutil -flushcache && sudo killall -HUP mDNSResponder'

# Remove .DS_Store files recursively in a directory. -> mattmc3/zephyr/tree/main/plugins/macos
# alias rmdsstore='find "${@:-.}" -type f -name .DS_Store -delete'

# macOS has no 'md5sum', so use 'md5' as a fallback
command -v md5sum > /dev/null || alias md5sum="md5"

# macOS has no 'sha1sum', so use 'shasum' as a fallback
command -v sha1sum > /dev/null || alias sha1sum="shasum"

# Empty the Trash on all mounted volumes and the main HDD
# Also, clear Apple’s System Logs to improve shell startup speed
clearlogs() {
  if [[ "$1" =~ ^[-]?[aA]{1}(ll)*$ ]]; then
      sudo rm -rvf ~/Library/Logs/*
      sudo rm -rvf /Library/Logs/*
      sudo rm -rvf /var/log/*
      sudo rm -rfv /private/var/log/asl/*.asl
  elif [[ "$1" =~ ^[-]?[uU]{1}(ser)*$ ]]; then
      rm -rvf ~/Library/Logs/*
  fi
}
