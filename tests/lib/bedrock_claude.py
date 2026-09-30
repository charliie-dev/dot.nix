"""Synthetic-only Claude launcher contracts; no native client or credential reads."""

import hashlib
import importlib.util
import io
import json
import os
import plistlib
import pty
import shlex
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from typing import Any
from unittest import mock

SOURCE = Path(__file__).resolve().parents[2] / "conf.d/bedrock-api-key/claude.py"
PYTHON = str(Path(sys.executable).resolve())
FAKE_KEY = "synthetic-bedrock-key-never-a-real-secret"
CANARY = "synthetic-secret-must-not-appear-in-errors"


def load_module(name: str = "bedrock_claude_launcher") -> Any:
    spec = importlib.util.spec_from_file_location(name, SOURCE)
    if spec is None or spec.loader is None:
        raise RuntimeError("launcher source fixture is missing")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


sys.dont_write_bytecode = True
L = load_module()


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def executable(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"#!{PYTHON}\n{body}\n", encoding="utf-8")
    path.chmod(0o700)


def process_absent(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    return False


def stop_process(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is None:
        process.kill()
        process.wait()


def wait_for_ready(path: Path, process: subprocess.Popen[bytes]) -> dict[str, int]:
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline and process.poll() is None:
        if path.exists():
            return json.loads(path.read_text())
        time.sleep(0.01)
    raise AssertionError("synthetic runner did not become ready")


class ReviewedBuilds(unittest.TestCase):
    def test_only_reviewed_native_digests_are_allowed(self):
        self.assertEqual(
            L.REVIEWED_CLIENTS,
            {
                "fcfd837103965c64de34a6b9b94370d77a347ea71819715a27d5f0ef01775ea4": "2.1.282",
                "d8cb1e5c79684cc12a8bfc813e3a2073406921b6245744b3009be3ab5651d21e": "2.1.283",
            },
        )


class Fixture(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(
            prefix="bedrock-claude-", dir=os.environ.get("TMPDIR")
        )
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.home = self.root / "home"
        self.store = self.root / "store"
        self.bin = self.root / "bin"
        self.cwd = self.root / "checkout/nested"
        for directory in (self.home, self.store, self.bin, self.cwd):
            directory.mkdir(parents=True)
        self.claude_home = self.home / "config/claude"
        self.claude_home.mkdir(parents=True)
        self.layout = L.Layout(
            self.cwd,
            self.home,
            self.root / "system/ClaudeCode",
            (
                L.Source(
                    "managed-plist-user", self.root / "system/user.plist", True, True
                ),
                L.Source(
                    "managed-plist-device",
                    self.root / "system/device.plist",
                    True,
                    True,
                ),
            ),
            self.root,
        )
        self.script = self.store / "claude.py"
        self.script.write_bytes(SOURCE.read_bytes())
        interpreter = self.store / "python3"
        interpreter.write_text(f'#!/bin/sh\nexec {shlex.quote(PYTHON)} "$@"\n')
        interpreter.chmod(0o700)
        self.runtime = {
            "claude_home": str(self.claude_home),
            "doppler_run": str(self.store / "doppler-run"),
            "python": str(interpreter),
            "claude_binary": "claude",
            "doppler_binary": str(self.bin / "doppler"),
            "claude_overlay": str(self.store / "overlay.json"),
            "empty_aws_config": str(self.store / "aws-config"),
            "empty_aws_credentials": str(self.store / "aws-credentials"),
            "process_control": str(self.store / "process_control.py"),
            "grok_home": "/unused-grok",
        }
        Path(self.runtime["process_control"]).write_bytes(
            (SOURCE.parent / "process_control.py").read_bytes()
        )
        Path(self.runtime["empty_aws_config"]).write_bytes(b"")
        Path(self.runtime["empty_aws_credentials"]).write_bytes(b"")
        self.runtime_path = self.store / "runtime.json"
        write_json(self.runtime_path, self.runtime)
        self.overlay: dict[str, Any] = {
            "model": "opus[1m]",
            "fallbackModel": ["sonnet"],
            "env": L.fixed_environment(self.runtime)
            | dict.fromkeys(L.NEUTRALIZABLE, "")
            | {
                f"ANTHROPIC_DEFAULT_{name}_MODEL_NAME": f"Bedrock {name} fixture"
                for name in L.MODEL_PINS
            },
        }
        self.save_overlay()
        self.runner_log = self.root / "runner.json"
        self.ready = self.root / "ready.json"
        self.native_marker = self.root / "forbidden-native-command"
        self.env = {
            "HOME": str(self.home),
            "PATH": str(self.bin),
            "TMPDIR": str(self.root),
            "LANG": "C",
            "TERM": "xterm-256color",
            "USER": "fixture",
            "LOGNAME": "fixture",
        }
        self.client = self.bin / "claude"
        self.write_client(
            "import json, os, sys\nprint(json.dumps({'argv': sys.argv[1:], 'env': dict(os.environ), 'pid': os.getpid()}))"
        )
        self.write_runner()
        for name in ("aws", "doppler", "aws-helper"):
            executable(
                self.bin / name,
                f"from pathlib import Path\nPath({str(self.native_marker)!r}).touch()\nraise SystemExit(91)",
            )
        self.enterContext(mock.patch.object(L, "STORE_ROOT", self.store))
        self.enterContext(mock.patch.object(L, "SCRIPT_PATH", self.script))
        self.enterContext(
            mock.patch.object(L, "REVIEWED_CLIENTS", {self.digest: "2.1.282"})
        )
        self.enterContext(mock.patch.object(L, "host_layout", return_value=self.layout))
        self.enterContext(mock.patch.dict(os.environ, self.env, clear=True))

    def tearDown(self):
        self.assertFalse(self.native_marker.exists())

    def write_client(self, body: str) -> None:
        executable(self.client, body)
        self.digest = hashlib.sha256(self.client.read_bytes()).hexdigest()

    def save_overlay(self) -> None:
        write_json(Path(self.runtime["claude_overlay"]), self.overlay)

    def write_runner(self, body: str | None = None) -> None:
        default = f"env = dict(os.environ)\nenv[{L.KEY_NAME!r}] = {FAKE_KEY!r}\nenv['DOPPLER_CONFIG_DIR'] = '/synthetic/isolated'\nos.execve(sys.argv[3], sys.argv[3:], env)"
        prefix = (
            "import json, os, signal, subprocess, sys, time\nfrom pathlib import Path\n"
            f"Path({str(self.runner_log)!r}).write_text(json.dumps({{'argv': sys.argv[1:], 'env': dict(os.environ)}}))\n"
            "if sys.argv[1:3] != ['bedrock-claude', '--']:\n    raise SystemExit(92)\n"
        )
        executable(
            Path(self.runtime["doppler_run"]),
            prefix + (default if body is None else body),
        )

    def setting(self, value: Any, path: Path | None = None) -> Path:
        target = self.claude_home / "settings.json" if path is None else path
        write_json(target, value)
        return target

    def prepare(self, arguments: list[str] | None = None):
        return L.preflight(self.runtime, arguments or [], dict(os.environ), self.layout)

    def reject(self, code: str, function: Any, *args: Any) -> None:
        with self.assertRaises(L.LaunchError) as raised:
            function(*args)
        self.assertEqual(raised.exception.code, code)

    def run_main(self, args: list[str] | None = None):
        stdout, stderr = io.StringIO(), io.StringIO()
        with (
            redirect_stdout(stdout),
            redirect_stderr(stderr),
            mock.patch.object(L.os, "execve") as execute,
        ):
            status = L.main([str(self.runtime_path), *(args or [])])
        return status, stdout.getvalue(), stderr.getvalue(), execute

    def driver(self, args: list[str] | None = None) -> list[str]:
        code = (
            "import importlib.util, sys\nfrom pathlib import Path\n"
            f"s=importlib.util.spec_from_file_location('fixture_launcher', {str(self.script)!r})\n"
            "m=importlib.util.module_from_spec(s); sys.modules[s.name]=m; s.loader.exec_module(m)\n"
            f"m.STORE_ROOT=Path({str(self.store)!r}); m.REVIEWED_CLIENTS={{{self.digest!r}: '2.1.282'}}\n"
            f"m.host_layout=lambda: m.Layout(Path({str(self.cwd)!r}), Path({str(self.home)!r}), Path({str(self.layout.managed_dir)!r}), (), Path({str(self.root)!r}))\n"
            "sys.exit(m.main(sys.argv[1:]))\n"
        )
        return [PYTHON, "-I", "-c", code, str(self.runtime_path), *(args or [])]

    def run_driver(self, args: list[str] | None = None):
        return subprocess.run(
            self.driver(args),
            cwd=self.cwd,
            env=self.env,
            capture_output=True,
            timeout=8,
            check=False,
        )

    def wait_ready(self, process: subprocess.Popen[bytes]) -> dict[str, int]:
        return wait_for_ready(self.ready, process)


class PublicArtifacts(Fixture):
    def test_runtime_accepts_shared_fields_and_default_binary(self):
        self.runtime.pop("claude_binary")
        write_json(self.runtime_path, self.runtime)
        self.assertEqual(
            L.load_runtime(str(self.runtime_path))["claude_binary"], "claude"
        )

    def test_runtime_rejects_nonstore_configuration(self):
        outside = self.root / "runtime.json"
        write_json(outside, self.runtime)
        self.reject("runtime", L.load_runtime, str(outside))

    def test_runtime_requires_absolute_nonempty_paths(self):
        for value in ("", "relative", None, False, "/not-in-store"):
            self.reject("runtime", L.store_file, value)

    def test_store_path_cannot_escape_with_parent_segments(self):
        outside = self.root / "outside"
        outside.write_text("synthetic")
        self.reject("runtime", L.store_file, str(self.store / "../outside"))

    def test_store_data_symlink_is_rejected(self):
        link = self.store / "link"
        link.symlink_to(self.runtime_path)
        self.reject("runtime", L.store_file, str(link))

    def test_store_interpreter_link_must_stay_in_store(self):
        link = self.store / "python-link"
        link.symlink_to(self.runtime["python"])
        self.assertEqual(L.store_file(str(link), executable=True), link)
        link.unlink()
        link.symlink_to(PYTHON)
        self.reject("runtime", L.store_file, str(link), True)

    def test_empty_aws_files_are_required_before_bootstrap(self):
        Path(self.runtime["empty_aws_credentials"]).write_text(CANARY)
        status, stdout, stderr, execute = self.run_main()
        self.assertEqual(status, 1)
        self.assertEqual(stdout, "")
        self.assertNotIn(CANARY, stderr)
        execute.assert_not_called()
        self.assertFalse(self.runner_log.exists())

    def test_public_overlay_pins_and_display_names(self):
        env = L.validate_overlay(self.runtime)
        self.assertTrue(env["ANTHROPIC_DEFAULT_FABLE_MODEL"].endswith("[1m]"))
        self.assertTrue(env["ANTHROPIC_DEFAULT_OPUS_MODEL"].endswith("[1m]"))
        self.assertEqual(env["CLAUDE_CODE_SUBPROCESS_ENV_SCRUB"], "1")
        self.assertNotIn(L.KEY_NAME, env)

    def test_overlay_rejects_persisted_bearer_even_empty(self):
        self.overlay["env"][L.KEY_NAME] = ""
        self.save_overlay()
        self.reject("overlay", L.validate_overlay, self.runtime)

    def test_overlay_rejects_model_or_fallback_drift(self):
        self.overlay["fallbackModel"] = ["haiku"]
        self.save_overlay()
        self.reject("overlay", L.validate_overlay, self.runtime)

    def test_overlay_rejects_missing_foundry_neutralization(self):
        self.overlay["env"].pop("ANTHROPIC_FOUNDRY_API_KEY")
        self.save_overlay()
        self.reject("overlay", L.validate_overlay, self.runtime)

    def test_unknown_client_version_is_not_executed(self):
        self.client.write_text(f"#!{PYTHON}\nraise Exception({CANARY!r})\n")
        status, stdout, stderr, execute = self.run_main()
        self.assertEqual(status, 1)
        self.assertEqual(stdout, "")
        self.assertIn("unsupported-client", stderr)
        self.assertNotIn(CANARY, stderr)
        execute.assert_not_called()
        self.assertFalse(self.runner_log.exists())

    def test_client_version_cannot_be_asserted_by_runtime(self):
        self.runtime["claude_version"] = "2.1.282"
        self.runtime["claude_sha256"] = self.digest
        with mock.patch.object(L, "REVIEWED_CLIENTS", {}):
            self.reject("unsupported-client", self.prepare)


class Settings(Fixture):
    def test_empty_persisted_bearer_is_rejected(self):
        self.setting({"env": {L.KEY_NAME: ""}})
        self.reject("persisted-bearer", self.prepare)

    def test_nonempty_persisted_bearer_is_rejected(self):
        self.setting({"env": {L.KEY_NAME: CANARY}})
        self.reject("persisted-bearer", self.prepare)

    def test_skip_auth_presence_is_rejected(self):
        for value in ("", "0", "false", "true"):
            self.setting({"env": {"CLAUDE_CODE_SKIP_BEDROCK_AUTH": value}})
            self.reject("skip-auth", self.prepare)

    def test_helper_presence_including_empty_and_null_is_rejected(self):
        for helper in L.AUTH_HELPERS:
            self.setting({helper: ""})
            self.reject("auth-helper", self.prepare)
        self.setting({"apiKeyHelper": None})
        self.reject("auth-helper", self.prepare)

    def test_legacy_global_files_are_checked(self):
        for name in (".claude.json", ".config.json"):
            path = self.setting({"awsCredentialExport": ""}, self.claude_home / name)
            self.reject("auth-helper", self.prepare)
            path.unlink()

    def test_project_local_and_ancestor_settings_are_checked(self):
        locations = (self.cwd, self.cwd.parent, self.root)
        for directory in locations:
            path = self.setting(
                {"env": {L.KEY_NAME: ""}}, directory / ".claude/settings.local.json"
            )
            self.reject("persisted-bearer", self.prepare)
            path.unlink()
        self.setting({"apiKeyHelper": ""}, self.cwd / ".claude/settings.json")
        self.reject("auth-helper", self.prepare)

    def test_linked_worktree_common_checkout_is_checked(self):
        main = self.root / "main"
        gitdir = main / ".git/worktrees/example"
        gitdir.mkdir(parents=True)
        (gitdir / "commondir").write_text("../..\n")
        (self.cwd / ".git").write_text(f"gitdir: {gitdir}\n")
        self.setting({"env": {L.KEY_NAME: ""}}, main / ".claude/settings.local.json")
        self.reject("persisted-bearer", self.prepare)

    def test_unrecognized_git_indirection_stops(self):
        (self.cwd / ".git").write_text(CANARY)
        self.reject("project-layout", self.prepare)

    def test_managed_json_cannot_be_neutralized_by_overlay(self):
        self.setting(
            {"env": {"CLAUDE_CODE_USE_VERTEX": "1"}},
            self.layout.managed_dir / "managed-settings.json",
        )
        self.reject("routing-conflict", self.prepare)

    def test_managed_dropins_are_checked_in_order(self):
        directory = self.layout.managed_dir / "managed-settings.d"
        self.setting({}, directory / "10-empty.json")
        self.setting({"env": {L.KEY_NAME: ""}}, directory / "20-secret.json")
        self.assertEqual(
            [source.path.name for source in L.managed_dropins(directory)],
            ["10-empty.json", "20-secret.json"],
        )
        self.reject("persisted-bearer", self.prepare)

    def test_hidden_and_non_json_dropins_are_not_loaded(self):
        directory = self.layout.managed_dir / "managed-settings.d"
        self.setting({"env": {L.KEY_NAME: CANARY}}, directory / ".hidden.json")
        self.setting({"apiKeyHelper": CANARY}, directory / "ignored.txt")
        self.assertEqual(self.prepare().report["status"], "ok")

    def test_managed_plists_are_checked_for_both_scopes_and_formats(self):
        for index, source in enumerate(self.layout.plists):
            source.path.parent.mkdir(parents=True, exist_ok=True)
            source.path.write_bytes(
                plistlib.dumps(
                    {"env": {L.KEY_NAME: ""}},
                    fmt=plistlib.FMT_BINARY if index else plistlib.FMT_XML,
                )
            )
            self.reject("persisted-bearer", self.prepare)
            source.path.unlink()

    def test_json_incompatible_managed_plist_stops(self):
        source = self.layout.plists[0]
        source.path.parent.mkdir(parents=True)
        source.path.write_bytes(plistlib.dumps({"data": b"synthetic"}))
        self.reject("settings-format", self.prepare)

    def test_duplicate_plist_keys_do_not_hide_settings(self):
        data = b'<plist version="1.0"><dict><key>env</key><dict/><key>env</key><dict/></dict></plist>'
        self.reject("settings-format", L.document, data, "managed-plist-user", True)

    def test_server_managed_cache_is_checked(self):
        self.setting(
            {"env": {"ANTHROPIC_BEDROCK_BASE_URL": "https://example.invalid"}},
            self.claude_home / "remote-settings.json",
        )
        self.reject("routing-conflict", self.prepare)

    def test_unknown_dynamic_managed_sources_stop(self):
        for field in (
            "policyHelper",
            "policyHelpers",
            "forceRemoteSettingsRefresh",
            "forceLoginGatewayUrl",
        ):
            self.setting({field: {}}, self.layout.managed_dir / "managed-settings.json")
            self.reject("host-source", self.prepare)

    def test_signed_client_data_source_requires_explicit_review(self):
        for value in ("", "https://downloads.claude.ai/synthetic/" + CANARY):
            self.setting({"env": {"CLAUDE_CODE_CLIENT_DATA_URL": value}})
            self.reject("host-source", self.prepare)
            self.reject(
                "host-source",
                L.validate_ambient,
                {"CLAUDE_CODE_CLIENT_DATA_URL": value},
            )

    def test_host_provider_flags_stop_even_when_empty(self):
        for key in (
            "CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST",
            "CLAUDE_CODE_HOST_CREDS_FILE",
            "CLAUDE_CODE_REMOTE_SETTINGS_PATH",
            "CLAUDE_CODE_BRIDGE_CHILD_MACHINE_SETTINGS",
            "CLAUDE_CODE_MOCK_REMOTE_SETTINGS",
            "CLAUDE_BG_AUTH_SNAPSHOT_PATH",
        ):
            self.setting({"env": {key: ""}})
            self.reject("host-source", self.prepare)

    def test_legacy_and_subagent_model_overrides_stop_even_when_empty(self):
        for key in L.FORBIDDEN_MODELS:
            self.setting({"env": {key: ""}})
            self.reject("model-conflict", self.prepare)

    def test_lower_provider_secrets_are_neutralized_without_rewriting_base(self):
        original = {
            "model": "old-model",
            "fallbackModel": ["old-fallback"],
            "env": {
                "ANTHROPIC_API_KEY": CANARY,
                "ANTHROPIC_FOUNDRY_API_KEY": CANARY,
                "CLAUDE_CODE_USE_VERTEX": "1",
            },
        }
        path = self.setting(original)
        before = path.read_bytes()
        prepared = self.prepare()
        self.assertEqual(prepared.environment["ANTHROPIC_API_KEY"], "")
        self.assertEqual(prepared.environment["ANTHROPIC_FOUNDRY_API_KEY"], "")
        self.assertEqual(prepared.report["fallbackModel"], ["sonnet"])
        self.assertEqual(path.read_bytes(), before)
        self.assertNotIn(CANARY, json.dumps(prepared.report))

    def test_service_tier_user_setting_is_accepted_without_rewriting(self):
        key = "ANTHROPIC_BEDROCK_SERVICE_TIER"
        for tier in ("", "default", "priority", "flex", "reserved"):
            path = self.setting({"env": {key: tier}})
            before = path.read_bytes()
            self.assertEqual(self.prepare().report["status"], "ok")
            self.assertEqual(path.read_bytes(), before)
            self.assertNotIn(key, self.overlay["env"])

    def test_service_tier_from_environment_is_preserved(self):
        key = "ANTHROPIC_BEDROCK_SERVICE_TIER"
        for tier in ("", "default", "priority", "flex", "reserved"):
            with mock.patch.dict(os.environ, {key: tier}):
                self.assertEqual(self.prepare().environment[key], tier)

    def test_service_tier_is_accepted_in_project_and_managed_sources(self):
        key = "ANTHROPIC_BEDROCK_SERVICE_TIER"
        paths = (
            self.cwd / ".claude/settings.json",
            self.cwd / ".claude/settings.local.json",
            self.layout.managed_dir / "managed-settings.json",
        )
        for path in paths:
            self.setting({"env": {key: "priority"}}, path)
            self.assertEqual(self.prepare().report["status"], "ok")
            path.unlink()

    def test_invalid_service_tiers_fail_without_exposing_values(self):
        key = "ANTHROPIC_BEDROCK_SERVICE_TIER"
        for value in ("standard", "PRIORITY", " flex ", CANARY):
            self.setting({"env": {key: value}})
            self.reject("service-tier", self.prepare)
            self.setting({})
            with mock.patch.dict(os.environ, {key: value}):
                self.reject("service-tier", self.prepare)

    def test_service_tier_does_not_allow_other_bedrock_routing_overrides(self):
        self.setting(
            {
                "env": {
                    "ANTHROPIC_BEDROCK_SERVICE_TIER": "flex",
                    "ANTHROPIC_BEDROCK_REGION_PREFIX": "us",
                }
            }
        )
        self.reject("routing-conflict", self.prepare)

    def test_unknown_gateway_and_endpoint_env_are_rejected(self):
        for key in (
            "AWS_ENDPOINT_URL_STS",
            "AWS_ENDPOINT_URL_BEDROCK_RUNTIME",
            "CLAUDE_CODE_API_BASE_URL",
            "ANTHROPIC_UNIX_SOCKET",
        ):
            self.setting({"env": {key: ""}})
            self.reject("routing-conflict", self.prepare)

    def test_empty_static_aws_keys_can_remain(self):
        self.setting({"env": dict.fromkeys(L.EMPTY_AWS_KEYS, "")})
        self.assertEqual(self.prepare().report["status"], "ok")

    def test_competing_aws_profile_and_chain_are_rejected(self):
        for key in (
            "AWS_PROFILE",
            "AWS_WEB_IDENTITY_TOKEN_FILE",
            "AWS_CONTAINER_CREDENTIALS_FULL_URI",
        ):
            self.setting({"env": {key: ""}})
            self.reject("routing-conflict", self.prepare)

    def test_managed_model_and_fallback_must_match(self):
        path = self.layout.managed_dir / "managed-settings.json"
        self.setting({"model": "sonnet"}, path)
        self.reject("model-conflict", self.prepare)
        self.setting({"model": "opus[1m]", "fallbackModel": ["sonnet"]}, path)
        self.assertEqual(self.prepare().report["status"], "ok")

    def test_model_mapping_and_allowlist_are_not_silently_ignored(self):
        for field in (
            "modelOverrides",
            "modelPicker",
            "availableModels",
            "enforceAvailableModels",
        ):
            self.setting({field: {}})
            self.reject("model-conflict", self.prepare)

    def test_new_managed_model_constraints_are_not_silently_ignored(self):
        for field, value in (
            ("deniedModels", ["claude-opus-5-5"]),
            ("availableModelsMatch", "exact"),
        ):
            for source in (
                L.Source("managed-json", self.root / "policy.json", True),
                L.Source("managed-plist", self.root / "policy.plist", True, True),
                L.Source("server-managed", self.root / "remote.json", True),
            ):
                self.reject(
                    "model-conflict",
                    L.validate_settings,
                    {field: value},
                    source,
                    self.overlay["env"],
                    L.fixed_environment(self.runtime),
                )
            L.validate_settings(
                {field: value},
                L.Source("user", self.root / "user.json"),
                self.overlay["env"],
                L.fixed_environment(self.runtime),
            )

    def test_non_object_env_and_non_string_values_stop(self):
        for env in (None, [], {"AWS_REGION": False}, {L.KEY_NAME: None}):
            self.setting({"env": env})
            self.reject("settings-format", self.prepare)

    def test_duplicate_json_invalid_utf8_and_nonfinite_values_stop(self):
        for raw in (
            b'{"env":{},"env":{}}',
            b'{"x":NaN}',
            b"[]",
            b"\xff",
            b"{",
            "{}".encode("utf-16"),
        ):
            self.reject("settings-format", L.document, raw, "user")

    def test_unreadable_source_does_not_mean_absent(self):
        with mock.patch.object(L.os, "open", side_effect=PermissionError(CANARY)):
            self.reject(
                "settings-unreadable",
                L.read_bytes,
                self.claude_home / "settings.json",
                "user",
                True,
            )

    def test_dangling_source_link_is_rejected(self):
        (self.claude_home / "settings.json").symlink_to(self.root / "missing")
        self.reject("settings-unreadable", self.prepare)

    def test_nonregular_source_never_blocks(self):
        os.mkfifo(self.claude_home / "settings.json")
        self.reject("settings-unreadable", self.prepare)


class EnvironmentAndArguments(Fixture):
    def test_ambient_credentials_endpoints_and_doppler_overrides_are_removed(self):
        dirty = {
            L.KEY_NAME: CANARY,
            "AWS_ACCESS_KEY_ID": CANARY,
            "AWS_SECRET_ACCESS_KEY": CANARY,
            "AWS_PROFILE": CANARY,
            "AWS_WEB_IDENTITY_TOKEN_FILE": CANARY,
            "AWS_CONTAINER_CREDENTIALS_FULL_URI": CANARY,
            "AWS_ENDPOINT_URL_BEDROCK": CANARY,
            "DOPPLER_TOKEN": CANARY,
            "DOPPLER_API_HOST": CANARY,
            "GROK_AUTH_PROVIDER_TOKEN": CANARY,
            "ANTHROPIC_SMALL_FAST_MODEL": CANARY,
            "CLAUDE_CODE_SUBAGENT_MODEL_FORCE": "1",
            "GOOGLE_APPLICATION_CREDENTIALS": CANARY,
            "AZURE_OPENAI_API_KEY": CANARY,
            "PYTHONPATH": CANARY,
            "BASH_ENV": CANARY,
            "DO_NOT_TRACK": "1",
            "CLAUDE_CONFIG_DIR": CANARY,
        }
        with mock.patch.dict(os.environ, dirty):
            clean = self.prepare().environment
        self.assertNotIn(CANARY, json.dumps(clean))
        self.assertNotIn(L.KEY_NAME, clean)
        self.assertEqual(clean["DO_NOT_TRACK"], "1")
        self.assertEqual(clean["CLAUDE_CONFIG_DIR"], str(self.claude_home))
        self.assertEqual(clean["AWS_CONFIG_FILE"], self.runtime["empty_aws_config"])
        self.assertEqual(
            clean["AWS_SHARED_CREDENTIALS_FILE"], self.runtime["empty_aws_credentials"]
        )
        self.assertEqual(clean["AWS_EC2_METADATA_DISABLED"], "true")

    def test_do_not_track_value_and_absence_are_preserved(self):
        for value in (None, "", "0", "1"):
            with self.subTest(value=value):
                env = dict(self.env)
                env.pop("DO_NOT_TRACK", None)
                if value is not None:
                    env["DO_NOT_TRACK"] = value
                clean = L.sanitize_environment(
                    env, self.runtime, self.overlay["env"], self.home
                )
                if value is None:
                    self.assertNotIn("DO_NOT_TRACK", clean)
                else:
                    self.assertEqual(clean["DO_NOT_TRACK"], value)

    def test_trusted_proxy_tls_and_terminal_env_are_preserved(self):
        env = self.env | {
            "HTTPS_PROXY": "https://proxy.example.invalid",
            "NODE_EXTRA_CA_CERTS": "/synthetic/ca.pem",
        }
        clean = L.sanitize_environment(
            env, self.runtime, self.overlay["env"], self.home
        )
        self.assertEqual(clean["HTTPS_PROXY"], env["HTTPS_PROXY"])
        self.assertEqual(clean["NODE_EXTRA_CA_CERTS"], env["NODE_EXTRA_CA_CERTS"])
        self.assertEqual(clean["TERM"], env["TERM"])

    def test_ambient_host_and_skip_auth_presence_stop(self):
        for key in (
            "CLAUDE_CODE_SKIP_BEDROCK_AUTH",
            "CLAUDE_CODE_HOST_CREDS_FILE",
            "CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST",
        ):
            self.reject(
                "skip-auth" if "SKIP" in key else "host-source",
                L.validate_ambient,
                {key: ""},
            )

    def test_signed_client_data_flag_cannot_add_a_startup_source(self):
        for args in (
            ["--client-data-url", "https://downloads.claude.ai/" + CANARY],
            ["--client-data-url=https://downloads.claude.ai/" + CANARY],
        ):
            self.reject("arguments", L.validate_arguments, args)
        self.assertEqual(
            L.validate_arguments(["--", "--client-data-url=" + CANARY]),
            ("opus[1m]", ["sonnet"]),
        )

    def test_settings_flags_equal_and_split_forms_stop(self):
        for flag in L.CONFIG_FLAGS:
            self.reject("arguments", L.validate_arguments, [flag, CANARY])
            self.reject("arguments", L.validate_arguments, [flag + "=" + CANARY])

    def test_models_and_fallback_keep_1m(self):
        self.assertEqual(L.validate_arguments([]), ("opus[1m]", ["sonnet"]))
        self.assertEqual(
            L.validate_arguments(["--model", "fable[1m]", "--fallback-model=sonnet"]),
            ("fable[1m]", ["sonnet"]),
        )
        self.assertEqual(L.validate_arguments(["--model=haiku"]), ("haiku", ["sonnet"]))

    def test_invalid_empty_or_duplicate_models_stop(self):
        for args in (
            ["--model"],
            ["--model="],
            ["--model", CANARY],
            ["--model=haiku", "--model=sonnet"],
            ["--fallback-model=haiku"],
        ):
            self.reject("arguments", L.validate_arguments, args)

    def test_print_continue_resume_and_prompt_delimiter_are_preserved(self):
        args = [
            "-p",
            "-c",
            "--resume",
            "fixture-session",
            "--",
            "--settings=prompt-data",
        ]
        self.assertEqual(L.validate_arguments(args), ("opus[1m]", ["sonnet"]))
        result = self.run_driver(args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(result.stdout)["argv"],
            ["--settings", self.runtime["claude_overlay"], *args],
        )

    def test_invalid_arguments_stop_before_settings_or_bootstrap(self):
        with mock.patch.object(
            L,
            "validate_overlay",
            side_effect=AssertionError("settings should not be read"),
        ):
            self.reject("arguments", self.prepare, ["--settings=" + CANARY])
        self.assertFalse(self.runner_log.exists())


class BootstrapAndLaunch(Fixture):
    def test_fixed_emitter_pipe_and_final_exec(self):
        result = self.run_driver(
            ["--model=fable[1m]", "-p", "quoted 'prompt'\nwith newline"]
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, b"")
        client = json.loads(result.stdout)
        runner = json.loads(self.runner_log.read_text())
        self.assertEqual(
            runner["argv"],
            [
                "bedrock-claude",
                "--",
                self.runtime["python"],
                "-I",
                str(self.script),
                "--internal-emit",
            ],
        )
        self.assertNotIn(L.KEY_NAME, runner["env"])
        self.assertNotIn("DOPPLER_TOKEN", runner["env"])
        self.assertEqual(client["env"][L.KEY_NAME], FAKE_KEY)
        self.assertNotIn("DOPPLER_CONFIG_DIR", client["env"])
        self.assertEqual(
            client["argv"][:2], ["--settings", self.runtime["claude_overlay"]]
        )
        self.assertNotIn(FAKE_KEY, json.dumps(client["argv"]))

    def test_no_secret_is_written_to_public_artifacts(self):
        before = {path: path.read_bytes() for path in self.store.iterdir()}
        self.assertEqual(self.run_main()[0], 0)
        self.assertEqual(
            before, {path: path.read_bytes() for path in self.store.iterdir()}
        )
        self.assertNotIn(FAKE_KEY, self.runner_log.read_text())

    def test_interactive_tty_and_outer_pid_survive(self):
        self.write_client(
            f"import json, os\nprint(json.dumps({{'stdin_tty': os.isatty(0), 'stdout_tty': os.isatty(1), 'pid': os.getpid(), 'key_present': {L.KEY_NAME!r} in os.environ}}))"
        )
        master, slave = pty.openpty()
        process = subprocess.Popen(
            self.driver(),
            cwd=self.cwd,
            env=self.env,
            stdin=slave,
            stdout=slave,
            stderr=subprocess.PIPE,
        )
        try:
            _stdout, stderr = process.communicate(timeout=8)
            self.assertEqual(process.returncode, 0, stderr)
            response = json.loads(os.read(master, 65536))
        finally:
            os.close(slave)
            os.close(master)
            stop_process(process)
        self.assertEqual(
            response,
            {
                "stdin_tty": True,
                "stdout_tty": True,
                "pid": process.pid,
                "key_present": True,
            },
        )

    def test_fake_token_missing_empty_whitespace_newline_and_large(self):
        for value in (
            "",
            " ",
            "a b",
            "key\n",
            "key\r",
            "key\t",
            "\x7f",
            "非ascii",
            '{"access_token":"SYNTHETIC_ONLY","expires_in":86400}',
            '["SYNTHETIC_ONLY"]',
            '"SYNTHETIC_ONLY"',
            "a" * (L.MAX_KEY_BYTES + 1),
        ):
            self.reject("invalid-key", L.validate_key, value)
        self.assertEqual(L.validate_key("a" * L.MAX_KEY_BYTES), "a" * L.MAX_KEY_BYTES)

    def test_emitter_stdout_is_bare_and_missing_key_stops(self):
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            L.emit_key({L.KEY_NAME: FAKE_KEY})
        self.assertEqual(stdout.getvalue(), FAKE_KEY)
        self.reject("invalid-key", L.emit_key, {})

    def test_emitter_accepts_only_the_nix_user_site_isolation_value(self):
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            L.emit_key({L.KEY_NAME: FAKE_KEY, "PYTHONNOUSERSITE": "true"})
        self.assertEqual(stdout.getvalue(), FAKE_KEY)
        self.reject(
            "emitter-boundary",
            L.emit_key,
            {L.KEY_NAME: FAKE_KEY, "PYTHONNOUSERSITE": CANARY},
        )

    def test_emitter_rejects_extra_managed_secret_and_bootstrap_token(self):
        for key in (
            "DOPPLER_TOKEN",
            "DOPPLER_PROJECT",
            "AZURE_OPENAI_API_KEY",
            "TSTRUCT_TOKEN",
            "UNEXPECTED_MANAGED_SECRET",
        ):
            self.reject("emitter-boundary", L.emit_key, {L.KEY_NAME: FAKE_KEY, key: ""})

    def test_internal_invocation_cannot_select_runtime_profile_or_command(self):
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            status = L.main(
                ["--internal-emit", str(self.runtime_path), "azure-grok", "--", "aws"]
            )
        self.assertEqual(status, 1)
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("arguments", stderr.getvalue())
        self.assertFalse(self.runner_log.exists())

    def test_bootstrap_failures_never_echo_child_output(self):
        self.write_runner(
            f"print({CANARY!r})\nprint({CANARY!r}, file=sys.stderr)\nraise SystemExit(7)"
        )
        status, stdout, stderr, execute = self.run_main()
        self.assertEqual(status, 1)
        self.assertEqual(stdout, "")
        self.assertIn("bootstrap-failed", stderr)
        self.assertNotIn(CANARY, stderr)
        execute.assert_not_called()

    def test_success_with_stderr_is_classified_without_forwarding(self):
        self.write_runner(
            f"sys.stdout.write({FAKE_KEY!r})\nsys.stderr.write({CANARY!r})"
        )
        status, stdout, stderr, execute = self.run_main()
        self.assertEqual(status, 1)
        self.assertEqual(stdout, "")
        self.assertIn("bootstrap-output", stderr)
        self.assertNotIn(CANARY, stderr)
        execute.assert_not_called()

    def test_excessive_stdout_is_bounded_and_stops(self):
        self.write_runner(
            f"sys.stdout.write('x' * {L.MAX_KEY_BYTES + 8192})\nsys.stdout.flush()\ntime.sleep(30)"
        )
        status, stdout, stderr, execute = self.run_main()
        self.assertEqual(status, 1)
        self.assertEqual(stdout, "")
        self.assertIn("bootstrap-output", stderr)
        execute.assert_not_called()

    def test_timeout_kills_and_reaps_bootstrap(self):
        self.write_runner(
            f"signal.signal(signal.SIGTERM, signal.SIG_IGN)\nPath({str(self.ready)!r}).write_text(json.dumps({{'pid': os.getpid()}}))\ntime.sleep(30)"
        )
        created: list[subprocess.Popen[Any]] = []
        original = subprocess.Popen

        def record(command: list[str], **kwargs: Any) -> subprocess.Popen[Any]:
            process = original(command, text=False, **kwargs)
            created.append(process)
            return process

        with (
            mock.patch.object(L, "BOOTSTRAP_TIMEOUT", 0.2),
            mock.patch.object(subprocess, "Popen", side_effect=record),
        ):
            status, stdout, stderr, execute = self.run_main()
        self.assertEqual(status, 1)
        self.assertEqual(stdout, "")
        self.assertIn("bootstrap-timeout", stderr)
        self.assertEqual(len(created), 1)
        self.assertIsNotNone(created[0].poll())
        self.assertTrue(process_absent(created[0].pid))
        execute.assert_not_called()

    def test_cancellation_terminates_child_process_group(self):
        body = (
            f"child = subprocess.Popen([{PYTHON!r}, '-I', '-c', 'import time; time.sleep(30)'])\n"
            "def stop(signum, frame):\n    child.wait(timeout=2)\n    raise SystemExit(0)\n"
            "signal.signal(signal.SIGTERM, stop)\n"
            f"Path({str(self.ready)!r}).write_text(json.dumps({{'pid': os.getpid(), 'child': child.pid}}))\ntime.sleep(30)"
        )
        self.write_runner(body)
        process = subprocess.Popen(
            self.driver(),
            cwd=self.cwd,
            env=self.env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        try:
            pids = self.wait_ready(process)
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=8)
        finally:
            stop_process(process)
        self.assertEqual(process.returncode, 130, stderr)
        self.assertEqual(stdout, b"")
        self.assertIn(b"cancelled", stderr)
        self.assertTrue(all(process_absent(pid) for pid in pids.values()))

    def test_changed_settings_during_bootstrap_stop(self):
        self.write_runner(
            f"Path({str(self.claude_home / 'settings.json')!r}).write_text('{{}}')\nsys.stdout.write({FAKE_KEY!r})"
        )
        status, stdout, stderr, execute = self.run_main()
        self.assertEqual(status, 1)
        self.assertEqual(stdout, "")
        self.assertIn("settings-changed", stderr)
        execute.assert_not_called()

    def test_conflicting_settings_added_during_bootstrap_stop(self):
        self.write_runner(
            f"Path({str(self.claude_home / 'settings.json')!r}).write_text({json.dumps({'env': {L.KEY_NAME: ''}})!r})\nsys.stdout.write({FAKE_KEY!r})"
        )
        self.assertIn("persisted-bearer", self.run_main()[2])

    def test_preflight_only_does_not_request_key(self):
        status, stdout, stderr, execute = self.run_main(["--bedrock-preflight"])
        self.assertEqual(status, 0)
        self.assertEqual(stderr, "")
        self.assertEqual(
            json.loads(stdout)["scope"],
            "trusted-host-startup-check-not-request-binding",
        )
        self.assertNotIn(FAKE_KEY, stdout)
        self.assertFalse(self.runner_log.exists())
        execute.assert_not_called()

    def test_unexpected_errors_are_fixed_and_safe(self):
        with mock.patch.object(L, "load_runtime", side_effect=RuntimeError(CANARY)):
            status, stdout, stderr, _execute = self.run_main()
        self.assertEqual(status, 1)
        self.assertEqual(stdout, "")
        self.assertIn("unexpected", stderr)
        self.assertNotIn(CANARY, stderr)

    def test_import_does_not_read_settings_execute_or_emit(self):
        stdout = io.StringIO()
        with (
            mock.patch.object(Path, "open", side_effect=AssertionError),
            mock.patch.object(L.os, "open", side_effect=AssertionError),
            mock.patch.object(subprocess, "Popen", side_effect=AssertionError),
            redirect_stdout(stdout),
        ):
            module = load_module("bedrock_import_fixture")
        self.assertTrue(callable(module.main))
        self.assertEqual(stdout.getvalue(), "")

    def test_fresh_key_replaces_ambient_snapshot(self):
        self.env[L.KEY_NAME] = CANARY
        self.env["DOPPLER_API_HOST"] = "https://wrong.example.invalid"
        result = self.run_driver()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["env"][L.KEY_NAME], FAKE_KEY)
        self.assertNotIn(CANARY, self.runner_log.read_text())
        self.assertNotIn("DOPPLER_API_HOST", self.runner_log.read_text())

    def test_actual_emitter_rejects_injected_source_metadata(self):
        injected = {L.KEY_NAME: FAKE_KEY, "DOPPLER_PROJECT": CANARY}
        self.write_runner(
            f"env = dict(os.environ)\nenv.update({injected!r})\nos.execve(sys.argv[3], sys.argv[3:], env)"
        )
        status, stdout, stderr, execute = self.run_main()
        self.assertEqual(status, 1)
        self.assertEqual(stdout, "")
        self.assertIn("bootstrap-failed", stderr)
        self.assertNotIn(CANARY, stderr)
        execute.assert_not_called()

    def test_bootstrap_start_failure_has_no_fallback(self):
        runtime = self.runtime | {"doppler_run": str(self.store / "absent-runner")}
        self.reject("bootstrap-start", L.read_key, runtime, self.env)
        self.assertFalse(self.runner_log.exists())

    def test_cleanup_failure_does_not_claim_children_were_terminated(self):
        control = {"capture": mock.Mock(side_effect=ValueError("cleanup-failed"))}
        with mock.patch.object(L.runpy, "run_path", return_value=control):
            self.reject("bootstrap-cleanup", L.read_key, self.runtime, self.env)
        self.assertNotIn("were terminated", L.ERRORS["bootstrap-cleanup"])

    def test_client_exec_failure_is_classified(self):
        with mock.patch.object(L.os, "execve", side_effect=OSError(CANARY)):
            self.reject(
                "client-exec", L.launch, self.runtime, [], self.env, self.layout
            )

    def test_deleted_settings_during_bootstrap_stop(self):
        path = self.setting({})
        self.write_runner(
            f"Path({str(path)!r}).unlink()\nsys.stdout.write({FAKE_KEY!r})"
        )
        status, stdout, stderr, execute = self.run_main()
        self.assertEqual(status, 1)
        self.assertEqual(stdout, "")
        self.assertIn("settings-changed", stderr)
        execute.assert_not_called()

    def test_uncaught_exception_hook_never_echoes_exception(self):
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            L.safe_exception(Exception, Exception(CANARY), None)
        self.assertIn("unexpected", stderr.getvalue())
        self.assertNotIn(CANARY, stderr.getvalue())

    def test_preflight_does_not_open_credential_paths(self):
        self.setting(
            {"env": {L.KEY_NAME: CANARY}}, self.claude_home / ".credentials.json"
        )
        self.setting({"apiKeyHelper": CANARY}, self.home / ".aws/credentials")
        with mock.patch.object(L.os, "open", wraps=os.open) as opened:
            prepared = self.prepare()
        self.assertEqual(prepared.report["status"], "ok")
        paths = {Path(call.args[0]) for call in opened.call_args_list}
        self.assertTrue(all(path.is_relative_to(self.root) for path in paths))
        self.assertNotIn(self.claude_home / ".credentials.json", paths)
        self.assertNotIn(self.home / ".aws/credentials", paths)


if __name__ == "__main__":
    unittest.main(verbosity=2)
