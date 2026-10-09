#!/usr/bin/env bats

load "../lib/home-config"

setup_file() {
  TEST_PYTHON_ROOT=$(nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"git+file://$REPO\"; p = import f.inputs.nixpkgs { system = builtins.currentSystem; }; in p.python3.withPackages (ps: [ ps.tomlkit ])")
  export TEST_PYTHON="$TEST_PYTHON_ROOT/bin/python3"
}

setup() {
  require_home_config
  export TMPDIR="$BATS_TEST_TMPDIR"
}

secrets_enabled() {
  nix eval --json --file "$REPO/hosts.nix" --apply \
    "h: let chosen = h.\"$(home_config_name)\"; base = if chosen ? sharedConfig then h.\${chosen.sharedConfig} else {}; host = base // chosen; in host.enableSecrets or false"
}

@test "all non-NVIDIA host packages files and dispatch follow enableSecrets" {
  run nix eval --json --impure --expr "
    let
      f = builtins.getFlake \"git+file://$REPO\";
      registry = import $REPO/hosts.nix;
      lib = f.inputs.nixpkgs.lib;
      names = builtins.filter (name: !(registry.\${name}.nvidiaGpu or false)) (builtins.attrNames registry);
      packages = [ \"bedrock-api-key\" \"grok-bedrock\" \"claude-bedrock\" \"bedrock-key-admin\" \"bedrock-grok-config\" \"bedrock-verify\" \"bedrock-build-manifest\" ];
      files = [ \"grok/bin/bedrock-api-key\" \"claude/bedrock-settings.json\" \"bedrock-api-key/build-manifest.json\" ];
      check = name:
        let
          selected = registry.\${name};
          host = (if selected ? sharedConfig then registry.\${selected.sharedConfig} else {}) // selected;
          enabled = host.enableSecrets or false;
          config = f.homeConfigurations.\${name}.config;
          installed = map (package: package.name or \"\") config.home.packages;
        in {
          inherit enabled;
          packages = builtins.all (package: (builtins.elem package installed) == enabled) packages;
          files = builtins.all (file: (builtins.hasAttr file config.xdg.configFile) == enabled) files;
          dispatch = (lib.hasInfix \"command claude-bedrock\" config.programs.zsh.siteFunctions.claude) == enabled;
        };
      checks = lib.genAttrs names check;
    in assert builtins.all (result: result.packages && result.files && result.dispatch) (builtins.attrValues checks);
       checks"
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "Bedrock packages and Claude dispatch follow enableSecrets" {
  enabled=$(secrets_enabled)
  names="$BATS_TEST_TMPDIR/packages.json"
  functions="$BATS_TEST_TMPDIR/functions.json"
  nix eval --json --impure --expr \
    "let f = builtins.getFlake \"git+file://$REPO\"; in map (p: p.name or \"\") f.homeConfigurations.\"$(home_config_name)\".config.home.packages" > "$names"
  nix eval --json --impure --expr \
    "let f = builtins.getFlake \"git+file://$REPO\"; z = f.homeConfigurations.\"$(home_config_name)\".config.programs.zsh.siteFunctions; in { inherit (z) claude cc grok; cct = z.claude-code-toggle; _cct_current = z._cct_current; _cct_enabled = z._cct_enabled; }" > "$functions"
  run "$TEST_PYTHON" - "$names" "$functions" "$enabled" <<'PY'
import json, sys
from pathlib import Path
names = set(json.loads(Path(sys.argv[1]).read_text()))
functions = json.loads(Path(sys.argv[2]).read_text())
enabled = json.loads(sys.argv[3])
expected = {"bedrock-api-key", "grok-bedrock", "claude-bedrock", "bedrock-key-admin", "bedrock-grok-config", "bedrock-verify", "bedrock-build-manifest"}
assert (names & expected) == (expected if enabled else set())
assert ("command claude-bedrock" in functions["claude"]) == enabled
assert 'command claude "$@"' in functions["claude"]
assert 'env -u DO_NOT_TRACK' not in functions["claude"]
assert 'claude "$@"' in functions["cc"]
assert 'command grok-azure "$@"' in functions["grok"]
print("host-flags-ok")
PY
  [ "$status" -eq 0 ]
  [ "$output" = host-flags-ok ]
}

@test "generated Claude functions preserve arguments DNT and cc-only trust" {
  enabled=$(secrets_enabled)
  functions="$BATS_TEST_TMPDIR/functions.json"
  fixture="$BATS_TEST_TMPDIR/dispatch"
  mkdir -p "$fixture/bin" "$fixture/claude" "$fixture/work"
  printf '{"projects":{}}\n' > "$fixture/claude/.claude.json"
  nix eval --json --impure --expr \
    "let f = builtins.getFlake \"git+file://$REPO\"; z = f.homeConfigurations.\"$(home_config_name)\".config.programs.zsh.siteFunctions; in { inherit (z) claude cc; cct = z.claude-code-toggle; _cct_current = z._cct_current; _cct_enabled = z._cct_enabled; }" > "$functions"
  "$TEST_PYTHON" - "$functions" "$fixture" <<'PY'
import json, os, sys
from pathlib import Path
functions = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2])
(root / "functions.zsh").write_text("\n".join(f"function {name}() {{\n{body}\n}}" for name, body in functions.items()))
for name in ("claude", "claude-bedrock"):
    path = root / "bin" / name
    path.write_text('#!/bin/sh\nprintf "%s|%s|%s\\n" "' + name + '" "${DO_NOT_TRACK-unset}" "$1" >> "$CALL_LOG"\n')
    path.chmod(0o700)
PY
  cat > "$fixture/dispatch-test.zsh" <<'ZSH'
set -e
cd "$1/work"
source "$1/functions.zsh"
cct bedrock >/dev/null
claude "two words"
jq -e '.projects == {}' "$CLAUDE_CONFIG_DIR/.claude.json" >/dev/null
cc "cc words"
jq -e --arg p "$PWD" '.projects[$p].hasTrustDialogAccepted == true' "$CLAUDE_CONFIG_DIR/.claude.json" >/dev/null
cct azure >/dev/null
claude "azure words"
ZSH
  run env -i HOME="$fixture" PATH="$fixture/bin:$PATH" \
    CLAUDE_CONFIG_DIR="$fixture/claude" DO_NOT_TRACK=1 CALL_LOG="$fixture/calls" \
    zsh -df "$fixture/dispatch-test.zsh" "$fixture"
  [ "$status" -eq 0 ]
  run "$TEST_PYTHON" - "$fixture/calls" "$enabled" <<'PY'
import json, sys
from pathlib import Path
enabled = json.loads(sys.argv[2])
first = "claude-bedrock|1" if enabled else "claude|1"
assert Path(sys.argv[1]).read_text().splitlines() == [first + "|two words", first + "|cc words", "claude|1|azure words"]
print("dispatch-ok")
PY
  [ "$status" -eq 0 ]
  [ "$output" = dispatch-ok ]
}

@test "native boolean values preserve Vertex and Foundry dispatch" {
  enabled=$(secrets_enabled)
  fixture="$BATS_TEST_TMPDIR/booleans"
  mkdir -p "$fixture/bin"
  nix eval --json --impure --expr \
    "let f = builtins.getFlake \"git+file://$REPO\"; z = f.homeConfigurations.\"$(home_config_name)\".config.programs.zsh.siteFunctions; in { inherit (z) claude _cct_current _cct_enabled; }" > "$fixture/functions.json"
  "$TEST_PYTHON" - "$fixture" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
functions = json.loads((root / "functions.json").read_text())
(root / "functions.zsh").write_text("\n".join(f"function {name}() {{\n{body}\n}}" for name, body in functions.items()))
for name in ("claude", "claude-bedrock"):
    path = root / "bin" / name
    path.write_text('#!/bin/sh\nprintf "%s\\n" "' + name + '" >> "$CALL_LOG"\n')
    path.chmod(0o700)
PY
  cat > "$fixture/check.zsh" <<'ZSH'
set -e
source "$1/functions.zsh"
for value in '' 0 false no off ' FALSE ' 't rue' $'\xc2\x85true'; do
  export CLAUDE_CODE_USE_BEDROCK="$value" CLAUDE_CODE_USE_VERTEX=1
  unset CLAUDE_CODE_USE_FOUNDRY
  [[ "$(_cct_current)" == vertex ]]
  claude probe
  unset CLAUDE_CODE_USE_VERTEX
  export CLAUDE_CODE_USE_FOUNDRY=1
  [[ "$(_cct_current)" == azure ]]
  claude probe
 done
unset CLAUDE_CODE_USE_FOUNDRY CLAUDE_CODE_USE_VERTEX
for value in 1 true yes on TRUE ' YES ' $'\xef\xbb\xbfOn\xe3\x80\x80'; do
  export CLAUDE_CODE_USE_BEDROCK="$value"
  [[ "$(_cct_current)" == bedrock ]]
  claude probe
done
ZSH
  run env -i HOME="$fixture" PATH="$fixture/bin:$PATH" LC_ALL=C CALL_LOG="$fixture/calls" \
    zsh -df "$fixture/check.zsh" "$fixture"
  [ "$status" -eq 0 ]
  run "$TEST_PYTHON" - "$fixture/calls" "$enabled" <<'PY'
import json, sys
from pathlib import Path
expected = ["claude"] * 16 + (["claude-bedrock"] if json.loads(sys.argv[2]) else ["claude"]) * 7
assert Path(sys.argv[1]).read_text().splitlines() == expected
print("native-booleans-ok")
PY
  [ "$status" -eq 0 ]
  [ "$output" = native-booleans-ok ]
}

@test "Bedrock Doppler profiles select one key and remove bootstrap data" {
  enabled=$(secrets_enabled)
  runner=$(build_home_package doppler-run)
  run "$TEST_PYTHON" - "$runner/bin/doppler-run" "$enabled" <<'PY'
import contextlib, io, os, re, runpy, sys
from pathlib import Path
from unittest.mock import patch
script = re.search(r"exec python3 -I (/nix/store/\S+doppler-run\.py)", Path(sys.argv[1]).read_text()).group(1)
ns = runpy.run_path(script)
enabled = sys.argv[2] == "true"
profiles = ("bedrock-grok-token", "bedrock-claude")
assert all((p in ns["PROFILES"]) == enabled for p in profiles)
assert ("AWS_BEARER_TOKEN_BEDROCK" in ns["SENSITIVE"]) == enabled
if enabled:
    base = {"DOPPLER_TOKEN": "SYNTHETIC_BOOTSTRAP", "DOPPLER_PROJECT": "dot-nix", "DOPPLER_CONFIG": "dev_personal", "DOPPLER_ENVIRONMENT": "dev", "AWS_BEARER_TOKEN_BEDROCK": "SYNTHETIC_KEY"}
    for profile in profiles:
        argv = ns["bootstrap_argv"](profile, ["/bin/true"])
        assert "--no-fallback" in argv
        assert argv.count("--only-secrets") == 1
        assert argv[argv.index("--only-secrets") + 1] == "AWS_BEARER_TOKEN_BEDROCK"
        captured = []
        with patch.dict(os.environ, base, clear=True), patch.object(os, "execvpe", side_effect=lambda binary, args, env: captured.append(env)):
            ns["launch"](profile, ["/bin/true"])
        assert set(captured[0]) == {"AWS_BEARER_TOKEN_BEDROCK", "DOPPLER_CONFIG_DIR"}
        assert captured[0]["AWS_BEARER_TOKEN_BEDROCK"] == "SYNTHETIC_KEY"
        for value in (None, "", "key\n"):
            invalid = dict(base)
            invalid.pop("AWS_BEARER_TOKEN_BEDROCK")
            if value is not None:
                invalid["AWS_BEARER_TOKEN_BEDROCK"] = value
            with patch.dict(os.environ, invalid, clear=True), contextlib.redirect_stderr(io.StringIO()):
                try:
                    ns["launch"](profile, ["/bin/true"])
                except SystemExit:
                    continue
                raise AssertionError("invalid key accepted")
print("profiles-ok")
PY
  [ "$status" -eq 0 ]
  [ "$output" = profiles-ok ]
}

@test "build manifest and secret-free Claude overlay work before activation" {
  enabled=$(secrets_enabled)
  if [ "$enabled" = true ]; then
    package=$(build_home_package bedrock-build-manifest)
    manifest=$("$package/bin/bedrock-build-manifest")
    run "$TEST_PYTHON" - "$manifest" <<'PY'
import importlib.util, json, os, stat, sys
from pathlib import Path
manifest = json.loads(Path(sys.argv[1]).read_text())
for path in manifest.values():
    assert path.startswith("/nix/store/") and Path(path).exists()
for name in ("grok_key_helper", "grok_launcher", "claude_launcher", "key_admin", "grok_config", "verify", "doppler_run", "python"):
    assert os.access(manifest[name], os.X_OK)
for name in ("empty_aws_config", "empty_aws_credentials"):
    assert stat.S_ISREG(Path(manifest[name]).stat().st_mode)
    assert Path(manifest[name]).read_bytes() == b""
overlay = json.loads(Path(manifest["claude_overlay"]).read_text())
env = overlay["env"]
assert "AWS_BEARER_TOKEN_BEDROCK" not in env
assert "CLAUDE_CODE_SKIP_BEDROCK_AUTH" not in env
assert env["AWS_REGION"] == "ap-northeast-1"
assert env["AWS_CONFIG_FILE"] == manifest["empty_aws_config"]
assert env["AWS_SHARED_CREDENTIALS_FILE"] == manifest["empty_aws_credentials"]
assert env["CLAUDE_CODE_SUBPROCESS_ENV_SCRUB"] == "1"
assert env["ANTHROPIC_DEFAULT_OPUS_MODEL"] == "global.anthropic.claude-opus-5-5[1m]"
assert env["ANTHROPIC_DEFAULT_FABLE_MODEL"] == "global.anthropic.claude-fable-5-1[1m]"
assert env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] == "global.anthropic.claude-haiku-5-5"
assert env["ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME"] == "Bedrock Claude Haiku 5.5"
assert overlay["model"] == "opus[1m]" and overlay["fallbackModel"] == ["sonnet"]
spec = importlib.util.spec_from_file_location("bedrock_claude_store", manifest["claude_script"])
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
module.validate_overlay(module.load_runtime(manifest["runtime_config"]))
spec = importlib.util.spec_from_file_location("bedrock_key_admin_store", manifest["key_admin_script"])
admin = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = admin
spec.loader.exec_module(admin)
admin.load_runtime(manifest["key_admin_runtime"])
print("manifest-ok")
PY
    [ "$status" -eq 0 ]
    [ "$output" = manifest-ok ]
  else
    run nix eval --json --impure --expr \
      "let f = builtins.getFlake \"git+file://$REPO\"; c = f.homeConfigurations.\"$(home_config_name)\".config.xdg.configFile; in !(builtins.hasAttr \"bedrock-api-key/build-manifest.json\" c) && !(builtins.hasAttr \"claude/bedrock-settings.json\" c)"
    [ "$status" -eq 0 ]
    [ "$output" = true ]
  fi
}

@test "offline Python contracts cover Grok Claude and Doppler administration" {
  for script in bedrock_grok.py bedrock_claude.py bedrock_key_admin.py bedrock_verify.py bedrock_process.py; do
    run "$TEST_PYTHON" -I -W error::ResourceWarning "$REPO/tests/lib/$script"
    if [ "$status" -ne 0 ]; then
      printf '%s\n' "$output" >&2
    fi
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ran "*" tests"* ]]
    [[ "$output" != *"skipped="* ]]
  done
}
