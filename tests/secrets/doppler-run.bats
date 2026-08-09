#!/usr/bin/env bats

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
MODULE="$REPO/modules/secrets/doppler.nix"

build_home_package() {
  local name="$1"
  nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"git+file://$REPO\"; ps = f.homeConfigurations.\"charles@24041-LABNB01\".config.home.packages; in builtins.head (builtins.filter (p: (p.name or \"\") == \"$name\") ps)"
}

@test "fixed profiles pin Doppler source and repeated selective retrieval" {
  grep -Fq '"--project", "dot-nix", "--config", "dev_personal"' "$MODULE"
  grep -Fq 'argv.extend(("--only-secrets", name))' "$MODULE"
  ! grep -q -- '--no-exit-on-missing-only-secrets' "$MODULE"
}

@test "bootstrap reads environment compatibly and sanitizes config directory" {
  ! grep -q -- '--no-read-env' "$MODULE"
  grep -Fq 'SANITIZE = SENSITIVE | {"DOPPLER_CONFIG_DIR"}' "$MODULE"
  grep -Fq 'boundary = required | {"DOPPLER_TOKEN"} | BOOTSTRAP_METADATA' "$MODULE"
  grep -Fq '"DOPPLER_PROJECT",' "$MODULE"
  grep -Fq '"DOPPLER_CONFIG",' "$MODULE"
  grep -Fq '"DOPPLER_ENVIRONMENT",' "$MODULE"
}

@test "internal boundary requires automatic metadata and removes all bootstrap names from target" {
  runner="$(build_home_package doppler-run)"
  run env -i HOME="$HOME" PATH=/usr/bin:/bin \
    DOPPLER_TOKEN=SYNTHETIC_BOOTSTRAP_TOKEN \
    DOPPLER_PROJECT=dot-nix \
    DOPPLER_CONFIG=dev_personal \
    DOPPLER_ENVIRONMENT=dev \
    AZURE_OPENAI_API_KEY=SYNTHETIC_PROFILE_VALUE \
    "$runner/bin/doppler-run" --internal-launch azure-grok -- /bin/sh -c \
    'test "$AZURE_OPENAI_API_KEY" = SYNTHETIC_PROFILE_VALUE && test -z "${DOPPLER_TOKEN+x}" && test -z "${DOPPLER_CONFIG_DIR+x}" && test -z "${DOPPLER_PROJECT+x}" && test -z "${DOPPLER_CONFIG+x}" && test -z "${DOPPLER_ENVIRONMENT+x}"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "internal boundary rejects missing and extra automatic metadata" {
  runner="$(build_home_package doppler-run)"
  base=(env -i HOME="$HOME" PATH=/usr/bin:/bin \
    DOPPLER_TOKEN=SYNTHETIC_BOOTSTRAP_TOKEN \
    DOPPLER_PROJECT=dot-nix DOPPLER_CONFIG=dev_personal \
    AZURE_OPENAI_API_KEY=SYNTHETIC_PROFILE_VALUE)
  run "${base[@]}" "$runner/bin/doppler-run" --internal-launch azure-grok -- /bin/true
  [ "$status" -ne 0 ]
  [[ "$output" != *SYNTHETIC_BOOTSTRAP_TOKEN* ]]
  run "${base[@]}" DOPPLER_ENVIRONMENT=dev CLAUDE_CODE_OAUTH_TOKEN=SYNTHETIC_EXTRA \
    "$runner/bin/doppler-run" --internal-launch azure-grok -- /bin/true
  [ "$status" -ne 0 ]
  [[ "$output" != *SYNTHETIC_EXTRA* ]]
}

@test "internal boundary rejects metadata that differs from fixed CLI source" {
  runner="$(build_home_package doppler-run)"
  run env -i HOME="$HOME" PATH=/usr/bin:/bin \
    DOPPLER_TOKEN=SYNTHETIC_BOOTSTRAP_TOKEN \
    DOPPLER_PROJECT=wrong-project DOPPLER_CONFIG=dev_personal DOPPLER_ENVIRONMENT=dev \
    AZURE_OPENAI_API_KEY=SYNTHETIC_PROFILE_VALUE \
    "$runner/bin/doppler-run" --internal-launch azure-grok -- /bin/true
  [ "$status" -ne 0 ]
  [[ "$output" != *wrong-project* ]]
  run env -i HOME="$HOME" PATH=/usr/bin:/bin \
    DOPPLER_TOKEN=SYNTHETIC_BOOTSTRAP_TOKEN \
    DOPPLER_PROJECT=dot-nix DOPPLER_CONFIG=dev_personal DOPPLER_ENVIRONMENT= \
    AZURE_OPENAI_API_KEY=SYNTHETIC_PROFILE_VALUE \
    "$runner/bin/doppler-run" --internal-launch azure-grok -- /bin/true
  [ "$status" -ne 0 ]
}

