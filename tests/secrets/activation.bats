#!/usr/bin/env bats

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

@test "Darwin disables upstream async agent and defines locked login agent" {
  file="$REPO/modules/platform/darwin.nix"
  grep -q 'sops-nix = {' "$file"
  grep -q 'enable = lib.mkForce false' "$file"
  grep -q 'sops-nix-sync = {' "$file"
  grep -q 'fcntl.LOCK_EX' "$file"
  ! grep -q 'stamp' "$file"
}

@test "Darwin lock wrapper supplies system PATH before exec" {
  file="$REPO/modules/platform/darwin.nix"
  path_line="$(grep -nF 'export PATH="/usr/bin:/bin:$PATH"' "$file" | cut -d: -f1)"
  exec_line="$(grep -nF 'exec python3 -' "$file" | cut -d: -f1)"
  [ -n "$path_line" ]
  [ -n "$exec_line" ]
  [ "$path_line" -lt "$exec_line" ]
}

@test "synchronous activation uses concrete platform predecessors and dry-run command" {
  file="$REPO/modules/secrets/sops.nix"
  grep -q 'setupLaunchAgents' "$file"
  grep -q 'reloadSystemd' "$file"
  grep -q '\$DRY_RUN_CMD.*sops-nix-sync-locked' "$file"
  grep -q 'systemctlPath.*restart --user sops-nix' "$file"
  grep -q '\$DRY_RUN_CMD.*sops-nix-sync.config.Program' "$file"
}

@test "authorized key consumer is ordered after synchronous SOPS" {
  grep -q 'home.activation.authorizedKeys = lib.hm.dag.entryAfter \[ "sops-nix-sync" \]' \
    "$REPO/modules/secrets/sops.nix"
}

@test "new hosts default disabled and intended direct hosts are explicit" {
  grep -q 'enableSecrets = hostCfg.enableSecrets or false' "$REPO/flake.nix"
  [ "$(grep -c 'enableSecrets = true' "$REPO/hosts.nix")" -eq 5 ]
  [ "$(grep -c 'enableSecrets = false' "$REPO/hosts.nix")" -eq 3 ]
}

@test "activation mutations are dry-run guarded" {
  grep -q '\$DRY_RUN_CMD rm' "$REPO/modules/secrets/doppler.nix"
  grep -q -- '--dry-run' "$REPO/modules/secrets/sops.nix"
}
