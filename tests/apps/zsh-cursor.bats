#!/usr/bin/env bats

load "../lib/home-config"

setup() {
  command -v zsh >/dev/null || skip "zsh is not installed"
  nix eval --impure --raw --expr \
    "(import $REPO/modules/apps/zsh/keybindings.nix { lib.mkOrder = order: value: value; }).initContent" \
    > "$BATS_TEST_TMPDIR/.zshrc"
  printf '\nbindkey -v\nPROMPT="CURSOR_READY> "\n' >> "$BATS_TEST_TMPDIR/.zshrc"
}

@test "zsh restores a bar after terminal programs and tracks vi keymap changes" {
  zsh -f -s -- "$BATS_TEST_TMPDIR" <<'ZSH'
zmodload zsh/zpty
zpty -b cursor env TERM=xterm-256color ZDOTDIR="$1" zsh -d -i
trap 'zpty -d cursor' EXIT

await_output() {
  local pattern="$1" chunk received=""
  local deadline=$(( SECONDS + 5 ))
  while (( SECONDS < deadline )); do
    while zpty -r cursor chunk; do
      received+="$chunk"
      [[ "$received" == ${~pattern} ]] && return 0
    done
    sleep 0.02
  done
  print -r -- "timed out waiting for ${(qqq)pattern}; received ${(qqq)received}"
  return 1
}

await_output '*CURSOR_READY> *' || exit 1
# Model the steady block emitted by Yazi when the terminal cannot report its cursor.
zpty -w cursor "printf '\\033[2 q'"
await_output $'*\e\\[2 q*CURSOR_READY> *\e\\[5 q*' || exit 1

zpty -w -n cursor $'\e'
await_output $'*\e\\[2 q*' || exit 1
zpty -w -n cursor 'i'
await_output $'*\e\\[5 q*' || exit 1
ZSH
}