@test "token accepts only the exact deployment link to a safe terminal file" {
  runner="$(build_home_package doppler-run)"
  script="$(sed -n 's/^exec python3 \([^ ]*doppler-run.py\).*/\1/p' "$runner/bin/doppler-run")"
  python="$(grep -o '/nix/store/[^:]*python3[^:]*/bin' "$runner/bin/doppler-run" | head -n1)/python3"
  run "$python" - "$script" <<'PY'
import contextlib, io, os, runpy, tempfile
ns = runpy.run_path(__import__('sys').argv[1])
open_link = ns['open_expected_link']
root = tempfile.mkdtemp()
config = os.path.join(root, 'config', 'sops-nix')
generation = os.path.join(root, 'generation')
os.makedirs(config); os.makedirs(generation)
target = os.path.join(config, 'secrets', 'doppler_token')
terminal = os.path.join(generation, 'doppler_token')
open(terminal, 'wb').write(b'SYNTHETIC_TOKEN')
os.chmod(terminal, 0o400)
os.symlink(generation, os.path.join(config, 'secrets'))
deploy = os.path.join(root, 'token')
os.symlink(target, deploy)
fd = open_link(deploy, target, 0o400)
assert os.read(fd, 64) == b'SYNTHETIC_TOKEN'; os.close(fd)
def rejected(setup):
    try:
        setup()
        with contextlib.redirect_stderr(io.StringIO()): open_link(deploy, target, 0o400)
    except SystemExit:
        return
    raise AssertionError('unsafe fixture accepted')
os.unlink(deploy)
rejected(lambda: os.symlink(os.path.join(config, 'secrets', 'other'), deploy))
os.unlink(deploy)
rejected(lambda: open(deploy, 'wb').close())
os.unlink(deploy)
os.symlink(target, deploy); os.chmod(terminal, 0o600)
rejected(lambda: None)
print('token-link-fixtures-ok')
PY
  [ "$status" -eq 0 ]
  [ "$output" = token-link-fixtures-ok ]
}

@test "Grok policy parser requires exact table keys and exclusion membership" {
  grep -q 'set(policy) !=' "$MODULE"
  grep -q 'set(excludes) != GROK_EXCLUDES' "$MODULE"
  grep -q 'len(excludes) != len(set(excludes))' "$MODULE"
}

@test "Codex wrapper emits the exact valid strict controls" {
  codex="$(build_home_package codex-azure)"
  wrapper="$codex/bin/codex-azure"
  grep -Fq -- '--disable hooks' "$wrapper"
  grep -Fq -- '--disable shell_snapshot' "$wrapper"
  grep -Fq -- "-c 'notify=[]'" "$wrapper"
  grep -Fq -- "-c 'shell_environment_policy.inherit=\"core\"'" "$wrapper"
  grep -Fq -- "-c 'shell_environment_policy.ignore_default_excludes=false'" "$wrapper"
  grep -Fq -- "-c 'shell_environment_policy.exclude=[\"AZURE_OPENAI_API_KEY\"]'" "$wrapper"
  ! grep -Fq -- "-c 'hooks=[]'" "$wrapper"
  ! grep -Fq -- "-c 'shell_snapshot=false'" "$wrapper"
  grep -Fq 'caller configuration overrides are not allowed' "$wrapper"
}

@test "legacy global loader is gone and cleanup is unconditional" {
  ! grep -q 'programs.zsh.envExtra' "$MODULE"
  ! grep -q 'doppler secrets download' "$MODULE"
  grep -q 'home.activation.dopplerLegacyCleanup' "$MODULE"
  grep -q '\$DRY_RUN_CMD rm' "$MODULE"
}
