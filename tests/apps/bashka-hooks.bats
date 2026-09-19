#!/usr/bin/env bats

setup_file() {
  export REPO
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export BASHKA_TEST_ROOT
  BASHKA_TEST_ROOT=$(mktemp -d "${TMPDIR:?}/bashka-tests.XXXXXX")
  # The registration helper rejects symlinked parents, including Darwin /var.
  BASHKA_TEST_ROOT=$(cd "$BASHKA_TEST_ROOT" && pwd -P)
  export BASHKA_TEST_BUNDLE
  BASHKA_TEST_BUNDLE=$(nix build --no-link --print-out-paths --impure --file "$REPO/tests/fixtures/bashka/module.nix")
}

teardown_file() {
  [[ -n "$BASHKA_TEST_ROOT" && "$BASHKA_TEST_ROOT" == */bashka-tests.* ]] || return 1
  rm -rf -- "$BASHKA_TEST_ROOT"
}

setup() {
  bats_require_minimum_version 1.5.0
}

check() {
  "$BASHKA_TEST_BUNDLE/python/bin/python3" -IS "$REPO/tests/lib/bashka_hooks.py" "$1" -v
}

@test "Claude and Grok hook protocols never rewrite or elevate" {
  check Protocol
}

@test "visible network pipelines and prefixed shell sinks are denied" {
  check Pipelines
}

@test "substitutions, redirections, heredocs and static nested shells are denied" {
  check Nested
}

@test "ordinary commands and documented out-of-scope flows pass unchanged" {
  check NonMatches
}

@test "shared parser resource boundaries and cancellation are enforced" {
  check Resources
}

@test "slow input and parser fixtures return valid deny before host timeout" {
  check Deadlines
}

@test "fixed entry preserves double-dash arguments and isolates startup" {
  check Entry
}

@test "native Bashka allows harmless GREEN and NEUTRAL with exact positional arguments" {
  check NativeAllow
}

@test "native Bashka stops harmless RED, StrongGate, Critical and error fixtures" {
  check NativeDeny
}

@test "registration preserves unrelated values and hook ordering" {
  check Registration
}

@test "registration refuses unsafe files, conflicting hooks and concurrent changes" {
  check RegistrationSafety
}
