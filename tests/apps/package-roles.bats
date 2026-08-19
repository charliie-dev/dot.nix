#!/usr/bin/env bats

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

@test "unknown app roles report the valid choices" {
  run nix eval --impure --expr "
    let
      flake = builtins.getFlake \"path:$REPO\";
      configuration = flake.lib.mkHomeConfiguration \"role-test\" {
        system = builtins.currentSystem;
        roles = [ \"missing\" ];
        homeDirectory = \"$BATS_TEST_TMPDIR/home\";
      };
    in
    builtins.length configuration.config.home.packages
  "

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown app role 'missing'"* ]]
  [[ "$output" == *"dev-core, dev-extra, nvidia-gpu, top"* ]]
}
