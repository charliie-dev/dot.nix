#!/usr/bin/env bats

load "../lib/home-config"

setup_file() {
  require_home_config
  PROGRAM="$(build_home_package home-manager-docker-credentials)/bin/home-manager-docker-credentials"
  export PROGRAM
}

setup() {
  # Keep GNUPGHOME short enough for gpg-agent's Unix-domain socket path limit.
  ROOT="$(mktemp -d /tmp/sec02-docker.XXXXXX)"
  HOME_DIR="$ROOT/home"
  XDG_CONFIG="$HOME_DIR/.config"
  XDG_DATA="$HOME_DIR/.local/share"
  DOCKER_CONFIG="$XDG_CONFIG/docker/config.json"
  LOCK="$XDG_CONFIG/.docker-config.lock"
  GNUPG_HOME="$XDG_DATA/gnupg"
  BOOTSTRAP_MARKER="$GNUPG_HOME/.home-manager-docker-bootstrap-in-progress"
  PASSWORD_STORE="$XDG_DATA/password-store"
  FIXTURE_BIN="$ROOT/bin"
  mkdir -p "$XDG_CONFIG" "$XDG_DATA" "$FIXTURE_BIN"
  chmod 700 "$XDG_CONFIG" "$XDG_DATA" "$FIXTURE_BIN"
  cat > "$FIXTURE_BIN/pass" <<'SH'
#!/bin/sh
set -eu
[ "$1" = init ]
printf '%s\n' "$2" > "$PASSWORD_STORE_DIR/.gpg-id"
chmod 600 "$PASSWORD_STORE_DIR/.gpg-id"
SH
  chmod 700 "$FIXTURE_BIN/pass"
  export PATH="$FIXTURE_BIN:$PATH"
}

teardown() {
  rm -rf "$ROOT"
}

run_bootstrap() {
  run "$PROGRAM" \
    --home "$HOME_DIR" \
    --xdg-config "$XDG_CONFIG" \
    --xdg-data "$XDG_DATA" \
    --docker-config "$DOCKER_CONFIG" \
    --lock "$LOCK" \
    --gnupg-home "$GNUPG_HOME" \
    --password-store "$PASSWORD_STORE" \
    --store pass --linux "$@"
}

config_hash() {
  shasum -a 256 "$DOCKER_CONFIG" | awk '{print $1}'
}

assert_exact_key() {
  public="$(GNUPGHOME="$GNUPG_HOME" gpg --batch --with-colons --fixed-list-mode --with-fingerprint --list-keys)"
  secret="$(GNUPGHOME="$GNUPG_HOME" gpg --batch --with-colons --fixed-list-mode --with-fingerprint --list-secret-keys)"
  [ "$(printf '%s\n' "$public" | awk -F: '$1=="pub" && $4==22 && $7=="" && $12 ~ /c/i && $17=="ed25519" {n++} END{print n+0}')" -eq 1 ]
  [ "$(printf '%s\n' "$public" | awk -F: '$1=="sub" && $4==18 && $7=="" && $12 ~ /e/i && $17=="cv25519" {n++} END{print n+0}')" -eq 1 ]
  [ "$(printf '%s\n' "$secret" | awk -F: '$1=="ssb" && $4==18 && $12 ~ /e/i {n++} END{print n+0}')" -eq 1 ]
  [ "$(grep -cv '^[[:space:]]*\($\|#\)' "$PASSWORD_STORE/.gpg-id")" -eq 1 ]
}

@test "pristine Linux fixture generates exact key initializes pass then replaces config" {
  run_bootstrap
  if [ "$status" -ne 0 ]; then
    echo "$output" >&2
    return 1
  fi
  [ "$(stat -f '%Lp' "$GNUPG_HOME")" = 700 ]
  [ "$(stat -f '%Lp' "$PASSWORD_STORE")" = 700 ]
  [ "$(stat -f '%Lp' "$PASSWORD_STORE/.gpg-id")" = 600 ]
  [ ! -e "$BOOTSTRAP_MARKER" ]
  jq -e '.credsStore == "pass" and .credHelpers["asia-east1-docker.pkg.dev"] == "gcr"' \
    "$DOCKER_CONFIG" >/dev/null
  assert_exact_key
}

