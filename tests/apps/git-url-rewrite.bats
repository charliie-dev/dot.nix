#!/usr/bin/env bats

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
HOST='charles@24041-LABNB01'

build_git_config() {
  nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"git+file://$REPO\"; in f.homeConfigurations.\"$HOST\".config.xdg.configFile.\"git/config\".source"
}

resolve_url() {
  local config="$1"
  local url="$2"
  env -i \
    PATH="$PATH" \
    HOME="$BATS_TEST_TMPDIR/home" \
    GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR/empty" \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL="$config" \
    git -C "$BATS_TEST_TMPDIR/empty" ls-remote --get-url "$url"
}

@test "private Go modules use only the nics-dp SSH rewrite" {
  mkdir -p "$BATS_TEST_TMPDIR/home" "$BATS_TEST_TMPDIR/empty"
  config="$(cd "$REPO" && build_git_config)"

  run git config --file "$config" --get \
    'url.ssh://git@github.com/nics-dp/.insteadof'
  [ "$status" -eq 0 ]
  [ "$output" = 'https://github.com/nics-dp/' ]

  run resolve_url "$config" 'https://github.com/nics-dp/example'
  [ "$status" -eq 0 ]
  [ "$output" = 'ssh://git@github.com/nics-dp/example' ]

  run resolve_url "$config" 'https://github.com/example/public'
  [ "$status" -eq 0 ]
  [ "$output" = 'https://github.com/example/public' ]

  run resolve_url "$config" 'https://github.com/nics-tw/example'
  [ "$status" -eq 0 ]
  [ "$output" = 'https://github.com/nics-tw/example' ]

  run resolve_url "$config" 'https://github.com/nics-dp-sibling/example'
  [ "$status" -eq 0 ]
  [ "$output" = 'https://github.com/nics-dp-sibling/example' ]

  run git config --file "$config" --get-regexp '^url\..*\.insteadof$'
  [ "$status" -eq 0 ]
  [ "$output" = 'url.ssh://git@github.com/nics-dp/.insteadof https://github.com/nics-dp/' ]
}

@test "failed private SSH proof reports only a sanitized boolean" {
  mkdir -p "$BATS_TEST_TMPDIR/home" "$BATS_TEST_TMPDIR/empty"
  fake_ssh="$BATS_TEST_TMPDIR/fake-ssh"
  cat >"$fake_ssh" <<'SH'
#!/bin/sh
exit 42
SH
  chmod 0700 "$fake_ssh"

  check_private() {
    if env -i \
      PATH="$PATH" \
      HOME="$BATS_TEST_TMPDIR/home" \
      GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR/empty" \
      GIT_CONFIG_NOSYSTEM=1 \
      GIT_CONFIG_GLOBAL=/dev/null \
      GIT_SSH="$fake_ssh" \
      git -C "$BATS_TEST_TMPDIR/empty" \
        ls-remote 'ssh://git@private.invalid/private/repository' HEAD \
        >/dev/null 2>&1
    then
      printf 'private_go_module=yes\n'
    else
      printf 'private_go_module=no\n'
    fi
  }

  run check_private
  [ "$status" -eq 0 ]
  [ "$output" = 'private_go_module=no' ]
  [[ "$output" != *private/repository* ]]
}
