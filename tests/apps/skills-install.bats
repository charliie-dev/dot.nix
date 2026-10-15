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

  # A copy of the task in a throwaway repository, so the tests pin the
  # discovery rule instead of whichever skills this repository ships today.
  FIXTURE_REPO="$BATS_TEST_TMPDIR/repo root"
  mkdir -p "$FIXTURE_REPO/.mise/tasks/skills" "$FIXTURE_REPO/skills"
  cp "$REPO/.mise/tasks/skills/install" "$FIXTURE_REPO/.mise/tasks/skills/install"
}

add_skill() {
  mkdir -p "$FIXTURE_REPO/skills/$1"
  printf -- '---\nname: %s\n---\n' "$1" > "$FIXTURE_REPO/skills/$1/SKILL.md"
}

run_install() {
  bash "$FIXTURE_REPO/.mise/tasks/skills/install"
}

expect_npx_args() {
  {
    printf '%s\n' --yes skills add "$FIXTURE_REPO/skills" --global --yes --skill
    printf '%s\n' "$@"
    printf '%s\n' --agent claude-code grok pi
  } > "$BATS_TEST_TMPDIR/expected-args"
  diff -u "$BATS_TEST_TMPDIR/expected-args" "$NPX_ARGS"
}

assert_pi_links() {
  local directory="$1"
  shift
  local skill
  for skill in "$@"; do
    [ -L "$directory/$skill" ]
    [ "$(readlink "$directory/$skill")" = "$HOME/.agents/skills/$skill" ]
    [ -f "$directory/$skill/SKILL.md" ]
  done
}

@test "skills install passes every skill directory from another working directory" {
  add_skill alpha
  add_skill beta
  cd "$BATS_TEST_TMPDIR" || return 1
  run -0 run_install

  expect_npx_args alpha beta
  assert_pi_links "$PI_CODING_AGENT_DIR/skills" alpha beta
}

@test "skills install skips entries without a SKILL.md" {
  add_skill alpha
  mkdir -p "$FIXTURE_REPO/skills/drafts"
  printf 'notes\n' > "$FIXTURE_REPO/skills/README.md"
  run -0 run_install

  expect_npx_args alpha
  [ ! -e "$PI_CODING_AGENT_DIR/skills/drafts" ]
  [ ! -e "$PI_CODING_AGENT_DIR/skills/README.md" ]
}

@test "skills install stops before npx when no skill is found" {
  mkdir -p "$FIXTURE_REPO/skills/drafts"
  run -1 run_install
  [[ "$output" == *"No skills found"* ]]
  [ ! -e "$NPX_ARGS" ]
}

@test "skills install repairs stale Pi links and can be repeated with the default directory" {
  add_skill alpha
  unset PI_CODING_AGENT_DIR
  mkdir -p "$HOME/.pi/agent/skills"
  ln -s "$BATS_TEST_TMPDIR/missing" "$HOME/.pi/agent/skills/alpha"

  run -0 run_install
  assert_pi_links "$HOME/.pi/agent/skills" alpha

  run -0 run_install
  assert_pi_links "$HOME/.pi/agent/skills" alpha
}

@test "skills install stops before linking Pi when npx fails" {
  add_skill alpha
  export NPX_STATUS=42
  run -42 run_install
  [ ! -e "$PI_CODING_AGENT_DIR/skills" ]
}

@test "skills install preserves an existing non-symlink in Pi's configured directory" {
  add_skill alpha
  directory="$PI_CODING_AGENT_DIR/skills/alpha"
  mkdir -p "$directory"
  printf 'local content\n' > "$directory/SKILL.md"

  run -1 run_install
  [ ! -L "$directory" ]
  [ "$(< "$directory/SKILL.md")" = "local content" ]
  [ ! -e "$directory/alpha" ]
}

@test "every repository skill directory is discoverable" {
  local manifest skill
  local found=0
  for manifest in "$REPO"/skills/*/SKILL.md; do
    [ -f "$manifest" ] || continue
    skill="${manifest%/SKILL.md}"
    skill="${skill##*/}"
    # skills add matches --skill against the frontmatter name.
    grep -qx "name: $skill" "$manifest"
    found=$((found + 1))
  done
  [ "$found" -gt 0 ]
}
