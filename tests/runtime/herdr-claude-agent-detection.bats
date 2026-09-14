#!/usr/bin/env bats

load "../lib/home-config"

setup() {
  command -v herdr >/dev/null || skip "herdr is not installed"
  manifest="$BATS_TEST_TMPDIR/config/herdr/agent-detection/claude.toml"
  screen="$BATS_TEST_TMPDIR/screen.txt"
  mkdir -p "$(dirname "$manifest")"
  nix eval --raw --file "$REPO/modules/runtime/herdr.nix" --apply \
    'module: (module { config = {}; lib = {}; pkgs = {}; }).xdg.configFile."herdr/agent-detection/claude.toml".text' \
    > "$manifest"
}

assert_claude_state() {
  output=$(env XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config" XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" \
    herdr agent explain --file "$screen" --agent claude --json)
  jq '{state, matched_rule, visible_blocker, visible_working, warning}' <<<"$output"
  jq -e --arg manifest "$manifest" --arg state "$1" \
    '.manifest_source == $manifest and .state == $state and .warning == null' \
    <<<"$output"
}

claude_prompt() {
  printf '%s\n' \
    '────────────────────────────────────────────────────────────────' \
    "❯ ${1:-}" \
    '────────────────────────────────────────────────────────────────'
}

claude_screen() {
  claude_prompt
  printf '%s\n' \
    ' [ Test model · ctx:43% · cache:85% · test-workspace ]' \
    ' [ dur:1180m42s · api:1023m3s · in:428k · out:0k ]' \
    "$1"
}

@test "claude background shell remains working at an idle prompt" {
  claude_screen '⏵⏵ auto mode on · 1 shell · ← for agents' > "$screen"
  assert_claude_state working
  jq -e '.visible_working and (.visible_idle | not) and .matched_rule.id == "background_shells_working"' <<<"$output"
}

@test "claude plural and multi-digit shell counts remain working" {
  for count in '2 shells' '12 shells' '100 shells'; do
    claude_screen "⏵⏵ auto mode on · $count · ← for agents" > "$screen"
    assert_claude_state working
  done
}

@test "claude background shells remain working across permission modes" {
  for footer in \
    '⏵⏵ bypass permissions on · 1 shell · ← for agents' \
    '⏸ plan mode on · 1 shell · ← for agents' \
    '1 shell · ← for agents'; do
    claude_screen "$footer" > "$screen"
    assert_claude_state working
  done
}

@test "claude shell footer without a prompt remains working" {
  printf '%s\n' '  ⏵⏵ auto mode on · 1 shell · ← for agents' > "$screen"
  assert_claude_state working
}

@test "claude wrapped shell footer remains working" {
  for footer in \
    $'⏵⏵ auto mode on\n  · 1 shell · ← for agents' \
    $'⏵⏵ auto mode\n  on · 1 shell · ← for agents' \
    $'⏵⏵ auto mode on ·\n  1 shell · ← for agents' \
    $'⏵⏵ auto mode on · 1\n  shell · ← for agents' \
    $'⏵⏵ auto mode on · 1 shell\n  · ← for agents'; do
    claude_screen "$footer" > "$screen"
    assert_claude_state working
  done
}

@test "claude missing or nonpositive shell counts remain idle" {
  for footer in \
    '⏵⏵ auto mode on · ← for agents' \
    '⏵⏵ auto mode on · 0 shells · ← for agents' \
    '⏵⏵ auto mode on · -1 shell · ← for agents'; do
    claude_screen "$footer" > "$screen"
    assert_claude_state idle
    jq -e '.visible_idle and (.visible_working | not)' <<<"$output"
  done
}

@test "claude historical shell footer does not keep a new prompt working" {
  {
    claude_screen '⏵⏵ auto mode on · 1 shell · ← for agents'
    printf '%s\n' 'The shell completed.'
    claude_screen '⏵⏵ auto mode on · ← for agents'
  } > "$screen"
  assert_claude_state idle
}

@test "claude shell text in a response or user prompt remains idle" {
  {
    printf '%s\n' '⏵⏵ auto mode on · 1 shell · ← for agents'
    claude_prompt $'Explain this footer:\n  1 shell · ← for agents'
    printf '%s\n' '⏵⏵ auto mode on · ← for agents'
  } > "$screen"
  assert_claude_state idle
}

@test "claude permission phrases in the input do not suppress active shells" {
  for prompt in \
    'Explain "waiting for permission".' \
    'Explain "Esc to cancel".' \
    $'Explain this text:\n  "waiting for permission".' \
    $'Explain this text:\n  Esc to cancel is a keyboard hint.'; do
    {
      claude_prompt "$prompt"
      printf '%s\n' '⏵⏵ auto mode on · 1 shell · ← for agents'
    } > "$screen"
    assert_claude_state working
  done
}

