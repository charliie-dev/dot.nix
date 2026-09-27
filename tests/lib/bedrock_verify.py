"""Pure message-stream verification tests; never starts a model client."""

import copy
import io
import json
import os
import runpy
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from typing import Any
from unittest import mock

SOURCE = Path(__file__).resolve().parents[2] / "conf.d/bedrock-api-key/verify.py"
VERIFY = runpy.run_path(str(SOURCE))
PROFILE = "global.anthropic.claude-opus-5-5"
NONCE = "synthetic-nonce"


class VerifyContracts(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR", "/tmp"))
        self.addCleanup(temporary.cleanup)
        self.fixture = (Path(temporary.name) / "fixture.txt").resolve()
        self.events: list[dict[str, Any]] = [
            {
                "type": "assistant",
                "message": {
                    "model": PROFILE,
                    "content": [
                        {
                            "type": "tool_use",
                            "id": "call-1",
                            "name": "Read",
                            "input": {"file_path": str(self.fixture)},
                        }
                    ],
                },
            },
            {
                "type": "user",
                "message": {
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": "call-1",
                            "content": NONCE,
                            "is_error": False,
                        }
                    ]
                },
            },
            {
                "type": "assistant",
                "message": {
                    "model": PROFILE,
                    "content": [{"type": "text", "text": NONCE}],
                },
            },
            {
                "type": "result",
                "subtype": "success",
                "is_error": False,
                "result": NONCE,
                "modelUsage": {PROFILE: {"contextWindow": 1000000}},
            },
        ]

    def verify(self, events):
        raw = b"\n".join(json.dumps(event).encode() for event in events)
        return VERIFY["inspect_stream"](raw, self.fixture, NONCE, "Read", PROFILE)

    def test_actual_round_trip_is_required(self):
        result = self.verify(self.events)
        self.assertTrue(result["tool_round_trip"])
        self.assertTrue(result["response_model_verified"])
        self.assertFalse(result["wire_model_id_verified"])
        self.assertEqual(result["reported_context_windows"], [1000000])

    def grok_events(self, first="bedrock-grok", last="bedrock-grok"):
        events = copy.deepcopy(self.events)
        events[0]["message"]["model"] = first
        events[0]["message"]["content"][0]["name"] = "read_file"
        events[2]["message"]["model"] = last
        events[-1]["modelUsage"] = {"bedrock-grok": {"contextWindow": 500000}}
        return events

    def verify_grok(self, events, alias="bedrock-grok"):
        raw = b"\n".join(json.dumps(event).encode() for event in events)
        return VERIFY["inspect_stream"](
            raw,
            self.fixture,
            NONCE,
            "read_file",
            "global.xai.grok-4.6",
            client_alias=alias,
        )

    def test_grok_catalog_key_only_verifies_the_client_label(self):
        result = self.verify_grok(self.grok_events())
        self.assertTrue(result["tool_round_trip"])
        self.assertTrue(result["client_model_label_verified"])
        self.assertFalse(result["response_model_verified"])
        self.assertFalse(result["wire_model_id_verified"])
        self.assertEqual(result["model_identity_source"], "catalog-key")
        result = self.verify_grok(self.grok_events("bedrock-grok[1m]", "bedrock-grok"))
        self.assertTrue(result["client_model_label_verified"])
        self.assertFalse(result["response_model_verified"])
        self.assertEqual(result["model_identity_source"], "catalog-key")

    def test_grok_id_and_mixed_identity_evidence_stay_distinct(self):
        profile = "global.xai.grok-4.6"
        result = self.verify_grok(self.grok_events(profile, "grok-4.6"))
        self.assertTrue(result["response_model_verified"])
        self.assertEqual(result["model_identity_source"], "model-id")
        result = self.verify_grok(self.grok_events("bedrock-grok", profile))
        self.assertFalse(result["response_model_verified"])
        self.assertEqual(result["model_identity_source"], "mixed")

    def test_catalog_key_mode_still_rejects_other_models_and_placeholders(self):
        for other in (
            "bedrock-sonnet-5",
            "global.anthropic.claude-sonnet-5",
            "unknown",
            "grok",
        ):
            self.assertRaisesRegex(
                ValueError,
                "response-model-mismatch",
                self.verify_grok,
                self.grok_events("bedrock-grok", other),
            )
        self.assertRaisesRegex(
            ValueError,
            "response-model-mismatch",
            self.verify_grok,
            self.grok_events("SYNTHETIC_PRIVATE_ALIAS", "SYNTHETIC_PRIVATE_ALIAS"),
            "SYNTHETIC_PRIVATE_ALIAS",
        )

    def test_catalog_key_mode_keeps_all_tool_round_trip_requirements(self):
        events = self.grok_events()
        for indexes in ((2, 3), (0, 2, 3), (0, 1, 3)):
            self.assertRaises(
                ValueError, self.verify_grok, [events[i] for i in indexes]
            )
        events[1]["message"]["content"][0]["content"] = "wrong-nonce"
        self.assertRaises(ValueError, self.verify_grok, events)
        events = self.grok_events()
        events[-1]["is_error"] = True
        self.assertRaises(ValueError, self.verify_grok, events)
        self.assertRaises(ValueError, self.verify_grok, [*events, events[-1]])

    def test_relative_tool_paths_use_the_client_fixture_directory(self):
        for path in ("fixture.txt", "./fixture.txt", str(self.fixture)):
            events = copy.deepcopy(self.events)
            events[0]["message"]["content"][0]["input"]["file_path"] = path
            self.assertTrue(self.verify(events)["tool_round_trip"])
        events[0]["message"]["content"][0]["input"]["file_path"] = "../fixture.txt"
        self.assertRaises(ValueError, self.verify, events)

    def test_text_only_and_incomplete_calls_fail(self):
        for indexes in ((2, 3), (0, 2, 3), (0, 1, 3)):
            self.assertRaises(
                ValueError, self.verify, [self.events[i] for i in indexes]
            )

    def test_fallback_is_not_counted_as_requested_model(self):
        events = copy.deepcopy(self.events)
        events[2]["message"]["model"] = "claude-sonnet-5"
        self.assertRaises(ValueError, self.verify, events)

    def test_model_identity_diagnostics_preserve_strict_matching(self):
        canary = "SYNTHETIC_SECRET_NEVER_OUTPUT"
        for value, label, kind in (
            ("bedrock-opus-5.5", "bedrock-opus-5.5", "string"),
            ("unknown", "unknown", "string"),
            ("grok", "grok", "string"),
            (canary, "unrecognized", "string"),
            (None, "unrecognized", "missing"),
            ({"private": canary}, "unrecognized", "non-string"),
            ([], "unrecognized", "non-string"),
        ):
            events = copy.deepcopy(self.events)
            events[0]["message"]["model"] = value
            with self.assertRaises(VERIFY["VerificationError"]) as raised:
                self.verify(events)
            report = VERIFY["failure_report"](raised.exception)
            self.assertEqual(report["reason"], "response-model-mismatch")
            self.assertEqual(
                report["diagnostics"]["model_identity"],
                {"expected": PROFILE, "reported": label, "reported_type": kind},
            )
            self.assertNotIn(canary.lower(), json.dumps(report).lower())

    def test_model_identity_fields_are_rewhitelisted(self):
        canary = "SYNTHETIC_SECRET_NEVER_OUTPUT"
        report = VERIFY["safe_diagnostics"](
            {
                "model_identity": {
                    "expected": canary,
                    "reported": canary,
                    "reported_type": canary,
                    "extra": canary,
                }
            }
        )
        self.assertEqual(
            report["model_identity"],
            {
                "expected": "unrecognized",
                "reported": "unrecognized",
                "reported_type": "unrecognized",
            },
        )
        self.assertNotIn(canary, json.dumps(report))
        for invalid in (canary, [], 1):
            self.assertNotIn(
                "model_identity",
                VERIFY["safe_diagnostics"]({"model_identity": invalid}),
            )

    def test_nonobject_assistant_message_is_invalid_stream(self):
        events = copy.deepcopy(self.events)
        events[0]["message"] = "SYNTHETIC_PRIVATE_MESSAGE"
        self.assertRaisesRegex(
            VERIFY["VerificationError"], "invalid-stream", self.verify, events
        )

    def test_unexpected_file_or_tool_fails(self):
        events = copy.deepcopy(self.events)
        events[0]["message"]["content"][0]["input"]["file_path"] = "/tmp/other"
        self.assertRaises(ValueError, self.verify, events)
        events = copy.deepcopy(self.events)
        events[0]["message"]["content"][0]["name"] = "Bash"
        self.assertRaises(ValueError, self.verify, events)

    def test_tool_error_and_wrong_nonce_fail(self):
        events = copy.deepcopy(self.events)
        events[1]["message"]["content"][0]["is_error"] = True
        self.assertRaises(ValueError, self.verify, events)
        events = copy.deepcopy(self.events)
        events[1]["message"]["content"][0]["content"] = "other"
        self.assertRaises(ValueError, self.verify, events)

    def test_duplicate_result_and_failed_result_fail(self):
        self.assertRaises(ValueError, self.verify, [*self.events, self.events[-1]])
        events = copy.deepcopy(self.events)
        events[-1]["is_error"] = True
        self.assertRaises(ValueError, self.verify, events)

    def test_result_must_be_text_and_other_actions_are_rejected(self):
        events = copy.deepcopy(self.events)
        events[-1]["result"] = {NONCE: True}
        self.assertRaises(ValueError, self.verify, events)
        for kind in ("server_tool_use", "web_search_tool_result", "unknown_action"):
            events = copy.deepcopy(self.events)
            events[0]["message"]["content"].append({"type": kind, "name": "web_search"})
            self.assertRaises(ValueError, self.verify, events)

    def test_single_model_selection_is_bounded_to_requested_client(self):
        policy = {"MODELS": {"bedrock-grok": (), "bedrock-opus-5.5": ()}}
        self.assertEqual(
            VERIFY["selected_cases"]("grok", "bedrock-grok", policy),
            [("grok", "bedrock-grok")],
        )
        self.assertRaises(
            ValueError, VERIFY["selected_cases"], "grok", "unknown", policy
        )
        self.assertRaises(
            ValueError, VERIFY["selected_cases"], "all", "bedrock-grok", policy
        )

    def test_failure_summary_redacts_unknown_fields(self):
        canary = "SYNTHETIC_SECRET_NEVER_OUTPUT"
        report = VERIFY["failure_report"](
            ValueError(canary), client=canary, model=canary
        )
        self.assertEqual(report["reason"], "unclassified")
        self.assertNotIn(canary.lower(), json.dumps(report).lower())
        report = VERIFY["failure_report"](
            VERIFY["VerificationError"]("response-model-mismatch"),
            client="grok",
            model="bedrock-grok",
        )
        self.assertEqual(report["reason"], "response-model-mismatch")
        self.assertEqual(report["phase"], "stream")
        self.assertEqual(report["model"], "bedrock-grok")
        error = VERIFY["VerificationError"](
            canary,
            phase=canary,
            diagnostics={
                "codes": [canary, {}, "access-denied"],
                "http_statuses": [canary, 401, {}, True],
                "parameters": [canary, {}, "model"],
                "stdout_received": canary,
            },
        )
        report = VERIFY["failure_report"](error)
        self.assertNotIn(canary.lower(), json.dumps(report).lower())
        self.assertEqual(report["diagnostics"]["codes"], ["access-denied"])
        self.assertEqual(report["diagnostics"]["http_statuses"], [401])
        self.assertEqual(report["diagnostics"]["parameters"], ["model"])
        self.assertFalse(report["diagnostics"]["stdout_received"])

    def test_summary_configuration_failure_keeps_its_safe_reason(self):
        report = VERIFY["failure_report"](
            ValueError("bedrock-reasoning-summary-required")
        )
        self.assertEqual(report["reason"], "bedrock-reasoning-summary-required")
        self.assertEqual(report["phase"], "preflight")
        self.assertFalse(report["deployment_ready"])

    def test_client_diagnostics_emit_only_fixed_markers(self):
        observer = VERIFY["ClientDiagnostics"]()
        canary = b"SYNTHETIC_SECRET_NEVER_OUTPUT"
        observer.observe("stderr", canary + b" AccessDeniedExcep")
        observer.observe("stderr", b"tion: HTTP 403 " + canary)
        report = observer.report()
        self.assertIn("access-denied", report["codes"])
        self.assertIn(403, report["http_statuses"])
        self.assertNotIn(canary.decode(), json.dumps(report))

    def test_mcp_configuration_errors_remain_redacted_across_chunks(self):
        canary = b"SYNTHETIC_SECRET_NEVER_OUTPUT"
        raw = (
            b"\x1b[31mError: Invalid MCP configuration:\n"
            b"mcpServers: Invalid input " + canary + b"\x1b[39m"
        )
        for split in range(len(raw) + 1):
            observer = VERIFY["ClientDiagnostics"]()
            observer.observe("stderr", raw[:split])
            observer.observe("stderr", raw[split:])
            report = VERIFY["safe_diagnostics"](observer.report())
            self.assertIn("mcp-configuration", report["codes"])
            self.assertFalse(report["stdout_received"])
            self.assertTrue(report["stderr_received"])
            self.assertEqual(report["http_statuses"], [])
            self.assertNotIn(canary.decode().lower(), json.dumps(report).lower())
            self.assertLessEqual(len(observer.tails["stderr"]), 512)

    def test_claude_launcher_errors_have_fixed_redacted_categories(self):
        canary = b"SYNTHETIC_SECRET_NEVER_OUTPUT"
        for code, expected in (
            (b"bootstrap-failed", {"claude-launcher", "key-helper"}),
            (b"invalid-key", {"claude-launcher", "key-helper"}),
            (b"settings-format", {"claude-launcher"}),
        ):
            raw = b"claude-bedrock: " + code + b" (launcher): " + canary
            for split in range(len(raw) + 1):
                observer = VERIFY["ClientDiagnostics"]()
                observer.observe("stderr", raw[:split])
                observer.observe("stderr", raw[split:])
                report = VERIFY["safe_diagnostics"](observer.report())
                self.assertEqual(set(report["codes"]), expected)
                self.assertNotIn(canary.decode().lower(), json.dumps(report).lower())

    def test_request_errors_report_only_known_parameters(self):
        canary = "SYNTHETIC_SECRET_NEVER_OUTPUT"
        message = json.dumps(
            {
                "error": {
                    "type": "invalid_request_error",
                    "code": "unsupported_parameter",
                    "message": canary,
                    "param": "reasoning.summary",
                }
            }
        )
        for raw in (message.encode(), json.dumps({"result": message}).encode()):
            for split in range(len(raw) + 1):
                observer = VERIFY["ClientDiagnostics"]()
                observer.observe("stderr", raw[:split])
                observer.observe("stderr", raw[split:])
                report = observer.report()
                self.assertEqual(report["parameters"], ["reasoning.summary"])
                self.assertIn("request-validation", report["codes"])
                self.assertIn("unsupported", report["codes"])
                self.assertNotIn(canary.lower(), json.dumps(report).lower())
                self.assertLessEqual(len(observer.tails["stderr"]), 512)

    def test_parameter_prefix_is_bounded_across_chunks(self):
        raw = b"param" + b" " * 600 + b'"model"'
        for split in (0, 5, len(raw) - 7, len(raw)):
            observer = VERIFY["ClientDiagnostics"]()
            observer.observe("stderr", raw[:split])
            observer.observe("stderr", raw[split:])
            self.assertEqual(observer.report()["parameters"], [])
        observer = VERIFY["ClientDiagnostics"]()
        observer.observe("stderr", b"param" + b" " * 32768 + b"!")
        self.assertEqual(observer.report()["parameters"], [])
        self.assertLessEqual(len(observer.tails["stderr"]), 512)

    def test_maximum_parameter_padding_has_stable_chunk_results(self):
        raw = b"parameter" + b" " * 16 + b":" + b" " * 16
        raw += b'"tools[0].' + b"x" * 110 + b'"'
        for split in range(len(raw) + 1):
            observer = VERIFY["ClientDiagnostics"]()
            observer.observe("stdout", raw[:split])
            observer.observe("stdout", raw[split:])
            self.assertEqual(observer.report()["parameters"], ["tools"])

    def test_parameter_paths_are_closed_and_private_suffixes_are_hidden(self):
        observer = VERIFY["ClientDiagnostics"]()
        canary = "SYNTHETIC_SECRET_NEVER_OUTPUT"
        text = (
            "Unsupported field: 'stream_tool_calls'. "
            '"param": "tools[0].parameters.properties.' + canary + '" '
            '"param": "' + canary + '" '
            '"param": "model-' + canary + '" '
            '"param": "' + "x" * 200 + '" '
        )
        observer.observe("stdout", text.encode())
        report = observer.report()
        self.assertEqual(report["parameters"], ["stream_tool_calls", "tools"])
        self.assertNotIn(canary.lower(), json.dumps(report).lower())
        self.assertEqual(
            VERIFY["safe_diagnostics"]({"parameters": [canary, {}, "model", "model"]})[
                "parameters"
            ],
            ["model"],
        )

    def test_staged_settings_are_allowlisted_and_type_sensitive(self):
        canary = "SYNTHETIC_SECRET_NEVER_OUTPUT"
        document: dict[str, Any] = {
            "model": {"bedrock-grok": {"reasoning_summary": "none", "api_key": canary}},
            "models": {"stream_tool_calls": False, "api_key": canary},
        }
        report = VERIFY["failure_report"](
            VERIFY["VerificationError"]("client-failed", phase="client"),
            client="grok",
            model="bedrock-grok",
            staged_config=document,
        )
        self.assertEqual(
            report["staged_request_settings"],
            {
                "reasoning_summary": "none",
                "model_stream_tool_calls": "unset",
                "global_stream_tool_calls": False,
            },
        )
        self.assertNotIn(canary.lower(), json.dumps(report).lower())
        for value in (canary, {}, [], None, 0, 1):
            document["model"]["bedrock-grok"]["reasoning_summary"] = value
            document["model"]["bedrock-grok"]["stream_tool_calls"] = value
            document["models"]["stream_tool_calls"] = value
            settings = VERIFY["staged_request_settings"](document, "bedrock-grok")
            self.assertEqual(set(settings.values()), {"other"})
            self.assertNotIn(canary, json.dumps(settings))
        for malformed in ({}, [], {"model": []}, {"model": {"bedrock-grok": []}}):
            self.assertEqual(
                VERIFY["staged_request_settings"](malformed, "bedrock-grok"), {}
            )
        self.assertNotIn(
            "staged_request_settings",
            VERIFY["failure_report"](
                ValueError(canary), client=canary, model=canary, staged_config=document
            ),
        )

    def test_client_failure_preserves_reason_and_exit_code(self):
        class FailedProcess(ValueError):
            returncode = 2

        def fail_process(*_args, **kwargs):
            kwargs["observe"](
                "stderr",
                b'HTTP 400 {"type":"invalid_request_error","param":"service_tier"}',
            )
            raise FailedProcess("failed")

        control = {"capture": mock.Mock(side_effect=fail_process)}
        with (
            mock.patch.object(runpy, "run_path", return_value=control),
            self.assertRaises(VERIFY["VerificationError"]) as raised,
        ):
            VERIFY["capture"](
                ["synthetic-client"], {}, self.fixture.parent, "synthetic-control"
            )
        report = VERIFY["failure_report"](
            raised.exception, client="grok", model="bedrock-grok"
        )
        self.assertEqual(report["phase"], "client")
        self.assertEqual(report["reason"], "client-failed")
        self.assertEqual(report["returncode"], 2)
        self.assertEqual(report["diagnostics"]["http_statuses"], [400])
        self.assertEqual(report["diagnostics"]["parameters"], ["service_tier"])
        self.assertIn("request-validation", report["diagnostics"]["codes"])

    def test_successful_capture_can_share_observations(self):
        observer = VERIFY["ClientDiagnostics"]()
        raw = b"synthetic-output"

        def captured(*_args, **kwargs):
            kwargs["observe"]("stdout", raw)
            kwargs["observe"]("stderr", b"synthetic-warning")
            return raw

        with mock.patch.object(runpy, "run_path", return_value={"capture": captured}):
            result = VERIFY["capture"](
                ["synthetic-client"],
                {},
                self.fixture.parent,
                "synthetic-control",
                diagnostics=observer,
            )
        self.assertEqual(result, raw)
        self.assertTrue(observer.report()["stdout_received"])
        self.assertTrue(observer.report()["stderr_received"])

    def test_grok_client_path_cleans_credentials_and_keeps_partial_evidence(self):
        extra_names = (
            "INPUT_AWS_BEARER_TOKEN_BEDROCK",
            "OPENAI_API_KEY",
            "XAI_API_KEY",
            "GROK_CODE_XAI_API_KEY",
        )
        runtime = {
            "empty_aws_config": "synthetic-config",
            "empty_aws_credentials": "synthetic-credentials",
            "grok_binary": "synthetic-client",
            "grok_policy": "synthetic-policy",
            "process_control": "synthetic-control",
        }

        def captured(command, env, cwd, _control, **kwargs):
            self.assertEqual(command[command.index("--model") + 1], "bedrock-grok")
            for name in extra_names:
                self.assertNotIn(name, env)
            self.assertEqual(env["TYPESAFE_API_KEY"], "SYNTHETIC_ALLOWED_TYPESAFE")
            self.assertEqual(cwd.parent, self.fixture.parent)
            nonce = (cwd / "fixture.txt").read_text()
            events = self.grok_events()
            events[0]["message"]["content"][0]["input"]["file_path"] = "fixture.txt"
            events[1]["message"]["content"][0]["content"] = nonce
            events[2]["message"]["content"][0]["text"] = nonce
            events[-1]["result"] = nonce
            raw = b"\n".join(json.dumps(event).encode() for event in events)
            kwargs["diagnostics"].observe("stdout", raw)
            return raw

        with (
            mock.patch.object(
                runpy,
                "run_path",
                return_value={"MODELS": {"bedrock-grok": ("global.xai.grok-4.6",)}},
            ),
            mock.patch.dict(VERIFY["test_model"].__globals__, capture=captured),
            mock.patch.dict(
                os.environ,
                {
                    "PATH": "/usr/bin:/bin",
                    "TMPDIR": str(self.fixture.parent),
                    "TYPESAFE_API_KEY": "SYNTHETIC_ALLOWED_TYPESAFE",
                    **dict.fromkeys(extra_names, "SYNTHETIC_EXTRA_CREDENTIAL"),
                },
                clear=True,
            ),
        ):
            result = VERIFY["test_model"](
                "grok", "bedrock-grok", runtime, {"grok_home": str(self.fixture.parent)}
            )
        self.assertTrue(result["tool_round_trip"])
        self.assertTrue(result["client_model_label_verified"])
        self.assertFalse(result["response_model_verified"])
        self.assertFalse(result["wire_model_id_verified"])
        self.assertEqual(result["model_identity_source"], "catalog-key")

    def test_claude_client_path_uses_a_valid_empty_mcp_configuration(self):
        runtime = {
            "empty_aws_config": "synthetic-config",
            "empty_aws_credentials": "synthetic-credentials",
            "claude_launcher": "synthetic-claude",
            "process_control": "synthetic-control",
        }
        profile = VERIFY["CLAUDE_MODELS"]["haiku"]

        def captured(command, _env, cwd, _control, **kwargs):
            self.assertEqual(command[0], "synthetic-claude")
            self.assertEqual(command[command.index("--model") + 1], "haiku")
            self.assertIn("--strict-mcp-config", command)
            self.assertEqual(
                json.loads(command[command.index("--mcp-config") + 1]),
                {"mcpServers": {}},
            )
            self.assertEqual(command[command.index("--tools") + 1], "Read")
            self.assertEqual(
                command[command.index("--allowedTools") + 1],
                f"Read({cwd / 'fixture.txt'})",
            )
            self.assertEqual(command[command.index("--disallowedTools") + 1], "mcp__*")
            self.assertEqual(command[command.index("--max-turns") + 1], "4")
            self.assertEqual(cwd.parent, self.fixture.parent)
            nonce = (cwd / "fixture.txt").read_text()
            events = copy.deepcopy(self.events)
            events[0]["message"]["model"] = profile
            events[0]["message"]["content"][0]["input"]["file_path"] = "fixture.txt"
            events[1]["message"]["content"][0]["content"] = nonce
            events[2]["message"]["model"] = profile
            events[2]["message"]["content"][0]["text"] = nonce
            events[-1]["result"] = nonce
            events[-1]["modelUsage"] = {}
            raw = b"\n".join(json.dumps(event).encode() for event in events)
            kwargs["diagnostics"].observe("stdout", raw)
            return raw

        with (
            mock.patch.dict(VERIFY["test_model"].__globals__, capture=captured),
            mock.patch.dict(
                os.environ,
                {"PATH": "/usr/bin:/bin", "TMPDIR": str(self.fixture.parent)},
                clear=True,
            ),
        ):
            result = VERIFY["test_model"]("claude", "haiku", runtime, {})
        self.assertTrue(result["tool_round_trip"])
        self.assertTrue(result["response_model_verified"])
        self.assertFalse(result["wire_model_id_verified"])
        self.assertEqual(result["reported_context_windows"], [])

    def test_stream_failures_keep_observations_and_client_exit_code(self):
        canary = "SYNTHETIC_SECRET_NEVER_OUTPUT"
        profile = "global.xai.grok-4.6"
        runtime = {
            "empty_aws_config": "synthetic-config",
            "empty_aws_credentials": "synthetic-credentials",
            "grok_binary": "synthetic-client",
            "grok_policy": "synthetic-policy",
            "process_control": "synthetic-control",
        }
        # The stdlib fallback's recursion limit is independent of the C decoder.
        recursive_scanner = vars(json.scanner)["py_make_scanner"]
        with mock.patch.object(json.scanner, "make_scanner", recursive_scanner):
            decoder = json.JSONDecoder()

        def decode(raw):
            return decoder.decode(raw.decode("utf-8"))

        depth = sys.getrecursionlimit() + 32
        cases = (
            (b"not-json", "invalid-client-json"),
            (b"[" * depth + b"0" + b"]" * depth, "invalid-client-json"),
            (
                json.dumps(
                    {"type": "assistant", "message": {"model": "unknown"}}
                ).encode(),
                "response-model-mismatch",
            ),
            (
                json.dumps({"type": "assistant", "message": []}).encode(),
                "invalid-stream",
            ),
            (
                json.dumps(
                    {"type": "assistant", "message": {"model": profile, "content": []}}
                ).encode(),
                "tool-round-trip-unverified",
            ),
            (
                json.dumps(
                    {
                        "type": "assistant",
                        "message": {
                            "model": profile,
                            "content": [
                                {
                                    "type": "tool_use",
                                    "id": "call",
                                    "name": "read_file",
                                    "input": {"path": "\u0000" + canary},
                                }
                            ],
                        },
                    }
                ).encode(),
                "unclassified",
            ),
        )
        for raw, expected_reason in cases:

            def captured(*_args, _raw=raw, **kwargs):
                kwargs["diagnostics"].observe("stdout", _raw)
                kwargs["diagnostics"].observe("stderr", b"synthetic-warning")
                return _raw

            with (
                mock.patch.object(
                    runpy,
                    "run_path",
                    return_value={"MODELS": {"bedrock-grok": (profile,)}},
                ),
                mock.patch.dict(VERIFY["test_model"].__globals__, capture=captured),
                mock.patch.object(json, "loads", side_effect=decode),
                mock.patch.dict(
                    os.environ,
                    {"PATH": "/usr/bin:/bin", "TMPDIR": str(self.fixture.parent)},
                    clear=True,
                ),
                self.assertRaises(VERIFY["VerificationError"]) as raised,
            ):
                VERIFY["test_model"](
                    "grok",
                    "bedrock-grok",
                    runtime,
                    {"grok_home": str(self.fixture.parent)},
                )
            report = VERIFY["failure_report"](raised.exception)
            self.assertEqual(report["reason"], expected_reason)
            self.assertEqual(report["phase"], "stream")
            self.assertEqual(report["returncode"], 0)
            self.assertTrue(report["diagnostics"]["stdout_received"])
            self.assertTrue(report["diagnostics"]["stderr_received"])
            self.assertNotIn(canary.lower(), json.dumps(report).lower())

    def test_failed_model_keeps_completed_model_labels(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR", "/tmp")) as root:
            runtime_path = Path(root) / "runtime.json"
            stage_path = Path(root) / "manifest.json"
            runtime = {
                "grok_key_helper": "synthetic-helper",
                "claude_launcher": "synthetic-claude",
                "grok_policy": "synthetic-policy",
                "shell_policy": {},
            }
            stage = {**runtime, "grok_home": root}
            runtime_path.write_text(json.dumps(runtime))
            stage_path.write_text(json.dumps(stage))
            policy = {
                "MODELS": {"bedrock-grok": (), "bedrock-opus-5.5": ()},
                "check_config": mock.Mock(
                    return_value={
                        "model": {"bedrock-opus-5.5": {"reasoning_summary": "none"}},
                        "models": {"stream_tool_calls": False},
                    }
                ),
            }
            stderr = io.StringIO()
            cases = mock.Mock(
                side_effect=[
                    {
                        "client": "grok",
                        "model": "bedrock-grok",
                        "response_model_verified": True,
                    },
                    VERIFY["VerificationError"]("response-model-mismatch"),
                ]
            )
            with (
                mock.patch.object(runpy, "run_path", return_value=policy),
                mock.patch.dict(VERIFY["main"].__globals__, test_model=cases),
                redirect_stderr(stderr),
            ):
                status = VERIFY["main"](
                    [str(runtime_path), str(stage_path), "--client", "grok", "--run"]
                )
            self.assertEqual(status, 1)
            report = json.loads(stderr.getvalue())
            self.assertEqual(report["model"], "bedrock-opus-5.5")
            self.assertEqual(
                report["completed_models"],
                [{"client": "grok", "model": "bedrock-grok"}],
            )
            self.assertEqual(report["phase"], "stream")
            self.assertEqual(
                report["staged_request_settings"],
                {
                    "reasoning_summary": "none",
                    "model_stream_tool_calls": "unset",
                    "global_stream_tool_calls": False,
                },
            )

    def test_partial_identity_stops_the_batch_with_a_distinct_status(self):
        for verified, expected_status, expected_exit, expected_calls in (
            (False, "base-smoke-partial", 2, 1),
            (True, "base-smoke-passed", 0, 2),
        ):
            runtime_path = self.fixture.parent / "runtime.json"
            stage_path = self.fixture.parent / "manifest.json"
            runtime = {
                "grok_key_helper": "synthetic-helper",
                "claude_launcher": "synthetic-claude",
                "grok_policy": "synthetic-policy",
                "shell_policy": {},
            }
            runtime_path.write_text(json.dumps(runtime))
            stage_path.write_text(
                json.dumps({**runtime, "grok_home": str(self.fixture.parent)})
            )
            models = ("bedrock-grok", "bedrock-opus-5.5")
            policy = {
                "MODELS": dict.fromkeys(models),
                "check_config": mock.Mock(return_value={}),
            }
            cases = mock.Mock(
                side_effect=[
                    {
                        "client": "grok",
                        "model": model,
                        "tool_round_trip": True,
                        "client_model_label_verified": True,
                        "response_model_verified": verified,
                        "wire_model_id_verified": False,
                    }
                    for model in models
                ]
            )
            output = io.StringIO()
            with (
                mock.patch.object(runpy, "run_path", return_value=policy),
                mock.patch.dict(VERIFY["main"].__globals__, test_model=cases),
                redirect_stdout(output),
            ):
                status = VERIFY["main"](
                    [str(runtime_path), str(stage_path), "--client", "grok", "--run"]
                )
            report = json.loads(output.getvalue())
            self.assertEqual(status, expected_exit)
            self.assertEqual(report["status"], expected_status)
            self.assertEqual(cases.call_count, expected_calls)
            self.assertEqual(len(report["results"]), expected_calls)
            self.assertIs(report["results"][-1]["response_model_verified"], verified)
            self.assertFalse(report["deployment_ready"])
            self.assertEqual(
                report["manual_gates_remaining"], list(VERIFY["MANUAL_GATES"])
            )

    def test_command_requires_explicit_user_run_confirmation(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR", "/tmp")) as root:
            runtime = Path(root) / "runtime.json"
            runtime.write_text("{}")
            with mock.patch("subprocess.Popen") as process:
                self.assertRaises(
                    ValueError,
                    VERIFY["main"],
                    [str(runtime), str(Path(root) / "stage.json")],
                )
            process.assert_not_called()


if __name__ == "__main__":
    unittest.main()
