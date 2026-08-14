#!/usr/bin/env bats

load "../lib/home-config"

MODULE="$REPO/modules/secrets/doppler.nix"

setup() {
  require_home_config
}

@test "fixed profiles pin Doppler source and repeated selective retrieval" {
  grep -Fq '"--project", "dot-nix", "--config", "dev_personal"' "$MODULE"
  grep -Fq 'argv.extend(("--only-secrets", name))' "$MODULE"
  ! grep -q -- '--no-exit-on-missing-only-secrets' "$MODULE"
}

@test "bootstrap pins its source with flags and strips every DOPPLER_ override" {
  ! grep -q -- '--no-read-env' "$MODULE"
  grep -Fq '"--api-host", "https://api.doppler.com",' "$MODULE"
  grep -Fq '"--config-dir", RUN_CONFIG_DIR,' "$MODULE"
  grep -Fq '"--no-verify-tls=false", "--no-check-version",' "$MODULE"
  grep -Fq 'exec python3 -I ' "$MODULE"
  grep -Fq 'sys.executable, "-I", os.path.realpath(__file__)' "$MODULE"
  grep -Fq 'if k not in SANITIZE and not k.startswith("DOPPLER_")' "$MODULE"
  # 不綁縮排,嵌入腳本重排時不會靜默變成永真。只釘 base64:signal 有正當用途
  # (exec 前把 SIGPIPE 還原成 SIG_DFL),不該被測試擋在門外。
  ! grep -Eq '^ *import base64$' "$MODULE"
  ! grep -Fq 'env["DOPPLER_CONFIG_DIR"]' "$MODULE"
  grep -Fq 'dopplerRunConfigDir = "${config.xdg.cacheHome}/doppler-run"' "$MODULE"
  grep -Fq 'reset_run_config_file()' "$MODULE"
  grep -Fq 'SANITIZE = SENSITIVE | {"DOPPLER_CONFIG_DIR"}' "$MODULE"
  grep -Fq 'final["DOPPLER_CONFIG_DIR"] = RUN_CONFIG_DIR' "$MODULE"
  grep -Fq 'boundary = required | {"DOPPLER_TOKEN"} | BOOTSTRAP_METADATA' "$MODULE"
  grep -Fq '"DOPPLER_PROJECT",' "$MODULE"
  grep -Fq '"DOPPLER_CONFIG",' "$MODULE"
  grep -Fq '"DOPPLER_ENVIRONMENT",' "$MODULE"
}