@test "existing valid key and store are idempotent" {
  run_bootstrap
  [ "$status" -eq 0 ]
  before="$(config_hash)"
  run_bootstrap
  [ "$status" -eq 0 ]
  [ "$(config_hash)" = "$before" ]
  [ ! -e "$BOOTSTRAP_MARKER" ]
  rm -rf "$PASSWORD_STORE"
  mkdir -m 700 "$PASSWORD_STORE"
  run_bootstrap
  [ "$status" -eq 0 ]
  [ ! -e "$BOOTSTRAP_MARKER" ]
  assert_exact_key
}

@test "Docker Hub token-like registry identifiers are accepted and idempotent" {
  run_bootstrap
  [ "$status" -eq 0 ]
  cat > "$DOCKER_CONFIG" <<'JSON'
{
  "auths": {
    "https://index.docker.io/v1/": {},
    "/access-token": {},
    "/refresh-token": {}
  },
  "credsStore": "pass"
}
JSON
  chmod 600 "$DOCKER_CONFIG"
  run_bootstrap
  [ "$status" -eq 0 ]
  jq -e '
    .credsStore == "pass"
    and .auths["https://index.docker.io/v1/"] == {}
    and .auths["/access-token"] == {}
    and .auths["/refresh-token"] == {}
  ' "$DOCKER_CONFIG" >/dev/null
  before="$(config_hash)"
  run_bootstrap
  [ "$status" -eq 0 ]
  [ "$(config_hash)" = "$before" ]
}

@test "credential fields beneath Docker Hub token-like registry identifiers remain rejected" {
  run_bootstrap
  [ "$status" -eq 0 ]
  cases=(
    '{"credsStore":"pass","auths":{"https://index.docker.io/v1/":{"auth":"SENTINEL_PRIVATE"}}}'
    '{"credsStore":"pass","auths":{"/access-token":{"identityToken":"SENTINEL_PRIVATE"}}}'
    '{"credsStore":"pass","auths":{"/refresh-token":{"nested":[{"RefreshTOKEN":"SENTINEL_PRIVATE"}]}}}'
  )
  for document in "${cases[@]}"; do
    printf '%s\n' "$document" > "$DOCKER_CONFIG"
    chmod 600 "$DOCKER_CONFIG"
    before="$(config_hash)"
    run_bootstrap
    [ "$status" -ne 0 ]
    [ "$(config_hash)" = "$before" ]
    [[ "$output" != *SENTINEL_PRIVATE* ]]
  done
}

@test "inline auth and token fields are rejected unconditionally without disclosure" {
  cases=(
    '{"auths":{"registry.invalid":{"auth":"SENTINEL_PRIVATE"}}}'
    '{"credsStore":"pass","auths":{"registry.invalid":{"identityToken":"SENTINEL_PRIVATE"}}}'
    '{"credHelpers":{"registry.invalid":"gcr"},"auths":{"registry.invalid":{"nested":{"RefreshTOKEN":"SENTINEL_PRIVATE"}}}}'
    '{"auths":{"registry.invalid":{"entries":[{"AUTH":"SENTINEL_PRIVATE"}]}}}'
  )
  for document in "${cases[@]}"; do
    mkdir -p "$(dirname "$DOCKER_CONFIG")"
    chmod 700 "$(dirname "$DOCKER_CONFIG")"
    printf '%s\n' "$document" > "$DOCKER_CONFIG"
    chmod 600 "$DOCKER_CONFIG"
    before="$(config_hash)"
    run_bootstrap
    [ "$status" -ne 0 ]
    [ "$(config_hash)" = "$before" ]
    [[ "$output" != *SENTINEL_PRIVATE* ]]
    rm -rf "$GNUPG_HOME" "$PASSWORD_STORE"
  done
}

@test "malformed auths and credential helper types fail before GPG mutation" {
  for document in \
    '{"auths":[]}' \
    '{"auths":{"registry.invalid":[]}}' \
    '{"credHelpers":[]}' \
    '{"credsStore":{}}'; do
    mkdir -p "$(dirname "$DOCKER_CONFIG")"
    chmod 700 "$(dirname "$DOCKER_CONFIG")"
    printf '%s\n' "$document" > "$DOCKER_CONFIG"
    chmod 600 "$DOCKER_CONFIG"
    before="$(config_hash)"
    run_bootstrap
    [ "$status" -ne 0 ]
    [ "$(config_hash)" = "$before" ]
    [ ! -e "$GNUPG_HOME" ]
    [ ! -e "$PASSWORD_STORE" ]
  done
}

