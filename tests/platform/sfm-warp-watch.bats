#!/usr/bin/env bats

setup_file() {
  export REPO
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SFM_TEST_ROOT
  SFM_TEST_ROOT=$(mktemp -d "${TMPDIR:?}/sfm-watch-tests.XXXXXX")
}

teardown_file() {
  case "$SFM_TEST_ROOT" in
    "${TMPDIR:?}/sfm-watch-tests."*) rm -rf -- "$SFM_TEST_ROOT" ;;
    *) return 1 ;;
  esac
}

check() {
  python3 -ISB "$REPO/tests/lib/sfm_warp_watch.py" "$1" -v
}

watchdog_policy_requires_reachable_underlay_and_cooldown() { # @test
  check Policy
}

watchdog_discovers_physical_ipv4_ipv6_without_profiles() { # @test
  check Discovery
}

watchdog_probes_use_bounded_verified_fixed_ip_https() { # @test
  check Probes
}

watchdog_pause_overlap_and_restart_failures_are_safe() { # @test
  check Runtime
}

watchdog_state_is_private_atomic_and_fails_closed() { # @test
  check Storage
}

watchdog_commands_and_reports_are_noncredential() { # @test
  check Safety
}

isolated_nix_module_builds_darwin_watchdog_without_activation() { # @test
  check NixModule
}