@test "internal boundary requires automatic metadata and removes all bootstrap names from target" {
  runner="$(build_home_package doppler-run)"
  isolated="${XDG_CACHE_HOME:-$HOME/.cache}/doppler-run"
  run env -i HOME="$HOME" PATH=/usr/bin:/bin \
    DOPPLER_TOKEN=SYNTHETIC_BOOTSTRAP_TOKEN \
    DOPPLER_PROJECT=dot-nix \
    DOPPLER_CONFIG=dev_personal \
    DOPPLER_ENVIRONMENT=dev \
    AZURE_OPENAI_API_KEY=SYNTHETIC_PROFILE_VALUE \
    "$runner/bin/doppler-run" --internal-launch azure-grok -- /bin/sh -c \
    'test "$AZURE_OPENAI_API_KEY" = SYNTHETIC_PROFILE_VALUE && test -z "${DOPPLER_TOKEN+x}" && test "$DOPPLER_CONFIG_DIR" = "'"$isolated"'" && test -z "${DOPPLER_PROJECT+x}" && test -z "${DOPPLER_CONFIG+x}" && test -z "${DOPPLER_ENVIRONMENT+x}"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "target environment carries no caller-supplied DOPPLER_ override" {
  runner="$(build_home_package doppler-run)"
  isolated="${XDG_CACHE_HOME:-$HOME/.cache}/doppler-run"
  run env -i HOME="$HOME" PATH=/usr/bin:/bin \
    DOPPLER_TOKEN=SYNTHETIC_BOOTSTRAP_TOKEN \
    DOPPLER_PROJECT=dot-nix \
    DOPPLER_CONFIG=dev_personal \
    DOPPLER_ENVIRONMENT=dev \
    DOPPLER_API_HOST=http://127.0.0.1:1 \
    DOPPLER_NO_VERIFY_TLS=true \
    AZURE_OPENAI_API_KEY=SYNTHETIC_PROFILE_VALUE \
    "$runner/bin/doppler-run" --internal-launch azure-grok -- /bin/sh -c \
    'test -z "${DOPPLER_API_HOST+x}" && test -z "${DOPPLER_NO_VERIFY_TLS+x}" && test "$DOPPLER_CONFIG_DIR" = "'"$isolated"'"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "internal boundary rejects a foreign config directory" {
  runner="$(build_home_package doppler-run)"
  run env -i HOME="$HOME" PATH=/usr/bin:/bin \
    DOPPLER_TOKEN=SYNTHETIC_BOOTSTRAP_TOKEN \
    DOPPLER_PROJECT=dot-nix \
    DOPPLER_CONFIG=dev_personal \
    DOPPLER_ENVIRONMENT=dev \
    DOPPLER_CONFIG_DIR="$HOME/.config/doppler" \
    AZURE_OPENAI_API_KEY=SYNTHETIC_PROFILE_VALUE \
    "$runner/bin/doppler-run" --internal-launch azure-grok -- /bin/true
  [ "$status" -ne 0 ]
  [[ "$output" != *SYNTHETIC_BOOTSTRAP_TOKEN* ]]
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
  script="$(grep -o '/nix/store/[^ ]*doppler-run\.py' "$runner/bin/doppler-run" | head -n1)"
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

@test "bootstrap environment drops transport overrides and the argv pins every source" {
  runner="$(build_home_package doppler-run)"
  script="$(grep -o '/nix/store/[^ ]*doppler-run\.py' "$runner/bin/doppler-run" | head -n1)"
  python="$(grep -o '/nix/store/[^:]*python3[^:]*/bin' "$runner/bin/doppler-run" | head -n1)/python3"
  run "$python" - "$script" <<'PY'
import runpy, sys
ns = runpy.run_path(sys.argv[1])
transport = ns['TRANSPORT']
stash = ns['STASH_PREFIX']
assert 'HTTP_PROXY' in transport and 'HTTPS_PROXY' in transport, 'Go reads these'
assert 'SSL_CERT_FILE' in transport and 'SSL_CERT_DIR' in transport, 'these replace the trust store'
source = {
    'PATH': '/usr/bin', 'HOME': '/home/x', 'NIX_SSL_CERT_FILE': '/nix/ca.pem',
    'DOPPLER_API_HOST': 'http://127.0.0.1:1', 'DOPPLER_CONFIG_DIR': '/tmp/evil',
    'AZURE_OPENAI_API_KEY': 'SYNTHETIC_PROFILE_VALUE',
    # 呼叫者預埋的 stash 名:真名的值必須勝,非 TRANSPORT 的名字不得被還原
    stash + 'HTTPS_PROXY': 'http://127.0.0.1:6666',
    stash + 'LD_PRELOAD': '/tmp/evil.so',
}
source.update({name: 'transport-' + name for name in transport})
env = ns['bootstrap_environment'](source, 'SYNTHETIC_TOKEN')
for name in transport:
    assert name not in env, 'bootstrap environment kept ' + name
    assert env[stash + name] == 'transport-' + name, 'real name lost to a planted stash: ' + name
for name in ('DOPPLER_API_HOST', 'DOPPLER_CONFIG_DIR', 'AZURE_OPENAI_API_KEY'):
    assert name not in env, 'bootstrap environment kept ' + name
assert env['DOPPLER_TOKEN'] == 'SYNTHETIC_TOKEN', 'token not injected'
assert env['PATH'] == '/usr/bin', 'PATH dropped'
assert env['NIX_SSL_CERT_FILE'] == '/nix/ca.pem', 'Go ignores this one, keep it for the target'
restored = ns['restore_transport'](dict(env))
for name in transport:
    assert restored[name] == 'transport-' + name, 'target lost ' + name
assert 'LD_PRELOAD' not in restored, 'a non-transport stash name was promoted'
assert not [k for k in restored if k.startswith(stash)], 'stash leaked'
argv = ns['bootstrap_argv']('azure-codex', ['/bin/true'])
assert argv[argv.index('--') + 2] == '-I', 'the re-exec must be isolated too'
assert '--no-verify-tls=false' in argv, 'verify-tls not pinned'
assert '--no-check-version' in argv, 'version check not disabled'
assert argv[argv.index('--api-host') + 1] == 'https://api.doppler.com'
assert argv[argv.index('--config-dir') + 1] == ns['RUN_CONFIG_DIR']
assert argv[argv.index('--project') + 1] == 'dot-nix'
assert argv[argv.index('--config') + 1] == 'dev_personal'
assert argv.index('--') > argv.index('--only-secrets'), 'flags must precede the command'
print('bootstrap-fixtures-ok')
PY
  [ "$status" -eq 0 ]
  [ "$output" = bootstrap-fixtures-ok ]
}

@test "isolated config directory rejects unsafe fixtures and resets a poisoned config" {
  runner="$(build_home_package doppler-run)"
  script="$(grep -o '/nix/store/[^ ]*doppler-run\.py' "$runner/bin/doppler-run" | head -n1)"
  python="$(grep -o '/nix/store/[^:]*python3[^:]*/bin' "$runner/bin/doppler-run" | head -n1)/python3"
  run "$python" - "$script" <<'PY'
import contextlib, io, os, runpy, stat, sys, tempfile
ns = runpy.run_path(sys.argv[1])
ensure = ns['ensure_run_config_dir']
g = ensure.__globals__
home = tempfile.mkdtemp()
os.environ['HOME'] = home
cache = os.path.join(home, 'cache')
os.makedirs(cache, mode=0o700)
target = os.path.join(cache, 'doppler-run')
g['RUN_CONFIG_DIR'] = target
def rejected(label):
    try:
        with contextlib.redirect_stderr(io.StringIO()):
            ensure()
    except SystemExit:
        return
    raise AssertionError('unsafe fixture accepted: ' + label)
ensure()
assert stat.S_IMODE(os.lstat(target).st_mode) == 0o700, 'fresh directory is not 0700'
poisoned = os.path.join(target, '.doppler.yaml')
open(poisoned, 'w').write('scoped:\n  /:\n    api-host: http://127.0.0.1:1\n')
ensure()
assert not os.path.exists(poisoned), 'poisoned config survived'
os.chmod(target, 0o777)
ensure()
assert stat.S_IMODE(os.lstat(target).st_mode) == 0o700, 'loose mode was not tightened'
os.rmdir(target)
os.symlink(cache, target)
rejected('symlink to directory')
os.unlink(target)
open(target, 'wb').close()
rejected('regular file')
os.unlink(target)
g['RUN_CONFIG_DIR'] = os.path.join(tempfile.mkdtemp(), 'doppler-run')
rejected('outside home')
print('run-config-dir-fixtures-ok')
PY
  [ "$status" -eq 0 ]
  [ "$output" = run-config-dir-fixtures-ok ]
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