@test "claude completed-turn shell summary is not a live footer" {
  {
    printf '%s\n' '✻ Sautéed for 10s · 1 shell still running'
    claude_screen '⏵⏵ auto mode on · ← for agents'
  } > "$screen"
  assert_claude_state idle
}

@test "claude foreground turn with background shells still uses its working rule" {
  claude_screen '⏵⏵ auto mode on · 1 shell · esc to interrupt' > "$screen"
  assert_claude_state working
  jq -e '.matched_rule.id == "live_turn_working"' <<<"$output"
}

@test "claude Bash permissions outrank background shells" {
  for selected in 1 2; do
    {
      printf '%s\n' 'Bash command: pwd' 'Do you want to proceed?'
      if [ "$selected" -eq 1 ]; then
        printf '%s\n' '❯ 1. Yes' '  2. No'
      else
        printf '%s\n' '  1. Yes' '❯ 2. No'
      fi
      printf '%s\n' \
        'Esc to cancel · Tab to amend · ctrl+e to explain' \
        '⏵⏵ auto mode on · 1 shell · ← for agents'
    } > "$screen"
    assert_claude_state blocked
    jq -e '.visible_blocker and .matched_rule.id == "bash_permission_prompt"' <<<"$output"
  done
}

@test "claude generic permissions and confirmation forms outrank background shells" {
  for controls in \
    'Do you want to proceed? · Esc to cancel' \
    'Enter to select · ↑/↓ to navigate · Esc to cancel'; do
    printf '%s\n' \
      '────────────────────────────────────────────────────────────────' \
      '❯ 1. Yes' '  2. No' "$controls" \
      '⏵⏵ auto mode on · 1 shell · ← for agents' > "$screen"
    assert_claude_state blocked
    jq -e '.visible_blocker and (.visible_working | not)' <<<"$output"
  done
}

@test "claude waiting for permission outranks background shells" {
  printf '%s\n' \
    'Waiting for permission' \
    '⏵⏵ auto mode on · 1 shell · ← for agents' > "$screen"
  assert_claude_state blocked
}

@test "claude MCP input requests outrank background shells" {
  printf '%s\n' \
    'MCP server "test-server" requests your input' \
    '❯ Accept    Decline' \
    'Esc to cancel · ↑/↓ to navigate' \
    '⏵⏵ auto mode on · 1 shell · ← for agents' > "$screen"
  assert_claude_state blocked
  jq -e '.visible_blocker and .matched_rule.id == "mcp_elicitation_prompt"' <<<"$output"
}

@test "claude historical permission text does not suppress a live shell footer" {
  {
    printf '%s\n' 'Bash command: pwd' 'Do you want to proceed?' '❯ 1. Yes' 'Esc to cancel'
    claude_screen '⏵⏵ auto mode on · 1 shell · ← for agents'
  } > "$screen"
  assert_claude_state working
}

@test "claude transcript and model pickers keep their state with background shells" {
  for controls in \
    'Showing detailed transcript · ctrl+o to toggle' \
    'Select model · Enter to set as default · Esc to cancel'; do
    printf '%s\n' "$controls" '⏵⏵ auto mode on · 1 shell · ← for agents' > "$screen"
    assert_claude_state unknown
    jq -e '.skip_state_update and (.visible_working | not)' <<<"$output"
  done
}

@test "claude Bash permissions above a footer divider remain blocked" {
  printf '%s\n' \
    'Bash command: pwd' 'Do you want to proceed?' \
    '❯ 1. Yes' '  2. No' \
    'Esc to cancel · Tab to amend · ctrl+e to explain' \
    '────────────────────────────────────────────────────────────────' \
    '⏵⏵ auto mode on · 1 shell · ← for agents' > "$screen"
  assert_claude_state blocked
  jq -e '.visible_blocker and .matched_rule.id == "bash_permission_prompt"' <<<"$output"
}

@test "claude model picker above a footer divider keeps its state" {
  printf '%s\n' \
    'Select model · Enter to set as default · Esc to cancel' \
    '────────────────────────────────────────────────────────────────' \
    '⏵⏵ auto mode on · 1 shell · ← for agents' > "$screen"
  assert_claude_state unknown
  jq -e '.skip_state_update and .matched_rule.id == "model_picker_menu"' <<<"$output"
}

@test "claude existing foreground and background working signals are preserved" {
  for status in \
    '✳ Thinking… (4s · esc to interrupt)' \
    '✻ Waiting for 2 background agents to finish' \
    '✻ Sautéed for 10s · 2 MCP tasks still running'; do
    {
      printf '%s\n' "$status"
      claude_screen '⏵⏵ auto mode on · ← for agents'
    } > "$screen"
    assert_claude_state working
  done
}
