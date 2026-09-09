#!/usr/bin/env bats

load "../lib/home-config"

setup() {
  command -v herdr >/dev/null || skip "herdr is not installed"
  manifest="$BATS_TEST_TMPDIR/config/herdr/agent-detection/grok.toml"
  screen="$BATS_TEST_TMPDIR/screen.txt"
  mkdir -p "$(dirname "$manifest")"
  nix eval --raw --file "$REPO/modules/runtime/herdr.nix" --apply \
    'module: (module { config = {}; lib = {}; pkgs = {}; }).xdg.configFile."herdr/agent-detection/grok.toml".text' \
    > "$manifest"
}

assert_grok_state() {
  output=$(env XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config" XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" \
    herdr agent explain --file "$screen" --agent grok --json)
  jq '{state, matched_rule, visible_blocker, warning}' <<<"$output"
  jq -e --arg manifest "$manifest" --arg state "$1" \
    '.manifest_source == $manifest and .state == $state and .warning == null' \
    <<<"$output"
}

plan_approval_screen() {
  cat <<'SCREEN'
  ╭─ plan.md ──────────────────────────────────────────────────────────────╮
  │ Review the proposed changes before implementation.                     │
  │ a approve | s request changes | c comment | y copy plan | q quit plan   │
  ╰───────────────────────────────────────────────────────────────────────╯

  ◆ Waiting on plan approval

  ╭───────────────────────────────────────────────────────────────────────╮
  │ ❯ Build anything                                                      │
  ╰───────────────────── Test model · plan approval · always-approve ──────╯

  c:comment │ y:copy plan │ a:approve │ q:quit plan │ v:select │ Tab:prompt
SCREEN
}

@test "grok plan approval is blocked" {
  plan_approval_screen > "$screen"
  assert_grok_state blocked
  jq -e '.visible_blocker and .matched_rule.id == "plan_approval_blocked"' <<<"$output"
}

@test "grok plan approval outranks running background work" {
  {
    printf '  test-workspace  ◆ 1 │ 20K / 100K\n'
    plan_approval_screen
  } > "$screen"
  assert_grok_state blocked
}

@test "grok empty-plan approval controls are blocked without a status line" {
  printf '%s\n' 'No plan written yet' 'a:approve │ s:request changes │ q:quit plan' > "$screen"
  assert_grok_state blocked
}

@test "grok plan approval with pending comments is blocked" {
  printf '%s\n' 'a:approve w/ comments │ q:quit plan │ Tab:prompt' > "$screen"
  assert_grok_state blocked
}

@test "grok wrapped plan approval controls are blocked" {
  printf '%s\n' 'c:comment │ y:copy plan │ a:approve' 'q:quit plan │ v:select │ Tab:prompt' > "$screen"
  assert_grok_state blocked
}

@test "grok plan approval remains blocked while typing feedback" {
  cat > "$screen" <<'SCREEN'
  ╭───────────────────────────────────────────────────────────────────────╮
  │ ❯ Please revise the proposed change.                                  │
  ╰───────────────────── Test model · plan approval · always-approve ──────╯

  Enter:send │ Esc:back
SCREEN
  assert_grok_state blocked
}

@test "grok historical approval controls do not block an idle prompt" {
  {
    plan_approval_screen
    printf '%s\n' \
      'The plan was approved.' \
      '╭──────────────────────────────────╮' \
      '│ ❯                                │' \
      '╰───── Test model · always-approve ─╯' \
      'Shift+Tab:mode │ Ctrl+.:shortcuts'
  } > "$screen"
  assert_grok_state idle
}

@test "grok ordinary plan mode is not waiting for approval" {
  printf '%s\n' \
    '╰───── Test model · plan · always-approve ─╯' \
    'Shift+Tab:mode │ Ctrl+.:shortcuts' > "$screen"
  assert_grok_state idle
}

@test "grok mentioning approval in prose does not block a prompt" {
  printf '%s\n' \
    'The controls are a:approve and q:quit plan.' \
    'This explains plan approval, not an active approval dialog.' \
    '╰───── Test model · always-approve ─╯' \
    'Shift+Tab:mode │ Ctrl+.:shortcuts' > "$screen"
  assert_grok_state idle
}

@test "grok working after approval remains working" {
  printf '%s\n' \
    '⠋ Implementing the approved plan… 2s [stop]' \
    '╭──────────────────────────────────╮' \
    '│ ❯                                │' \
    '╰───── Test model · always-approve ─╯' \
    'Shift+Tab:mode │ Ctrl+c:cancel │ Ctrl+.:shortcuts' > "$screen"
  assert_grok_state working
}

@test "grok background task indicators remain working" {
  for indicator in '◆ 1 │ 20K / 100K' '◎ 1 command still running · send a message to interrupt'; do
    printf '%s\n' "$indicator" 'Shift+Tab:mode │ Ctrl+.:shortcuts' > "$screen"
    assert_grok_state working
  done
}

@test "grok permission and question dialogs remain blocked" {
  for controls in '1/3:select │ Ctrl+o:yolo │ Ctrl+c:cancel' 'Esc:unselect │ Tab:scrollback │ Shift+x:dismiss'; do
    printf '%s\n' "$controls" > "$screen"
    assert_grok_state blocked
  done
}