@test "primary-only injected failure is monotonic and blocks the next run" {
  mkdir -p "$(dirname "$DOCKER_CONFIG")"
  chmod 700 "$(dirname "$DOCKER_CONFIG")"
  printf '{"fixture":"unchanged"}\n' > "$DOCKER_CONFIG"
  chmod 600 "$DOCKER_CONFIG"
  before="$(config_hash)"
  run_bootstrap --test-fail-at after-primary
  [ "$status" -ne 0 ]
  [ "$(config_hash)" = "$before" ]
  run_bootstrap
  [ "$status" -ne 0 ]
  [ "$(config_hash)" = "$before" ]
  [ -d "$GNUPG_HOME" ]
  [ "$(stat -f '%Lp' "$BOOTSTRAP_MARKER")" = 600 ]
  [ "$(stat -f '%l' "$BOOTSTRAP_MARKER")" = 1 ]
  [ "$(cat "$BOOTSTRAP_MARKER")" = bootstrap-in-progress ]
}

@test "subkey-complete interrupted generation marker blocks automatic recovery" {
  mkdir -p "$(dirname "$DOCKER_CONFIG")"
  chmod 700 "$(dirname "$DOCKER_CONFIG")"
  printf '{"fixture":"unchanged"}\n' > "$DOCKER_CONFIG"
  chmod 600 "$DOCKER_CONFIG"
  before="$(config_hash)"
  run_bootstrap --test-fail-at after-subkey
  [ "$status" -ne 0 ]
  [ "$(config_hash)" = "$before" ]
  [ "$(stat -f '%Lp' "$BOOTSTRAP_MARKER")" = 600 ]
  run_bootstrap
  [ "$status" -ne 0 ]
  [ "$(config_hash)" = "$before" ]
  [ -f "$BOOTSTRAP_MARKER" ]
  [[ "$output" == *"interrupted Docker GPG bootstrap"* ]]
}

@test "encrypted store entry without gpg-id and unsafe nested entries fail closed" {
  mkdir -p "$PASSWORD_STORE/nested" "$(dirname "$DOCKER_CONFIG")"
  chmod 700 "$PASSWORD_STORE" "$PASSWORD_STORE/nested" "$(dirname "$DOCKER_CONFIG")"
  printf fixture > "$PASSWORD_STORE/nested/item.gpg"
  chmod 600 "$PASSWORD_STORE/nested/item.gpg"
  printf '{}\n' > "$DOCKER_CONFIG"
  chmod 600 "$DOCKER_CONFIG"
  before="$(config_hash)"
  run_bootstrap
  [ "$status" -ne 0 ]
  [ "$(config_hash)" = "$before" ]
  rm "$PASSWORD_STORE/nested/item.gpg"
  ln -s /dev/null "$PASSWORD_STORE/nested/unsafe"
  run_bootstrap
  [ "$status" -ne 0 ]
  [ "$(config_hash)" = "$before" ]
}

@test "empty and multiple gpg-id recipients fail with config unchanged" {
  run_bootstrap
  [ "$status" -eq 0 ]
  printf '{"fixture":"unchanged"}\n' > "$DOCKER_CONFIG"
  chmod 600 "$DOCKER_CONFIG"
  before="$(config_hash)"
  : > "$PASSWORD_STORE/.gpg-id"
  chmod 600 "$PASSWORD_STORE/.gpg-id"
  run_bootstrap
  [ "$status" -ne 0 ]
  [ "$(config_hash)" = "$before" ]
  printf 'first\nsecond\n' > "$PASSWORD_STORE/.gpg-id"
  run_bootstrap
  [ "$status" -ne 0 ]
  [ "$(config_hash)" = "$before" ]
}

