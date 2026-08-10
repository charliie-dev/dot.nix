#!/usr/bin/env bats
# shellcheck disable=SC2016 # literal shell fragments are the assertions

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

@test "Darwin gates the disabled upstream agent and locked login agent on either secret group" {
  file="$REPO/modules/platform/darwin.nix"
  grep -q 'sopsEnabled = enableSecrets || enableSshSecrets' "$file"
  grep -q 'lib.optionalAttrs sopsEnabled' "$file"
  grep -q 'sops-nix = {' "$file"
  grep -q 'enable = lib.mkForce false' "$file"
  grep -q 'sops-nix-sync = {' "$file"
  grep -q 'fcntl.LOCK_EX' "$file"
  run grep -q 'stamp' "$file"
  [ "$status" -eq 1 ]
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

@test "security-sensitive activation ordering is synchronous SOPS then authorized keys then Docker" {
  grep -q 'home.activation.authorizedKeys = lib.hm.dag.entryAfter \[ "sops-nix-sync" \]' \
    "$REPO/modules/secrets/sops.nix"
  grep -q 'activation.dockerCredentials = lib.hm.dag.entryAfter \[ "authorizedKeys" \]' \
    "$REPO/modules/runtime/docker.nix"
}

@test "application and SSH secret defaults and explicit shared-host policy are wired" {
  grep -q 'enableSecrets = hostCfg.enableSecrets or false' "$REPO/flake.nix"
  grep -q 'enableSshSecrets = hostCfg.enableSshSecrets or enableSecrets' "$REPO/flake.nix"
  grep -q '^[[:space:]]*enableSshSecrets$' "$REPO/flake.nix"
  [ "$(grep -c 'enableSecrets = true' "$REPO/hosts.nix")" -eq 4 ]
  [ "$(grep -c 'enableSecrets = false' "$REPO/hosts.nix")" -eq 7 ]
  [ "$(grep -c 'enableSshSecrets = true' "$REPO/hosts.nix")" -eq 1 ]
}

@test "activation mutations are dry-run guarded" {
  grep -q '\$DRY_RUN_CMD rm' "$REPO/modules/secrets/doppler.nix"
  grep -q -- '--dry-run' "$REPO/modules/secrets/sops.nix"
}
