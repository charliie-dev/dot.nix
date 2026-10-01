#!/usr/bin/env bats

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

function test_account_maintenance_and_reserved_profile_safety() { # @test
  env PYTHONDONTWRITEBYTECODE=1 python3 "$REPO/tests/lib/sfm_warp_maintenance.py"
}

function test_gl_profile_generation_safety() { # @test
  env PYTHONDONTWRITEBYTECODE=1 python3 "$REPO/tests/lib/sfm_warp_profile.py"
}