@test "unsafe parent leaf symlink mode hardlink and special file are rejected" {
  chmod 0777 "$XDG_DATA"
  run_bootstrap
  [ "$status" -ne 0 ]
  chmod 0700 "$XDG_DATA"
  rm -rf "$HOME_DIR/.local"
  mkdir -m 700 "$ROOT/data-target"
  ln -s "$ROOT/data-target" "$HOME_DIR/.local"
  run_bootstrap
  [ "$status" -ne 0 ]
  rm "$HOME_DIR/.local"
  mkdir -p "$XDG_DATA"
  chmod 700 "$HOME_DIR/.local" "$XDG_DATA"
  mkdir -m 700 "$GNUPG_HOME"
  ln -s "$GNUPG_HOME" "$PASSWORD_STORE"
  run_bootstrap
  [ "$status" -ne 0 ]
  rm "$PASSWORD_STORE"
  mkdir -m 700 "$PASSWORD_STORE"
  printf fixture > "$PASSWORD_STORE/item"
  chmod 600 "$PASSWORD_STORE/item"
  ln "$PASSWORD_STORE/item" "$PASSWORD_STORE/second"
  run_bootstrap
  [ "$status" -ne 0 ]
  rm "$PASSWORD_STORE/item" "$PASSWORD_STORE/second"
  mkfifo "$PASSWORD_STORE/fifo"
  run_bootstrap
  [ "$status" -ne 0 ]
  [ ! -e "$DOCKER_CONFIG" ]
}

@test "post-verification pass-init and source-race injections never replace config" {
  for point in after-verification after-pass-init before-replace; do
    rm -rf "$XDG_CONFIG" "$XDG_DATA"
    mkdir -p "$XDG_CONFIG" "$XDG_DATA" "$(dirname "$DOCKER_CONFIG")"
    chmod 700 "$XDG_CONFIG" "$XDG_DATA" "$(dirname "$DOCKER_CONFIG")"
    printf '{"fixture":"unchanged"}\n' > "$DOCKER_CONFIG"
    chmod 600 "$DOCKER_CONFIG"
    before="$(config_hash)"
    run_bootstrap --test-fail-at "$point"
    [ "$status" -ne 0 ]
    [ "$(config_hash)" = "$before" ]
  done
}

@test "public-only expired revoked disabled duplicate and malformed key states fail closed" {
  cat > "$FIXTURE_BIN/gpg" <<'SH'
#!/bin/sh
set -eu
primary_validity=u
primary_expiry=
sub_validity=u
sub_count=1
case "$GPG_CASE" in
  expired) primary_expiry=1 ;;
  revoked) primary_validity=r ;;
  disabled) sub_validity=d ;;
  missing-subkey) sub_count=0 ;;
  multiple-subkeys) sub_count=2 ;;
  public-only | duplicate) ;;
  *) exit 2 ;;
esac
emit_key() {
  kind=$1
  subkind=$2
  printf '%s:%s:255:22:PRIMARY:1:%s::u:::cC:::::ed25519:::0:\n' \
    "$kind" "$primary_validity" "$primary_expiry"
  printf 'fpr:::::::::AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:\n'
  printf 'uid:u::::1::HASH::Home Manager Docker Credentials <docker-credentials@localhost>::::::::::0:\n'
  i=1
  while [ "$i" -le "$sub_count" ]; do
    printf '%s:%s:255:18:SUB%s:1::::::e:::::cv25519::\n' "$subkind" "$sub_validity" "$i"
    printf 'fpr:::::::::BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB%s:\n' "$i"
    i=$((i + 1))
  done
}
case " $* " in
  *' --list-secret-keys '*)
    [ "$GPG_CASE" = public-only ] || emit_key sec ssb
    ;;
  *' --list-keys '*)
    emit_key pub sub
    [ "$GPG_CASE" = duplicate ] && emit_key pub sub
    ;;
esac
SH
  chmod 700 "$FIXTURE_BIN/gpg"
  mkdir -p "$(dirname "$DOCKER_CONFIG")"
  chmod 700 "$(dirname "$DOCKER_CONFIG")"
  printf '{"fixture":"unchanged"}\n' > "$DOCKER_CONFIG"
  chmod 600 "$DOCKER_CONFIG"
  before="$(config_hash)"
  for GPG_CASE in public-only expired revoked disabled duplicate missing-subkey multiple-subkeys; do
    export GPG_CASE
    run_bootstrap
    [ "$status" -ne 0 ]
    [ "$(config_hash)" = "$before" ]
  done
}

