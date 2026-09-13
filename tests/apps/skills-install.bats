#!/usr/bin/env bats

load "../lib/home-config"
bats_require_minimum_version 1.5.0

setup() {
  export HOME="$BATS_TEST_TMPDIR/home directory"
  export PI_CODING_AGENT_DIR="$BATS_TEST_TMPDIR/pi config"
  export NPX_ARGS="$BATS_TEST_TMPDIR/npx-args"
  export NPX_STATUS=0
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/npx" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$NPX_ARGS"
if [[ "$NPX_STATUS" != 0 ]]; then
    exit "$NPX_STATUS"
fi
mkdir -p "$HOME/.agents/skills"
cp -R "$4/." "$HOME/.agents/skills/"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/npx"
}

assert_pi_links() {
  local directory="$1"
  local skill
  for skill in compose-lint container-security dockerfile-builder; do
    [ -L "$directory/$skill" ]
    [ "$(readlink "$directory/$skill")" = "$HOME/.agents/skills/$skill" ]
    [ -f "$directory/$skill/SKILL.md" ]
  done
}

@test "skills install uses the repository source from another working directory" {
  cd "$BATS_TEST_TMPDIR" || return 1
  run -0 bash "$REPO/.mise/tasks/skills/install"

  printf '%s\n' --yes skills add "$REPO/skills" --global --yes \
    --skill compose-lint container-security dockerfile-builder \
    --agent claude-code grok pi > "$BATS_TEST_TMPDIR/expected-args"
  diff -u "$BATS_TEST_TMPDIR/expected-args" "$NPX_ARGS"
  assert_pi_links "$PI_CODING_AGENT_DIR/skills"
}

@test "skills install repairs stale Pi links and can be repeated with the default directory" {
  unset PI_CODING_AGENT_DIR
  mkdir -p "$HOME/.pi/agent/skills"
  ln -s "$BATS_TEST_TMPDIR/missing" "$HOME/.pi/agent/skills/compose-lint"

  run -0 bash "$REPO/.mise/tasks/skills/install"
  assert_pi_links "$HOME/.pi/agent/skills"

  run -0 bash "$REPO/.mise/tasks/skills/install"
  assert_pi_links "$HOME/.pi/agent/skills"
}

@test "skills install stops before linking Pi when npx fails" {
  export NPX_STATUS=42
  run -42 bash "$REPO/.mise/tasks/skills/install"
  [ ! -e "$PI_CODING_AGENT_DIR/skills" ]
}

@test "skills install preserves an existing non-symlink in Pi's configured directory" {
  directory="$PI_CODING_AGENT_DIR/skills/compose-lint"
  mkdir -p "$directory"
  printf 'local content\n' > "$directory/SKILL.md"

  run -1 bash "$REPO/.mise/tasks/skills/install"
  [ ! -L "$directory" ]
  [ "$(< "$directory/SKILL.md")" = "local content" ]
  [ ! -e "$directory/compose-lint" ]
}
