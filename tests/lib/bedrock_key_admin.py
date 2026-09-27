"""Offline only: python3 -I -B tests/lib/bedrock_key_admin.py.

All workflow commands use a fake runner and a synthetic HOME. Process tests run
only this interpreter or task-owned fake binaries; no Doppler/AWS/client runs.
"""

from __future__ import annotations

import copy
import importlib.util
import io
import json
import os
import signal
import sys
import tempfile
import time
import unittest
import warnings
from collections import Counter
from collections.abc import Callable
from contextlib import redirect_stderr, redirect_stdout
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any
from unittest import mock

sys.dont_write_bytecode = True
SOURCE = Path(__file__).resolve().parents[2] / "conf.d/bedrock-api-key/key_admin.py"
SPEC = importlib.util.spec_from_file_location("synthetic_bedrock_key_admin", SOURCE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Missing required key-admin fixture")
ADMIN = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = ADMIN
SPEC.loader.exec_module(ADMIN)

A = "synthetic-prior-A-not-a-real-key"
B = "synthetic-candidate-B-not-a-real-key"
C = "synthetic-unknown-C-not-a-real-key"
OTHER = "synthetic-unrelated-secret-not-for-output"
TOKEN = "synthetic-user-token-not-a-real-token"
AMBIENT = "synthetic-ambient-bootstrap-must-not-be-used"
BINARY = f"/nix/store/{'0' * 32}-doppler-3.76.5/bin/doppler"
RUNTIME = {
    "doppler_binary": BINARY,
    "project": "dot-nix",
    "doppler_config": "dev_personal",
    "api_host": "https://api.doppler.com",
}
OUTPUT_KEYS = {
    "schema",
    "action",
    "commit_state",
    "state_scope",
    "reason",
    "project",
    "doppler_config",
    "api_host",
    "secret_name",
    "write_attempted",
    "write_result",
    "matches_A",
    "matches_B",
    "workplace_matches",
    "scopes_user_confirmed",
    "exclusive_window_user_confirmed",
    "history_user_confirmed",
    "expected_current_B_verified",
    "metadata_verified",
    "event_id",
    "event_created_at",
    "no_later_target_edit",
    "compare_and_swap",
    "client_migration_verified",
    "may_revoke_keys",
    "next_step",
}


def response(value: object) -> Any:
    return ADMIN.CommandResult(0, json.dumps(value).encode())


@dataclass(repr=False)
class Call:
    operation: str
    argv: tuple[str, ...]
    payload: bytes = field(repr=False)
    environment: dict[str, str] = field(repr=False)
    timeout: float


class FakeDoppler:
    def __init__(self) -> None:
        self.values = {ADMIN.SECRET: A, "UNRELATED_SECRET": OTHER}
        self.logs: list[dict[str, Any]] = []
        self.calls: list[Call] = []
        self.counts: Counter[str] = Counter()
        self.sequence = 0
        self.commit_write = True
        self.set_result = ADMIN.CommandResult(0)
        self.failures: dict[str, Any] = {}
        self.after_write_failures: dict[str, Any] = {}
        self.hook: Callable[[str, FakeDoppler], Any] | None = None
        self.actor: dict[str, Any] = {
            "workplace": {"slug": "synthetic-workplace", "name": OTHER},
            "type": "cli_token",
            "slug": "synthetic-user-identity",
            "token_preview": TOKEN,
            "name": OTHER,
        }
        self.publish(ADMIN.SECRET, A, "synthetic-older-value")

    def publish(self, name: str, added: str, removed: str | None = None) -> str:
        previous = self.values.get(name, "") if removed is None else removed
        self.values[name] = added
        self.sequence += 1
        event_id = f"event-{self.sequence:03d}"
        when = datetime(2026, 1, 1, tzinfo=UTC) + timedelta(seconds=self.sequence)
        self.logs.insert(
            0,
            {
                "id": event_id,
                "created_at": when.isoformat(),
                "project": ADMIN.PROJECT,
                "config": ADMIN.CONFIG,
                "environment": "dev",
                "text": OTHER,
                "html": OTHER,
                "user": {"name": OTHER, "email": OTHER},
                "diff": [{"name": name, "added": added, "removed": previous}],
            },
        )
        return event_id

    @staticmethod
    def operation(argv: tuple[str, ...]) -> str:
        if "secrets" in argv:
            return argv[argv.index("secrets") + 1]
        if "configs" in argv:
            return "log" if "get" in argv else "logs"
        if "me" in argv:
            return "me"
        raise AssertionError("Unexpected non-fixture command")

    def __call__(
        self, argv: tuple[str, ...], payload: bytes, environment: Any, timeout: float
    ) -> Any:
        operation = self.operation(argv)
        self.calls.append(Call(operation, argv, payload, dict(environment), timeout))
        self.counts[operation] += 1
        if self.hook is not None:
            override = self.hook(operation, self)
            if override is not None:
                return override
        failures = self.after_write_failures if self.counts["set"] else self.failures
        if operation in failures:
            return failures[operation]
        return self.dispatch(operation, argv, payload)

    def dispatch(self, operation: str, argv: tuple[str, ...], payload: bytes) -> Any:
        if operation == "me":
            return response(self.actor)
        if operation == "get":
            if ADMIN.SECRET not in self.values:
                return response({})
            value = self.values[ADMIN.SECRET]
            return response(
                {ADMIN.SECRET: {"raw": value, "computed": value, "note": OTHER}}
            )
        if operation == "logs":
            return response(self.logs[: ADMIN.HISTORY_LIMIT])
        if operation == "log":
            event_id = argv[argv.index("get") + 1]
            return response(next(log for log in self.logs if log["id"] == event_id))
        if operation != "set":
            raise AssertionError("Unexpected write operation")
        if self.commit_write:
            self.publish(ADMIN.SECRET, payload.decode("ascii"))
        return self.set_result


class FakeQuestions:
    def __init__(self) -> None:
        self.answers: dict[str, Any] = {
            "trust": "ACCEPT-TRUST",
            "scope": "SCOPES-VERIFIED",
            "window": "EXCLUSIVE-WINDOW",
            "lifecycle": "KEEP-KEYS",
            "auth": "LOGIN",
            "token": TOKEN,
            "workplace": "synthetic-workplace",
            "lifetime": "NEVER-EXPIRES",
            "presence": "REPLACE",
            "history": "HISTORY-AVAILABLE",
            "label": "B",
            "a": A,
            "b": B,
            "event": "event-002",
            "upload": "WRITE-ONE-KEY",
            "restore": "RESTORE-ONE-KEY",
        }
        self.seen: list[str] = []
        self.hook: Callable[[str], None] | None = None

    def __call__(self, prompt: str) -> str:
        name = prompt.split("]", 1)[0][1:]
        self.seen.append(name)
        print(prompt, end="", file=sys.stderr)
        if self.hook is not None:
            self.hook(name)
        answer = self.answers[name]
        if isinstance(answer, BaseException):
            raise answer
        return answer


class Fixture(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory(prefix="bedrock-key-admin-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.home = self.root / "synthetic-home"
        self.config_dir = self.home / ".doppler"
        self.config_dir.mkdir(parents=True, mode=0o700)
        self.config_dir.chmod(0o700)
        self.user_config = self.config_dir / ".doppler.yaml"
        self.user_config.write_text("scoped: {}\n")
        self.user_config.chmod(0o600)
        self.runtime_file = self.root / "public-runtime.json"
        self.runtime_file.write_text(json.dumps(RUNTIME))
        self.runtime = ADMIN.Runtime.parse(RUNTIME)
        self.fake = FakeDoppler()
        self.questions = FakeQuestions()
        self.environment = {
            "HOME": str(self.home),
            "PATH": "/synthetic/untrusted/bin",
            "DOPPLER_TOKEN": AMBIENT,
            "DOPPLER_API_HOST": "http://wrong.invalid",
            "DOPPLER_CONFIG_DIR": str(self.root / "runtime-sops-not-readable"),
            "DOPPLER_PROJECT": "wrong",
            "DOPPLER_CONFIG": "wrong",
            "DOPPLER_VERIFY_TLS": "false",
            "DOPPLER_DEBUG": "true",
            "ENCLAVE_TOKEN": AMBIENT,
            "AWS_BEARER_TOKEN_BEDROCK": C,
            "AWS_PROFILE": "synthetic-admin",
            "AWS_ACCESS_KEY_ID": C,
            "AWS_ENDPOINT_URL": "http://wrong.invalid",
            "ANTHROPIC_API_KEY": C,
            "GROK_AUTH_PROVIDER_TOKEN": C,
            "HTTP_PROXY": "http://wrong.invalid",
            "HTTPS_PROXY": "http://wrong.invalid",
            "SSL_CERT_FILE": "/wrong",
            "PYTHONPATH": "/synthetic/untrusted",
            "XDG_CONFIG_HOME": "/wrong",
        }
        self.console = ""

    def execute(self, action: str = "upload") -> dict[str, Any]:
        stdout, stderr = io.StringIO(), io.StringIO()
        with (
            mock.patch.object(
                ADMIN.subprocess,
                "Popen",
                side_effect=AssertionError("Unmocked process forbidden"),
            ),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            report = ADMIN.administer(
                self.runtime,
                action,
                runner=self.fake,
                prompt=self.questions,
                environ=self.environment,
            )
            data = report.output()
            print(json.dumps(data))
        self.console = stdout.getvalue() + stderr.getvalue()
        self.assertEqual(set(data), OUTPUT_KEYS)
        self.assertFalse(data["may_revoke_keys"])
        self.assertFalse(data["compare_and_swap"])
        self.assertFalse(data["client_migration_verified"])
        self.assert_sanitized(self.console)
        self.assert_calls()
        return data

    def assert_sanitized(self, text: str) -> None:
        for value in (A, B, C, OTHER, TOKEN, AMBIENT):
            self.assertNotIn(value, text)

    def assert_calls(self) -> None:
        for call in self.fake.calls:
            self.assert_call(call)

    def assert_call(self, call: Call) -> None:
        self.assertEqual(call.argv[0], BINARY)
        self.assert_sanitized("\n".join(call.argv))
        self.assertIn("--no-verify-tls=false", call.argv)
        self.assertIn("--no-timeout=false", call.argv)
        self.assertIn("--silent", call.argv)
        self.assertIn("--debug=false", call.argv)
        self.assertIn("--print-config=false", call.argv)
        self.assertIn("--no-check-version", call.argv)
        self.assertEqual(call.argv[call.argv.index("--attempts") + 1], "1")
        self.assertEqual(call.argv[call.argv.index("--api-host") + 1], ADMIN.API_HOST)
        self.assertEqual(call.argv[call.argv.index("--scope") + 1], "/")
        self.assertEqual(
            call.argv[call.argv.index("--config-dir") + 1], str(self.config_dir)
        )
        self.assertLessEqual(call.timeout, ADMIN.COMMAND_TIMEOUT)
        self.assertGreater(call.timeout, 0)
        self.assertFalse(
            any(value in (A, B, C, AMBIENT) for value in call.environment.values())
        )
        self.assertLessEqual(
            set(call.environment), {"HOME", "PATH", "LANG", "NO_COLOR", "DOPPLER_TOKEN"}
        )
        if call.operation == "me":
            self.assertNotIn("--project", call.argv)
            return
        self.assertEqual(call.argv[call.argv.index("--project") + 1], ADMIN.PROJECT)
        self.assertEqual(call.argv[call.argv.index("--config") + 1], ADMIN.CONFIG)
        if call.operation in ("get", "set"):
            index = call.argv.index("secrets")
            self.assertEqual(call.argv[index + 2], ADMIN.SECRET)
        if call.operation == "set":
            self.assertIn("--no-interactive", call.argv)
            self.assertNotIn("--json", call.argv)
        else:
            self.assertEqual(call.payload, b"")
            self.assertIn("--json", call.argv)

    def assert_unknown(self, data: dict[str, Any], reason: str) -> None:
        self.assertEqual(data["commit_state"], "unknown")
        self.assertEqual(data["reason"], reason)
        self.assertEqual(data["next_step"], "stop_keep_keys")
        self.assertFalse(data["metadata_verified"])

    def publish_b(self) -> str:
        event = self.fake.publish(ADMIN.SECRET, B)
        self.questions.answers["event"] = event
        return event


class PublicInterface(Fixture):
    def test_exact_public_runtime_contract(self) -> None:
        self.assertEqual(
            ADMIN.load_runtime(str(self.runtime_file)).doppler_binary, BINARY
        )
        cases = [
            {**RUNTIME, "token_file": "synthetic-forbidden"},
            {**RUNTIME, "project": "other"},
            {**RUNTIME, "doppler_config": "other"},
            {**RUNTIME, "api_host": "http://api.doppler.com"},
            {**RUNTIME, "api_host": "https://wrong.invalid"},
            {**RUNTIME, "doppler_binary": "/usr/bin/doppler"},
            {**RUNTIME, "doppler_binary": f"{BINARY}/../doppler"},
            {**RUNTIME, "doppler_binary": B},
            {**RUNTIME, "doppler_binary": None},
            {key: value for key, value in RUNTIME.items() if key != "api_host"},
        ]
        for value in cases:
            self.runtime_file.write_text(json.dumps(value))
            with self.assertRaises(ADMIN.Stop):
                ADMIN.load_runtime(str(self.runtime_file))

    def test_runtime_rejects_malformed_oversize_and_special_files(self) -> None:
        cases = [
            b"{",
            b"[]",
            b"\xff",
            b'{"a":1,"a":2}',
            b'{"a":NaN}',
            b" " * (ADMIN.MAX_RUNTIME + 1),
        ]
        for raw in cases:
            self.runtime_file.write_bytes(raw)
            with self.assertRaises(ADMIN.Stop):
                ADMIN.load_runtime(str(self.runtime_file))
        link = self.root / "runtime-link"
        link.symlink_to(self.runtime_file)
        fifo = self.root / "runtime-fifo"
        os.mkfifo(fifo)
        for path in (link, fifo, self.root):
            with self.assertRaises(ADMIN.Stop):
                ADMIN.load_runtime(str(path))

    def test_main_default_and_fixed_json_exit_codes(self) -> None:
        report = ADMIN.Report(
            action="upload",
            commit_state="confirmed_committed",
            reason="verified_event_and_value",
        )
        with mock.patch.object(ADMIN, "administer", return_value=report) as administer:
            output = io.StringIO()
            with redirect_stdout(output):
                code = ADMIN.main([str(self.runtime_file)])
        self.assertEqual(code, 0)
        self.assertEqual(administer.call_args.args[1], "upload")
        self.assertEqual(set(json.loads(output.getvalue())), OUTPUT_KEYS)
        self.assertEqual(len(output.getvalue().splitlines()), 1)

    def test_main_rejects_extra_or_secret_arguments_without_echo(self) -> None:
        for arguments in (
            [],
            [str(self.runtime_file), B],
            [str(self.runtime_file), "upload", B],
        ):
            output = io.StringIO()
            with redirect_stdout(output):
                code = ADMIN.main(arguments)
            self.assertEqual(code, 2)
            self.assert_sanitized(output.getvalue())
            self.assertEqual(
                json.loads(output.getvalue())["reason"], "invalid_arguments"
            )

    def test_hidden_prompt_never_falls_back_to_echo(self) -> None:
        def warn(_prompt: str, **_kwargs: Any) -> str:
            warnings.warn(
                "synthetic unavailable tty", ADMIN.getpass.GetPassWarning, stacklevel=2
            )
            raise AssertionError("Echo fallback must not execute")

        with (
            mock.patch.object(ADMIN.getpass, "getpass", side_effect=warn),
            self.assertRaises(ADMIN.Stop) as error,
        ):
            ADMIN.hidden_input("fixed hidden prompt")
        self.assertEqual(error.exception.reason, "input_unavailable")

    def test_candidate_validation_is_opaque_not_aws_encoding(self) -> None:
        invalid = (
            "",
            " ",
            "new line\n",
            "x\r",
            "x\t",
            "x\0",
            "x\x7f",
            "中文",
            '{"access_token":"SYNTHETIC_ONLY","expires_in":86400}',
            '["SYNTHETIC_ONLY"]',
            '"SYNTHETIC_ONLY"',
            "x" * (ADMIN.MAX_SECRET + 1),
        )
        for value in invalid:
            self.questions.answers["b"] = value
            result = self.execute()
            self.assertEqual(result["commit_state"], "confirmed_not_submitted")
            self.assertEqual(self.fake.counts["set"], 0)
        self.assertEqual(ADMIN.opaque("opaque/+=:._-"), b"opaque/+=:._-")

    def test_secret_holding_objects_have_redacted_repr(self) -> None:
        values = [
            ADMIN.CommandResult(1, B.encode(), A.encode()),
            ADMIN.Inputs(a=A.encode(), b=B.encode()),
            ADMIN.Change(B, A),
        ]
        self.assert_sanitized(" ".join(map(repr, values)))


class HumanGates(Fixture):
    def test_each_upload_approval_requires_exact_nondefault_answer(self) -> None:
        names = (
            "trust",
            "scope",
            "window",
            "lifecycle",
            "lifetime",
            "history",
            "upload",
        )
        for name in names:
            self.questions = FakeQuestions()
            self.questions.answers[name] = ""
            result = self.execute()
            self.assertEqual(result["reason"], "user_declined")
            self.assertEqual(result["commit_state"], "confirmed_not_submitted")
            self.assertEqual(self.fake.counts["set"], 0)
        self.questions.answers["trust"] = "yes"
        self.assertEqual(self.execute()["reason"], "user_declined")

    def test_history_decline_blocks_restore(self) -> None:
        self.publish_b()
        self.questions.answers["history"] = "no"
        result = self.execute("restore")
        self.assertEqual(result["commit_state"], "confirmed_not_submitted")
        self.assertEqual(self.fake.counts["set"], 0)

    def test_no_implicit_auth_or_presence_or_candidate_choice(self) -> None:
        for question in ("auth", "presence"):
            self.questions = FakeQuestions()
            self.questions.answers[question] = ""
            self.assertEqual(self.execute()["reason"], "user_declined")
        self.questions = FakeQuestions()
        self.questions.answers["label"] = ""
        self.assert_unknown(self.execute("confirm"), "user_declined")
        self.assertEqual(self.fake.counts["set"], 0)

    def test_login_ignores_all_ambient_tokens_and_overrides(self) -> None:
        result = self.execute()
        self.assertEqual(result["commit_state"], "confirmed_committed")
        for call in self.fake.calls:
            self.assertNotIn("DOPPLER_TOKEN", call.environment)
            self.assertIn("--no-read-env", call.argv)
            self.assertEqual(call.environment["PATH"], "/usr/bin:/bin")
        self.assertNotIn("token", self.questions.seen)

    def test_hidden_own_user_token_only_goes_to_child_auth_environment(self) -> None:
        self.questions.answers["auth"] = "TOKEN"
        result = self.execute()
        self.assertEqual(result["commit_state"], "confirmed_committed")
        for call in self.fake.calls:
            self.assertEqual(call.environment["DOPPLER_TOKEN"], TOKEN)
            self.assertIn("--no-read-env=false", call.argv)
        self.assertIn("token", self.questions.seen)

    def test_no_direct_credential_or_runtime_token_file_reads(self) -> None:
        with (
            mock.patch(
                "builtins.open",
                side_effect=AssertionError("Credential reads forbidden"),
            ),
            mock.patch.object(
                ADMIN.os,
                "open",
                side_effect=AssertionError("Credential reads forbidden"),
            ),
        ):
            result = self.execute()
        self.assertEqual(result["commit_state"], "confirmed_committed")

    def test_user_config_must_exist_and_remain_private(self) -> None:
        self.user_config.chmod(0o644)
        self.assertEqual(self.execute()["reason"], "user_config_permissions")
        self.user_config.chmod(0o600)
        self.config_dir.chmod(0o755)
        self.assertEqual(self.execute()["reason"], "user_config_permissions")
        self.config_dir.chmod(0o700)
        self.user_config.unlink()
        self.assertEqual(self.execute()["reason"], "user_config_unavailable")
        self.assertEqual(self.fake.calls, [])

    def test_user_config_symlinks_and_hardlinks_are_rejected(self) -> None:
        existing = self.root / "synthetic-auth"
        self.user_config.rename(existing)
        self.user_config.symlink_to(existing)
        self.assertEqual(self.execute()["reason"], "user_config_permissions")
        self.user_config.unlink()
        self.user_config.hardlink_to(existing)
        self.assertEqual(self.execute()["reason"], "user_config_permissions")
        self.assertEqual(self.fake.calls, [])

    def test_other_owner_is_rejected_without_reading_config(self) -> None:
        with mock.patch.object(ADMIN.os, "getuid", return_value=os.getuid() + 1):
            result = self.execute()
        self.assertEqual(result["reason"], "user_config_permissions")
        self.assertEqual(self.fake.calls, [])

    def test_workplace_mismatch_is_a_no_write_stop(self) -> None:
        self.fake.actor["workplace"]["slug"] = "different-workplace"
        result = self.execute()
        self.assertEqual(result["reason"], "workplace_mismatch")
        self.assertFalse(result["workplace_matches"])
        self.assertEqual(result["commit_state"], "confirmed_not_submitted")
        self.assertEqual([call.operation for call in self.fake.calls], ["me"])

    def test_interrupted_hidden_input_is_not_a_submission(self) -> None:
        self.questions.answers["b"] = KeyboardInterrupt(B)
        result = self.execute()
        self.assertEqual(result["reason"], "cancelled")
        self.assertEqual(result["commit_state"], "confirmed_not_submitted")
        self.assertEqual(self.fake.calls, [])


class Upload(Fixture):
    def test_single_key_write_and_verified_readback(self) -> None:
        result = self.execute()
        self.assertEqual(result["commit_state"], "confirmed_committed")
        self.assertEqual(result["state_scope"], "this_write_attempt")
        self.assertTrue(result["matches_B"])
        self.assertIsNone(result["matches_A"])
        self.assertTrue(result["metadata_verified"])
        self.assertEqual(result["event_id"], "event-002")
        self.assertEqual(self.fake.counts["set"], 1)
        self.assertEqual(self.fake.values["UNRELATED_SECRET"], OTHER)
        self.assertEqual(
            next(call.payload for call in self.fake.calls if call.operation == "set"),
            B.encode(),
        )

    def test_initial_absent_target_is_supported(self) -> None:
        del self.fake.values[ADMIN.SECRET]
        self.fake.logs.clear()
        self.questions.answers["presence"] = "ABSENT"
        result = self.execute()
        self.assertEqual(result["commit_state"], "confirmed_committed")
        self.assertFalse(result["history_user_confirmed"])
        self.assertEqual(self.fake.logs[0]["diff"][0]["removed"], "")

    def test_presence_mismatch_and_noop_do_not_write(self) -> None:
        self.questions.answers["presence"] = "ABSENT"
        self.assertEqual(self.execute()["reason"], "presence_mismatch")
        self.questions.answers["presence"] = "REPLACE"
        del self.fake.values[ADMIN.SECRET]
        self.assertEqual(self.execute()["reason"], "presence_mismatch")
        self.fake.values[ADMIN.SECRET] = B
        result = self.execute()
        self.assertEqual(result["reason"], "already_current")
        self.assertTrue(result["matches_B"])
        self.assertEqual(result["commit_state"], "confirmed_not_submitted")
        self.assertEqual(self.fake.counts["set"], 0)

    def test_prewrite_value_drift_stops(self) -> None:
        def drift(name: str) -> None:
            if name == "upload":
                self.fake.publish(ADMIN.SECRET, C)

        self.questions.hook = drift
        result = self.execute()
        self.assertEqual(result["reason"], "concurrent_change")
        self.assertEqual(result["commit_state"], "confirmed_not_submitted")
        self.assertEqual(self.fake.counts["set"], 0)

    def test_prewrite_aba_event_drift_stops_even_if_value_matches(self) -> None:
        def drift(name: str) -> None:
            if name == "upload":
                self.fake.publish(ADMIN.SECRET, C)
                self.fake.publish(ADMIN.SECRET, A)

        self.questions.hook = drift
        result = self.execute()
        self.assertEqual(result["reason"], "concurrent_change")
        self.assertEqual(self.fake.counts["set"], 0)

    def test_postcommit_nonzero_resolves_only_with_value_and_event_proof(self) -> None:
        self.fake.set_result = ADMIN.CommandResult(
            1, B.encode(), f"Unable to parse API response: {B}".encode()
        )
        result = self.execute()
        self.assertEqual(result["write_result"], "invalid_response")
        self.assertEqual(result["commit_state"], "confirmed_committed")
        self.assertTrue(result["matches_B"])
        self.assertTrue(result["metadata_verified"])
        self.assertEqual(self.fake.counts["set"], 1)

    def test_unexpected_silent_output_needs_independent_proof(self) -> None:
        self.fake.set_result = ADMIN.CommandResult(0, B.encode(), A.encode())
        result = self.execute()
        self.assertEqual(result["write_result"], "invalid_response")
        self.assertEqual(result["commit_state"], "confirmed_committed")

    def test_postcommit_error_and_unreadable_readback_remain_unknown(self) -> None:
        self.fake.set_result = ADMIN.CommandResult(1, B.encode(), B.encode())
        self.fake.after_write_failures["get"] = ADMIN.CommandResult(
            1, B.encode(), f"Forbidden {B}".encode()
        )
        result = self.execute()
        self.assert_unknown(result, "permission_or_authentication")
        self.assertEqual(self.fake.values[ADMIN.SECRET], B)
        self.assertIsNone(result["matches_B"])
        self.assertEqual(self.fake.counts["set"], 1)

    def test_postcommit_timeout_stops_without_read_or_retry(self) -> None:
        self.fake.set_result = ADMIN.CommandResult(failure="timeout")
        result = self.execute()
        self.assert_unknown(result, "timeout")
        self.assertEqual(self.fake.values[ADMIN.SECRET], B)
        self.assertIsNone(result["matches_B"])
        self.assertEqual(self.fake.calls[-1].operation, "set")
        self.assertEqual(self.fake.counts["set"], 1)
        self.questions.answers["event"] = self.fake.logs[0]["id"]
        self.assertEqual(self.execute("confirm")["commit_state"], "confirmed_committed")
        self.assertEqual(self.fake.counts["set"], 1)

    def test_postcommit_interruption_preserves_b_and_stops(self) -> None:
        def interrupt(operation: str, fake: FakeDoppler) -> None:
            if operation == "set":
                fake.publish(ADMIN.SECRET, B)
                raise KeyboardInterrupt(B)

        self.fake.hook = interrupt
        result = self.execute()
        self.assert_unknown(result, "cancelled")
        self.assertEqual(self.fake.values[ADMIN.SECRET], B)
        self.assertEqual(self.fake.calls[-1].operation, "set")

    def test_postcommit_unexpected_exception_is_redacted_and_unknown(self) -> None:
        def fail(operation: str, fake: FakeDoppler) -> None:
            if operation == "set":
                fake.publish(ADMIN.SECRET, B)
                raise RuntimeError(B)

        self.fake.hook = fail
        result = self.execute()
        self.assert_unknown(result, "internal_error")
        self.assertEqual(self.fake.values[ADMIN.SECRET], B)

    def test_late_interruption_cannot_leave_a_success_verdict(self) -> None:
        def finish_then_interrupt(
            _doppler: Any, _questions: Any, _inputs: Any, report: Any
        ) -> None:
            report.write_attempted = True
            report.commit_state = "confirmed_committed"
            report.event = ADMIN.event_metadata(self.fake.logs[0])
            raise KeyboardInterrupt(B)

        with mock.patch.object(ADMIN, "perform", side_effect=finish_then_interrupt):
            result = self.execute()
        self.assert_unknown(result, "cancelled")

    def test_third_value_after_write_is_unknown_not_automatic_restore(self) -> None:
        def drift(operation: str, fake: FakeDoppler) -> None:
            if operation == "get" and fake.counts["set"]:
                fake.publish(ADMIN.SECRET, C)

        self.fake.hook = drift
        result = self.execute()
        self.assert_unknown(result, "value_mismatch")
        self.assertFalse(result["matches_B"])
        self.assertEqual(self.fake.values[ADMIN.SECRET], C)
        self.assertEqual(self.fake.counts["set"], 1)

    def test_same_b_with_later_edits_is_still_unknown(self) -> None:
        def drift(operation: str, fake: FakeDoppler) -> None:
            if operation == "get" and fake.counts["set"]:
                fake.publish(ADMIN.SECRET, C)
                fake.publish(ADMIN.SECRET, B)

        self.fake.hook = drift
        result = self.execute()
        self.assert_unknown(result, "later_target_edit")
        self.assertTrue(result["matches_B"])
        self.assertEqual(self.fake.counts["set"], 1)

    def test_unrelated_edits_are_preserved(self) -> None:
        def unrelated(operation: str, fake: FakeDoppler) -> None:
            if operation == "get" and fake.counts["set"]:
                fake.publish("UNRELATED_SECRET", "synthetic-new-unrelated")

        self.fake.hook = unrelated
        result = self.execute()
        self.assertEqual(result["commit_state"], "confirmed_committed")
        self.assertEqual(
            self.fake.values["UNRELATED_SECRET"], "synthetic-new-unrelated"
        )
        self.assertEqual(self.fake.counts["set"], 1)

    def test_after_snapshot_drift_is_unknown(self) -> None:
        def drift(operation: str, fake: FakeDoppler) -> None:
            if operation == "logs" and fake.counts["logs"] == 4:
                fake.publish(ADMIN.SECRET, C)

        self.fake.hook = drift
        self.assert_unknown(self.execute(), "concurrent_change")

    def test_local_start_failure_is_not_submitted(self) -> None:
        self.fake.commit_write = False
        self.fake.set_result = ADMIN.CommandResult(
            started=False, failure="local_permission_denied"
        )
        result = self.execute()
        self.assertEqual(result["commit_state"], "confirmed_not_submitted")
        self.assertEqual(result["reason"], "local_permission_denied")
        self.assertEqual(self.fake.values[ADMIN.SECRET], A)

    def test_remote_permission_text_never_proves_noncommit(self) -> None:
        self.fake.commit_write = False
        self.fake.set_result = ADMIN.CommandResult(1, b"", f"Forbidden {B}".encode())
        result = self.execute()
        self.assert_unknown(result, "value_mismatch")
        self.assertEqual(result["write_result"], "permission_or_authentication")
        self.assertEqual(self.fake.counts["set"], 1)

    def test_cleanup_failure_never_runs_dependent_checks(self) -> None:
        self.fake.set_result = ADMIN.CommandResult(failure="cleanup_failed")
        result = self.execute()
        self.assert_unknown(result, "cleanup_failed")
        self.assertEqual(self.fake.calls[-1].operation, "set")


class ReadbackAndMetadata(Fixture):
    def test_confirm_is_read_only_with_bool_and_projected_event(self) -> None:
        event = self.publish_b()
        result = self.execute("confirm")
        self.assertEqual(result["commit_state"], "confirmed_committed")
        self.assertEqual(result["state_scope"], "referenced_event")
        self.assertTrue(result["matches_B"])
        self.assertEqual(result["event_id"], event)
        self.assertEqual(self.fake.counts["set"], 0)

    def test_confirm_can_check_a_without_exposing_it(self) -> None:
        self.questions.answers["label"] = "A"
        self.questions.answers["event"] = self.fake.logs[0]["id"]
        result = self.execute("confirm")
        self.assertEqual(result["commit_state"], "confirmed_committed")
        self.assertTrue(result["matches_A"])
        self.assertIsNone(result["matches_B"])
        self.assertEqual(self.fake.counts["set"], 0)

    def test_confirm_wrong_candidate_or_missing_target_is_unknown(self) -> None:
        self.publish_b()
        self.fake.values[ADMIN.SECRET] = C
        result = self.execute("confirm")
        self.assert_unknown(result, "value_mismatch")
        self.assertFalse(result["matches_B"])
        del self.fake.values[ADMIN.SECRET]
        self.assert_unknown(self.execute("confirm"), "value_mismatch")

    def test_rejects_extra_secret_and_empty_whitespace_restricted_or_computed_difference(
        self,
    ) -> None:
        self.publish_b()
        fixtures = [
            {ADMIN.SECRET: {"raw": B, "computed": B}, "OTHER": {"raw": OTHER}},
            {ADMIN.SECRET: {"raw": "", "computed": ""}},
            {ADMIN.SECRET: {"raw": " ", "computed": " "}},
            {ADMIN.SECRET: {"raw": B + "\n", "computed": B + "\n"}},
            {ADMIN.SECRET: {"raw": None, "computed": None}},
            {ADMIN.SECRET: {"raw": B, "computed": C}},
            {ADMIN.SECRET: {"raw": "${OTHER}", "computed": B}},
        ]
        for value in fixtures:
            self.fake.failures["get"] = response(value)
            result = self.execute("confirm")
            self.assertEqual(result["commit_state"], "unknown")
            self.assertIsNone(result["matches_B"])
            self.assertEqual(self.fake.counts["set"], 0)

    def test_malformed_and_duplicate_cli_json_is_unknown(self) -> None:
        self.publish_b()
        for raw in (b"{", b"[]", b"\xff", b'{"a":1,"a":2}', b'{"a":NaN}'):
            self.fake.failures["get"] = ADMIN.CommandResult(0, raw)
            self.assert_unknown(self.execute("confirm"), "invalid_response")

    def test_later_target_edits_cannot_be_hidden_by_matching_value(self) -> None:
        self.publish_b()
        self.fake.publish(ADMIN.SECRET, C)
        self.fake.publish(ADMIN.SECRET, B)
        result = self.execute("confirm")
        self.assert_unknown(result, "later_target_edit")
        self.assertTrue(result["matches_B"])
        self.assertEqual(self.fake.counts["set"], 0)

    def test_unrelated_newer_events_are_allowed_but_never_exposed(self) -> None:
        self.publish_b()
        self.fake.publish("UNRELATED_SECRET", OTHER)
        result = self.execute("confirm")
        self.assertEqual(result["commit_state"], "confirmed_committed")
        self.assertEqual(result["event_id"], "event-002")

    def test_event_must_be_single_key_with_matching_added_value(self) -> None:
        self.publish_b()
        self.fake.logs[0]["diff"].append(
            {"name": "OTHER", "added": OTHER, "removed": OTHER}
        )
        self.assert_unknown(self.execute("confirm"), "event_not_single_key")
        self.fake.logs[0]["diff"] = [{"name": ADMIN.SECRET, "added": C, "removed": A}]
        self.assert_unknown(self.execute("confirm"), "event_value_mismatch")

    def test_history_permission_and_missing_diff_fail_closed(self) -> None:
        self.publish_b()
        self.fake.failures["log"] = ADMIN.CommandResult(
            1, b"", f"Permission denied {OTHER}".encode()
        )
        self.assert_unknown(self.execute("confirm"), "permission_or_authentication")
        self.fake.failures.clear()
        self.fake.logs[0]["diff"] = None
        self.assert_unknown(self.execute("confirm"), "history_unavailable")

    def test_history_outside_bounded_window_is_unverified(self) -> None:
        self.publish_b()
        for index in range(ADMIN.HISTORY_LIMIT):
            self.fake.publish("UNRELATED_SECRET", f"synthetic-{index}")
        result = self.execute("confirm")
        self.assert_unknown(result, "history_unavailable")
        self.assertTrue(result["matches_B"])
        self.assertEqual(self.fake.counts["set"], 0)

    def test_wrong_scope_malformed_timestamp_and_duplicate_events_rejected(
        self,
    ) -> None:
        self.publish_b()
        original = copy.deepcopy(self.fake.logs)
        for key, value in (
            ("project", "wrong"),
            ("config", "wrong"),
            ("created_at", B),
            ("id", "bad\nidentifier"),
        ):
            self.fake.logs = copy.deepcopy(original)
            self.fake.logs[0][key] = value
            self.assert_unknown(self.execute("confirm"), "invalid_response")
        self.fake.logs = [original[0], original[0]]
        self.assert_unknown(self.execute("confirm"), "invalid_response")
        self.fake.logs = list(reversed(original))
        self.assert_unknown(self.execute("confirm"), "invalid_response")

    def test_secret_cannot_be_smuggled_into_event_argv_or_metadata(self) -> None:
        self.publish_b()
        self.questions.answers["event"] = B
        self.assert_unknown(self.execute("confirm"), "invalid_response")
        self.assertEqual(self.fake.calls, [])
        self.questions.answers["event"] = "event-002"
        self.fake.logs[0]["id"] = B
        self.assert_unknown(self.execute("confirm"), "invalid_response")
        self.assertEqual(self.fake.counts["log"], 0)

    def test_actor_type_is_not_guessed_from_an_undocumented_enum(self) -> None:
        self.fake.actor["type"] = "Synthetic CLI Token"
        self.assertEqual(self.execute()["commit_state"], "confirmed_committed")

    def test_identity_change_stops_before_write(self) -> None:
        def change_identity(operation: str, fake: FakeDoppler) -> None:
            if operation == "me" and fake.counts["me"] == 2:
                fake.actor["slug"] = "synthetic-other-user"

        self.fake.hook = change_identity
        result = self.execute()
        self.assertEqual(result["reason"], "identity_changed")
        self.assertEqual(result["commit_state"], "confirmed_not_submitted")
        self.assertEqual(self.fake.counts["set"], 0)

    def test_postwrite_identity_change_is_unknown(self) -> None:
        def change_identity(operation: str, fake: FakeDoppler) -> None:
            if operation == "me" and fake.counts["me"] == 3:
                fake.actor["workplace"]["slug"] = "wrong-workplace"

        self.fake.hook = change_identity
        self.assert_unknown(self.execute(), "workplace_mismatch")

    def test_exhausted_command_budget_never_starts_runner(self) -> None:
        runner = mock.Mock()
        doppler = ADMIN.Doppler(
            self.runtime, {"HOME": str(self.home)}, runner, "synthetic-workplace"
        )
        doppler.budget = 0
        result = doppler.invoke(("secrets", "set", ADMIN.SECRET), B.encode())
        self.assertFalse(result.started)
        self.assertEqual(result.failure, "timeout")
        runner.assert_not_called()


class Restore(Fixture):
    def test_restore_requires_current_b_event_and_matching_prior_a(self) -> None:
        self.publish_b()
        result = self.execute("restore")
        self.assertEqual(result["commit_state"], "confirmed_committed")
        self.assertTrue(result["expected_current_B_verified"])
        self.assertTrue(result["matches_A"])
        self.assertFalse(result["matches_B"])
        self.assertEqual(self.fake.values[ADMIN.SECRET], A)
        self.assertEqual(self.fake.values["UNRELATED_SECRET"], OTHER)
        self.assertEqual(self.fake.counts["set"], 1)
        self.assertEqual(
            next(call.payload for call in self.fake.calls if call.operation == "set"),
            A.encode(),
        )
        self.assertEqual(result["event_id"], "event-003")

    def test_restore_wrong_current_b_does_not_write(self) -> None:
        self.publish_b()
        self.fake.values[ADMIN.SECRET] = C
        result = self.execute("restore")
        self.assertEqual(result["reason"], "value_mismatch")
        self.assertEqual(result["commit_state"], "confirmed_not_submitted")
        self.assertEqual(self.fake.counts["set"], 0)

    def test_restore_wrong_prior_a_does_not_write(self) -> None:
        self.publish_b()
        self.questions.answers["a"] = C
        result = self.execute("restore")
        self.assertEqual(result["reason"], "event_value_mismatch")
        self.assertEqual(self.fake.counts["set"], 0)
        self.assertEqual(self.fake.values[ADMIN.SECRET], B)

    def test_restore_unreadable_history_and_later_edits_do_not_write(self) -> None:
        self.publish_b()
        self.fake.logs[0]["diff"] = []
        self.assertEqual(self.execute("restore")["reason"], "history_unavailable")
        self.fake = FakeDoppler()
        self.publish_b()
        self.fake.publish(ADMIN.SECRET, B)
        self.assertEqual(self.execute("restore")["reason"], "later_target_edit")
        self.assertEqual(self.fake.counts["set"], 0)

    def test_restore_final_approval_is_mandatory(self) -> None:
        self.publish_b()
        self.questions.answers["restore"] = ""
        result = self.execute("restore")
        self.assertEqual(result["reason"], "user_declined")
        self.assertTrue(result["expected_current_B_verified"])
        self.assertEqual(self.fake.counts["set"], 0)

    def test_restore_rejects_identical_a_and_b(self) -> None:
        self.questions.answers["a"] = B
        result = self.execute("restore")
        self.assertEqual(result["reason"], "invalid_input")
        self.assertEqual(self.fake.calls, [])

    def test_restore_preserves_unrelated_later_changes(self) -> None:
        self.publish_b()
        self.fake.publish("UNRELATED_SECRET", "synthetic-updated-unrelated")
        result = self.execute("restore")
        self.assertEqual(result["commit_state"], "confirmed_committed")
        self.assertEqual(
            self.fake.values["UNRELATED_SECRET"], "synthetic-updated-unrelated"
        )
        self.assertEqual(self.fake.counts["set"], 1)

    def test_restore_postcommit_failure_stays_unknown_without_proof(self) -> None:
        self.publish_b()
        self.fake.set_result = ADMIN.CommandResult(
            1, A.encode(), f"Unable to parse API response {A}".encode()
        )
        self.fake.after_write_failures["logs"] = ADMIN.CommandResult(
            1, OTHER.encode(), b"Forbidden"
        )
        result = self.execute("restore")
        self.assert_unknown(result, "permission_or_authentication")
        self.assertTrue(result["matches_A"])
        self.assertFalse(result["matches_B"])
        self.assertEqual(self.fake.values[ADMIN.SECRET], A)
        self.assertEqual(self.fake.counts["set"], 1)


class ProcessBoundary(Fixture):
    def run_fake(self, code: str, payload: bytes = b"", timeout: float = 2.0) -> Any:
        environment = {"HOME": str(self.home), "PATH": "/usr/bin:/bin", "LANG": "C"}
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            result = ADMIN.run_command(
                (sys.executable, "-I", "-c", code), payload, environment, timeout
            )
        self.assert_sanitized(stdout.getvalue() + stderr.getvalue())
        return result

    def test_stdin_only_and_both_output_streams_are_captured(self) -> None:
        code = "import sys; data=sys.stdin.buffer.read(); sys.stdout.buffer.write(data); sys.stderr.buffer.write(data); sys.exit(1)"
        result = self.run_fake(code, B.encode())
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, B.encode())
        self.assertEqual(result.stderr, B.encode())
        self.assert_sanitized(repr(result))

    def test_child_receives_no_ambient_provider_secrets(self) -> None:
        code = "import json,os; print(json.dumps({name: name in os.environ for name in ('AWS_BEARER_TOKEN_BEDROCK','DOPPLER_TOKEN','AWS_PROFILE','HTTPS_PROXY','PYTHONPATH')}))"
        with mock.patch.dict(os.environ, self.environment, clear=True):
            result = self.run_fake(code)
        self.assertEqual(result.returncode, 0)
        self.assertFalse(any(json.loads(result.stdout).values()))

    def test_fake_binary_contract_never_puts_candidate_in_argv(self) -> None:
        binary = self.root / "fake-doppler"
        binary.write_text(
            f"#!{sys.executable}\nimport json,sys\ndata=sys.stdin.buffer.read()\nassert data and all(data not in arg.encode() for arg in sys.argv)\nassert sys.argv[1:]==['secrets','set','AWS_BEARER_TOKEN_BEDROCK','--silent']\n"
        )
        binary.chmod(0o700)
        result = ADMIN.run_command(
            (str(binary), "secrets", "set", ADMIN.SECRET, "--silent"),
            B.encode(),
            {"HOME": str(self.home), "PATH": "/usr/bin:/bin"},
            2.0,
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(result.stderr, b"")

    def test_start_failure_classification_contains_no_exception_details(self) -> None:
        errors = [
            (FileNotFoundError(B), "executable_unavailable"),
            (PermissionError(B), "local_permission_denied"),
        ]
        for exception, expected in errors:
            with mock.patch.object(ADMIN.subprocess, "Popen", side_effect=exception):
                result = self.run_fake("raise AssertionError")
            self.assertFalse(result.started)
            self.assertEqual(result.failure, expected)
            self.assert_sanitized(repr(result))

    def test_output_limit_is_bounded_and_terminates_writer(self) -> None:
        started = time.monotonic()
        result = self.run_fake(
            "import os; data=b'x'*65536\nwhile True: os.write(1,data)"
        )
        self.assertEqual(result.failure, "output_limit")
        self.assertLess(time.monotonic() - started, 3)
        self.assertEqual(result.stdout, b"")

    def test_timeout_is_bounded(self) -> None:
        started = time.monotonic()
        result = self.run_fake("import time; time.sleep(30)", timeout=0.1)
        self.assertEqual(result.failure, "timeout")
        self.assertLess(time.monotonic() - started, 2)

    def test_interruption_signals_cancel_own_process_group(self) -> None:
        for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            previous = signal.getsignal(signum)
            result = self.run_fake(
                f"import os,signal,time; os.kill(os.getppid(), {int(signum)}); time.sleep(30)"
            )
            self.assertEqual(result.failure, "cancelled")
            self.assertEqual(signal.getsignal(signum), previous)

    def test_controlled_keyboard_interrupt_closes_pipes_and_kills_child(self) -> None:
        with mock.patch.object(ADMIN, "capture", side_effect=KeyboardInterrupt(B)):
            result = self.run_fake("import time; time.sleep(30)")
        self.assertEqual(result.failure, "cancelled")
        self.assert_sanitized(repr(result))

    def test_signal_during_process_creation_is_deferred_until_cleanup(self) -> None:
        original = ADMIN.subprocess.Popen

        def create_then_interrupt(*args: Any, **kwargs: Any) -> Any:
            process = original(*args, **kwargs)
            os.kill(os.getpid(), signal.SIGTERM)
            return process

        with mock.patch.object(
            ADMIN.subprocess, "Popen", side_effect=create_then_interrupt
        ):
            result = self.run_fake("import time; time.sleep(30)")
        self.assertEqual(result.failure, "cancelled")

    def test_pipe_holding_grandchild_is_killed_after_leader_exit(self) -> None:
        marker = self.root / "grandchild-survived"
        code = f"""import os,signal,time
pid=os.fork()
if pid:
    os._exit(0)
signal.signal(signal.SIGTERM,signal.SIG_IGN)
time.sleep(0.8)
with open({str(marker)!r},'w') as stream:
    stream.write('synthetic-survivor')
"""
        result = self.run_fake(code, timeout=0.2)
        self.assertEqual(result.failure, "timeout")
        time.sleep(0.9)
        self.assertFalse(marker.exists())

    def test_successful_leader_cannot_leave_background_grandchild(self) -> None:
        marker = self.root / "background-survived"
        code = f"""import os,signal,time
pid=os.fork()
if pid:
    os._exit(0)
os.close(0); os.close(1); os.close(2)
signal.signal(signal.SIGTERM,signal.SIG_IGN)
time.sleep(0.8)
with open({str(marker)!r},'w') as stream:
    stream.write('synthetic-survivor')
"""
        result = self.run_fake(code)
        self.assertEqual(result.returncode, 0)
        time.sleep(0.9)
        self.assertFalse(marker.exists())

    def test_cleanup_failure_is_explicit_even_after_zero_exit(self) -> None:
        with mock.patch.object(ADMIN, "signal_group", return_value=False):
            result = self.run_fake("pass")
        self.assertEqual(result.failure, "cleanup_failed")


if __name__ == "__main__":
    unittest.main(verbosity=2)