@test "unsafe bootstrap marker symlink and hardlink fail closed" {
  mkdir -m 700 "$GNUPG_HOME"
  mkdir -p "$(dirname "$DOCKER_CONFIG")"
  chmod 700 "$(dirname "$DOCKER_CONFIG")"
  printf '{"fixture":"unchanged"}\n' > "$DOCKER_CONFIG"
  chmod 600 "$DOCKER_CONFIG"
  before="$(config_hash)"
  ln -s /dev/null "$BOOTSTRAP_MARKER"
  run_bootstrap
  [ "$status" -ne 0 ]
  [ "$(config_hash)" = "$before" ]
  rm "$BOOTSTRAP_MARKER"
  printf 'bootstrap-in-progress\n' > "$BOOTSTRAP_MARKER"
  chmod 600 "$BOOTSTRAP_MARKER"
  ln "$BOOTSTRAP_MARKER" "$GNUPG_HOME/marker-hardlink"
  run_bootstrap
  [ "$status" -ne 0 ]
  [ "$(config_hash)" = "$before" ]
}

@test "bootstrap marker replacement is detected before unlink and remains blocking" {
  mkdir -p "$(dirname "$DOCKER_CONFIG")"
  chmod 700 "$(dirname "$DOCKER_CONFIG")"
  printf '{"fixture":"unchanged"}\n' > "$DOCKER_CONFIG"
  chmod 600 "$DOCKER_CONFIG"
  before="$(config_hash)"
  "$PROGRAM" \
    --home "$HOME_DIR" \
    --xdg-config "$XDG_CONFIG" \
    --xdg-data "$XDG_DATA" \
    --docker-config "$DOCKER_CONFIG" \
    --lock "$LOCK" \
    --gnupg-home "$GNUPG_HOME" \
    --password-store "$PASSWORD_STORE" \
    --store pass --linux --test-delay-before-marker-remove \
    > "$ROOT/marker-race.log" 2>&1 &
  pid=$!
  attempts=0
  until [ -f "$PASSWORD_STORE/.gpg-id" ] && [ -f "$BOOTSTRAP_MARKER" ]; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 200 ] || break
    sleep 0.01
  done
  [ -f "$PASSWORD_STORE/.gpg-id" ]
  [ -f "$BOOTSTRAP_MARKER" ]
  replacement="$GNUPG_HOME/.replacement-marker"
  printf 'bootstrap-in-progress\n' > "$replacement"
  chmod 600 "$replacement"
  mv -f "$replacement" "$BOOTSTRAP_MARKER"
  wait "$pid" && false
  [ "$(config_hash)" = "$before" ]
  [ -f "$BOOTSTRAP_MARKER" ]
  grep -q 'bootstrap marker changed before removal' "$ROOT/marker-race.log"
  run_bootstrap
  [ "$status" -ne 0 ]
  [ "$(config_hash)" = "$before" ]
}

@test "an external source race is detected without overwriting the raced config" {
  run_bootstrap
  [ "$status" -eq 0 ]
  printf '{"fixture":"source"}\n' > "$DOCKER_CONFIG"
  chmod 600 "$DOCKER_CONFIG"
  "$PROGRAM" \
    --home "$HOME_DIR" \
    --xdg-config "$XDG_CONFIG" \
    --xdg-data "$XDG_DATA" \
    --docker-config "$DOCKER_CONFIG" \
    --lock "$LOCK" \
    --gnupg-home "$GNUPG_HOME" \
    --password-store "$PASSWORD_STORE" \
    --store pass --linux --test-delay-before-replace \
    > "$ROOT/race.log" 2>&1 &
  pid=$!
  sleep 0.1
  printf '{"fixture":"external-race"}\n' > "$DOCKER_CONFIG"
  chmod 600 "$DOCKER_CONFIG"
  raced="$(config_hash)"
  wait "$pid" && false
  [ "$(config_hash)" = "$raced" ]
  grep -q 'Docker config changed before replacement' "$ROOT/race.log"
}

@test "dry-run creates no Docker GPG pass or lock artifact" {
  run_bootstrap --dry-run
  [ "$status" -eq 0 ]
  [ ! -e "$(dirname "$DOCKER_CONFIG")" ]
  [ ! -e "$LOCK" ]
  [ ! -e "$GNUPG_HOME" ]
  [ ! -e "$PASSWORD_STORE" ]
  [ ! -e "$DOCKER_CONFIG" ]
}
