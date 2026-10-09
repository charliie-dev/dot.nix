"""Offline contracts for the Bedrock Grok helper and config migration."""

import copy
import json
import os
import runpy
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from typing import Any
from unittest import mock

import tomlkit

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "conf.d" / "bedrock-api-key"
POLICY = runpy.run_path(str(SCRIPTS / "grok_policy.py"))
GROK = runpy.run_path(str(SCRIPTS / "grok.py"))
CONFIG = runpy.run_path(str(SCRIPTS / "grok_config.py"))
FAKE_KEY = "SYNTHETIC_BEDROCK_KEY+/="
SHELL_POLICY = {
    "inherit": "all",
    "ignore_default_excludes": True,
    "exclude": ["DOPPLER_TOKEN", "AWS_BEARER_TOKEN_BEDROCK"],
    "include_only": ["HOME", "PATH"],
}


class GrokContracts(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(
            prefix="bedrock-grok-", dir=os.environ.get("TMPDIR", "/tmp")
        )
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / "grok"
        self.home.mkdir(mode=0o700)
        self.path = self.home / "config.toml"
        self.runner = self.root / "fake-doppler"
        self.runtime = {
            "home": str(self.root),
            "grok_home": str(self.home),
            "grok_policy": str(SCRIPTS / "grok_policy.py"),
            "process_control": str(SCRIPTS / "process_control.py"),
            "grok_binary": "grok",
            "python": sys.executable,
            "doppler_run": str(self.runner),
            "helper_path": "/usr/bin:/bin",
            "shell_policy": copy.deepcopy(SHELL_POLICY),
            "sensitive_names": ["DOPPLER_TOKEN", "AZURE_OPENAI_API_KEY"],
            "grok_key_helper": "/nix/store/synthetic-helper/bin/bedrock-api-key",
            "claude_launcher": "/nix/store/synthetic-claude/bin/claude-bedrock",
            "claude_overlay": "/nix/store/synthetic-overlay",
            "empty_aws_config": "/nix/store/synthetic-empty-config",
            "empty_aws_credentials": "/nix/store/synthetic-empty-credentials",
            "false_binary": "/usr/bin/false",
        }
        self.runtime_path = self.root / "runtime.json"
        self.runtime_path.write_text(json.dumps(self.runtime))
        self.document = self.model_document()
        self.save(self.document)

    def model_document(self) -> dict[str, Any]:
        models: dict[str, Any] = {}
        for alias, (model_id, backend, suffix) in POLICY["MODELS"].items():
            models[alias] = {
                "model": model_id,
                "base_url": POLICY["RUNTIME_URL"] + suffix,
                "api_backend": backend,
                "auth_provider": "bedrock",
                "context_window": 1000000,
                "reasoning_effort": "high",
            }
            if backend == "messages":
                models[alias]["extra_headers"] = {"anthropic-version": "2023-06-01"}
        return {
            "model": models,
            "shell_environment_policy": CONFIG["legacy_policy"](self.runtime),
            "unrelated": {"value": "SYNTHETIC_UNRELATED_VALUE"},
        }

    def save(self, document):
        self.path.write_text(tomlkit.dumps(document))
        self.path.chmod(0o600)

    def fake_runner(self, body):
        self.runner.write_text("#!/bin/sh\nset -eu\n" + body + "\n")
        self.runner.chmod(0o700)

    def test_key_validation(self):
        self.assertEqual(GROK["validate_key"](FAKE_KEY), FAKE_KEY)
        invalid = ("", " ", "key\n", "key\r", "key\x00", "key\t", "キー", "k" * 65537)
        for value in invalid:
            with self.subTest(value_length=len(value)), self.assertRaises(ValueError):
                GROK["validate_key"](value)

    def test_provider_json_cannot_override_cache_lifetime(self):
        candidates = (
            '{"access_token":"SYNTHETIC_ONLY","expires_in":86400}',
            '["SYNTHETIC_ONLY"]',
            '"SYNTHETIC_ONLY"',
        )
        for candidate in candidates:
            self.assertRaises(ValueError, GROK["validate_key"], candidate)

    def test_helper_uses_only_fixed_profile_and_clean_environment(self):
        self.fake_runner(
            'test "$1" = bedrock-grok-token\n'
            'test "$2" = --\n'
            'test -z "${GROK_AUTH_PROVIDER_ACCESS_TOKEN+x}"\n'
            'test -z "${AWS_PROFILE+x}"\n'
            'test -z "${DOPPLER_TOKEN+x}"\n'
            'test -z "${AZURE_OPENAI_API_KEY+x}"\n'
            "shift 2\n"
            f"export AWS_BEARER_TOKEN_BEDROCK='{FAKE_KEY}'\n"
            'exec "$@"'
        )
        with mock.patch.dict(
            os.environ,
            {
                "GROK_AUTH_PROVIDER_ACCESS_TOKEN": "SYNTHETIC_OLD_KEY",
                "AWS_PROFILE": "SYNTHETIC_PROFILE",
                "DOPPLER_TOKEN": "SYNTHETIC_BOOTSTRAP",
                "AZURE_OPENAI_API_KEY": "SYNTHETIC_AZURE",
            },
            clear=True,
        ):
            self.assertEqual(
                GROK["read_key"](self.runtime, str(self.runtime_path)), FAKE_KEY
            )

    def test_failed_helper_does_not_print_child_output(self):
        self.fake_runner(f"printf '{FAKE_KEY}'\nprintf '{FAKE_KEY}' >&2\nexit 7")
        result = subprocess.run(
            [
                sys.executable,
                "-I",
                str(SCRIPTS / "grok.py"),
                str(self.runtime_path),
                "key",
            ],
            env={"HOME": str(self.root), "PATH": "/usr/bin:/bin"},
            capture_output=True,
            timeout=5,
            check=False,
        )
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, b"")
        self.assertNotIn(FAKE_KEY.encode(), result.stderr)
        self.assertIn(b"doppler-retrieval-failed", result.stderr)

    def test_timeout_reaps_process(self):
        self.fake_runner("exec /bin/sleep 30")
        created: list[subprocess.Popen[Any]] = []
        popen = subprocess.Popen

        def record(*args, **kwargs):
            process = popen(*args, **kwargs)
            created.append(process)
            return process

        started = time.monotonic()
        namespace = GROK["read_key"].__globals__
        with (
            mock.patch.dict(namespace, HELPER_TIMEOUT=0.1),
            mock.patch.object(subprocess, "Popen", side_effect=record),
            self.assertRaisesRegex(ValueError, "doppler-timeout"),
        ):
            GROK["read_key"](self.runtime, str(self.runtime_path))
        self.assertLess(time.monotonic() - started, 3)
        self.assertEqual(len(created), 1)
        self.assertIsNotNone(created[0].returncode)
        with self.assertRaises(ProcessLookupError):
            os.kill(created[0].pid, 0)

    def test_cleanup_failure_is_distinct_from_cancellation(self):
        control = {"capture": mock.Mock(side_effect=ValueError("cleanup-failed"))}
        with mock.patch.object(runpy, "run_path", return_value=control):
            self.assertRaisesRegex(
                ValueError,
                "doppler-cleanup-failed",
                GROK["read_key"],
                self.runtime,
                str(self.runtime_path),
            )

    def test_cancellation_handler_interrupts(self):
        with self.assertRaises(KeyboardInterrupt):
            GROK["interrupted"](signal.SIGTERM, None)

    def test_model_arguments_and_separator(self):
        allowed = set(POLICY["MODELS"])
        for args in (
            ["-m", "bedrock-grok"],
            ["--model=bedrock-sonnet-5"],
            ["--model", "bedrock-haiku-5.5"],
            ["--model=bedrock-haiku-5.5"],
            ["-mbedrock-grok"],
        ):
            self.assertEqual(GROK["model_arguments"](list(args), allowed), args)
        self.assertEqual(
            GROK["model_arguments"](["--", "--model=other"], allowed),
            ["--model", "bedrock-opus-5.5", "--", "--model=other"],
        )
        invalid = (
            ["-m"],
            ["-m", "azure"],
            ["--model", "global.anthropic.claude-haiku-5-5"],
            ["--model", "global.anthropic.claude-haiku-4-5-20251001-v1:0"],
            ["--config=x"],
            ["-m", "bedrock-grok", "-m", "bedrock-grok"],
        )
        for args in invalid:
            with self.subTest(args=args), self.assertRaises(ValueError):
                GROK["model_arguments"](list(args), allowed)

    def test_client_environment_keeps_context_and_clears_competitors(self):
        environment = {
            "GROK_CONFIG": "SYNTHETIC_OVERRIDE",
            "AWS_BEARER_TOKEN_BEDROCK": FAKE_KEY,
            "AZURE_OPENAI_API_KEY": "SYNTHETIC_AZURE",
            "ANTHROPIC_API_KEY": "SYNTHETIC_ANTHROPIC",
            "HERDR_PANE_ID": "synthetic-pane",
            "GROK_HOME": "SYNTHETIC_HOME",
        }
        with mock.patch.dict(os.environ, environment, clear=True):
            result = GROK["launch_environment"](self.runtime)
        self.assertEqual(
            result, {"GROK_HOME": str(self.home), "HERDR_PANE_ID": "synthetic-pane"}
        )

    def test_launch_clears_extra_credentials_and_preserves_typesafe(self):
        self.save(
            CONFIG["updated_document"](
                self.runtime, self.path.read_bytes(), POLICY, disable=False
            )
        )
        extra_names = (
            "INPUT_AWS_BEARER_TOKEN_BEDROCK",
            "OPENAI_API_KEY",
            "XAI_API_KEY",
            "GROK_CODE_XAI_API_KEY",
        )
        retained = {
            "HOME": str(self.root),
            "PATH": "/usr/bin:/bin",
            "HERDR_PANE_ID": "synthetic-pane",
            "TYPESAFE_API_KEY": "SYNTHETIC_ALLOWED_TYPESAFE",
            "UNRELATED_SETTING": "SYNTHETIC_UNRELATED",
        }
        for value in ("", FAKE_KEY):
            environment = {**retained, **dict.fromkeys(extra_names, value)}
            with (
                self.subTest(empty=not value),
                mock.patch.dict(os.environ, environment, clear=True),
                mock.patch.object(os, "execvpe") as execute,
            ):
                GROK["launch"](self.runtime, ["--model", "bedrock-grok"])
                execute.assert_called_once_with(
                    "grok",
                    ["grok", "--model", "bedrock-grok"],
                    {**retained, "GROK_HOME": str(self.home)},
                )
                self.assertEqual(dict(os.environ), environment)

    def test_model_and_policy_drift_is_rejected(self):
        for field, value in (
            ("env_key", "OTHER_KEY"),
            ("api_key", "SYNTHETIC_KEY"),
            ("base_url", "https://invalid.example"),
        ):
            doc = copy.deepcopy(self.document)
            doc["model"]["bedrock-grok"][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                POLICY["validate_models"](doc, ("bedrock",))
        with self.assertRaises(ValueError):
            POLICY["validate_shell_policy"](self.document, SHELL_POLICY)

    def test_global_headers_use_the_models_defaults_section(self):
        document = copy.deepcopy(self.document)
        document["models"] = {"extra_headers": {"Authorization": "SYNTHETIC_KEY"}}
        self.assertRaisesRegex(
            ValueError,
            "global-headers-require-review",
            POLICY["validate_models"],
            document,
            ("bedrock",),
        )
        document.pop("models")
        document["extra_headers"] = {"Authorization": "SYNTHETIC_IGNORED_ROOT"}
        POLICY["validate_models"](document, ("bedrock",))
        for defaults in (False, [], {"extra_headers": False}, {"extra_headers": []}):
            document["models"] = defaults
            self.assertRaises(
                ValueError, POLICY["validate_models"], document, ("bedrock",)
            )

    def test_inherited_credentials_and_dynamic_headers_require_review(self):
        fields = {
            "model_provider": "synthetic-shared-provider",
            "env_http_headers": {"Authorization": "SYNTHETIC_ENV_NAME"},
            "query_params": {"api-key": "SYNTHETIC_VALUE"},
        }
        for key, value in fields.items():
            document = copy.deepcopy(self.document)
            document["model"]["bedrock-grok"][key] = value
            self.assertRaises(
                ValueError, POLICY["validate_models"], document, ("bedrock",)
            )

    def test_legacy_catalog_stages_and_publishes_only_missing_haiku(self):
        alias = "bedrock-haiku-5.5"
        self.document["model"].pop(alias)
        self.document["model"]["unrelated"] = {"model": "synthetic-other"}
        self.document["models"] = {"default_reasoning_effort": "low"}
        self.save(self.document)
        with self.path.open("a") as stream:
            stream.write("\n# synthetic preserved comment\n")
        original = self.path.read_bytes()
        review = CONFIG["main"]([str(self.runtime_path), "check"])
        self.assertEqual(review["models_to_add"], [alias])
        self.assertEqual(set(review["providers"]), set(POLICY["MODELS"]) - {alias})
        self.assertRaises(
            ValueError, POLICY["validate_models"], self.document, ("bedrock",)
        )
        stage_root = self.root / "legacy-stage"
        stage_root.mkdir(mode=0o700)
        CONFIG["stage"](self.runtime, stage_root)
        self.assertEqual(self.path.read_bytes(), original)
        staged, _ = POLICY["read_config"](stage_root / "grok/config.toml")
        expected = {
            "model": "global.anthropic.claude-haiku-5-5",
            "api_backend": "messages",
            "base_url": "https://bedrock-runtime.ap-northeast-1.amazonaws.com/anthropic/v1",
            "auth_provider": "bedrock-doppler",
            "extra_headers": {"anthropic-version": "2023-06-01"},
            "context_window": 1000000,
            "max_completion_tokens": 8192,
        }
        self.assertEqual(staged["model"][alias], expected)
        self.assertEqual(staged["models"], self.document["models"])
        self.assertEqual(set(staged["model"]), set(POLICY["MODELS"]))
        manifest = json.loads((stage_root / "manifest.json").read_text())
        self.assertEqual(manifest["models"], list(POLICY["MODELS"]))
        self.assertRaisesRegex(
            ValueError,
            "changed-since-review",
            CONFIG["migrate"],
            self.runtime,
            "0" * 64,
            False,
        )
        result = CONFIG["migrate"](self.runtime, review["sha256"], False)
        self.assertNotIn(alias, result["previous_providers"])
        published, raw = POLICY["read_config"](self.path)
        self.assertEqual(published["model"][alias], expected)
        expected_document = copy.deepcopy(self.document)
        expected_document["model"][alias] = expected
        for name in POLICY["MODELS"]:
            expected_document["model"][name]["auth_provider"] = "bedrock-doppler"
        expected_document["model"]["bedrock-grok"]["reasoning_summary"] = "none"
        expected_document["shell_environment_policy"] = SHELL_POLICY
        expected_document["auth_provider"] = {
            "bedrock-doppler": {
                "command": str(self.home / "bin/bedrock-api-key"),
                "args": [],
                "token_ttl_secs": 300,
                "timeout_secs": 30,
            }
        }
        self.assertEqual(published, expected_document)
        self.assertIn(b"# synthetic preserved comment", raw)
        with mock.patch.object(os, "execvpe") as execute:
            GROK["launch"](self.runtime, ["--model", alias])
        self.assertEqual(execute.call_args.args[1], ["grok", "--model", alias])
        self.assertEqual(
            CONFIG["main"]([str(self.runtime_path), "check"])["models_to_add"], []
        )
        CONFIG["migrate"](self.runtime, CONFIG["fingerprint"](raw), False)
        self.assertEqual(self.path.read_bytes(), raw)

    def test_missing_haiku_is_migration_only_not_runtime_compatible(self):
        active = CONFIG["updated_document"](
            self.runtime, self.path.read_bytes(), POLICY, disable=False
        )
        del active["model"]["bedrock-haiku-5.5"]
        self.save(active)
        CONFIG["baseline"](self.runtime)
        with mock.patch.object(os, "execvpe") as execute:
            self.assertRaisesRegex(
                ValueError,
                "grok-configuration-preflight-failed",
                GROK["launch"],
                self.runtime,
                [],
            )
        execute.assert_not_called()

    def test_migration_does_not_repair_conflicting_or_missing_legacy_models(self):
        for field, value in (
            ("model", "global.anthropic.claude-haiku-4-5-20251001-v1:0"),
            ("base_url", "https://invalid.example"),
            ("api_backend", "responses"),
            ("auth_provider", "other"),
            ("api_key", FAKE_KEY),
            ("env_key", "OTHER_KEY"),
            ("extra_headers", {"Authorization": FAKE_KEY}),
            ("model_provider", "other"),
            ("env_http_headers", {"Authorization": "OTHER_KEY"}),
            ("query_params", {"api-key": FAKE_KEY}),
        ):
            document = copy.deepcopy(self.document)
            document["model"]["bedrock-haiku-5.5"][field] = value
            self.save(document)
            raw = self.path.read_bytes()
            self.assertRaises(ValueError, CONFIG["baseline"], self.runtime)
            self.assertRaises(
                ValueError,
                CONFIG["migrate"],
                self.runtime,
                CONFIG["fingerprint"](raw),
                False,
            )
            self.assertEqual(self.path.read_bytes(), raw)
        for alias in POLICY["MODELS"]:
            if alias == "bedrock-haiku-5.5":
                continue
            document = copy.deepcopy(self.document)
            document["model"].pop(alias)
            self.save(document)
            self.assertRaises(ValueError, CONFIG["baseline"], self.runtime)

    def test_disable_legacy_catalog_does_not_add_haiku(self):
        self.document["model"].pop("bedrock-haiku-5.5")
        self.save(self.document)
        CONFIG["migrate"](
            self.runtime, CONFIG["fingerprint"](self.path.read_bytes()), True
        )
        disabled, _ = POLICY["read_config"](self.path)
        self.assertNotIn("bedrock-haiku-5.5", disabled["model"])
        self.assertTrue(
            all(
                model["auth_provider"] == "bedrock-disabled"
                for model in disabled["model"].values()
            )
        )

    def test_staging_preserves_nonsecret_inference_defaults(self):
        defaults = {
            "temperature": 0.4,
            "max_completion_tokens": 512,
            "default_reasoning_effort": "low",
        }
        self.document["models"] = {**defaults, "unused_fixture_field": "not-copied"}
        self.save(self.document)
        stage_root = self.root / "stage-defaults"
        stage_root.mkdir(mode=0o700)
        CONFIG["stage"](self.runtime, stage_root)
        staged, _ = POLICY["read_config"](stage_root / "grok" / "config.toml")
        self.assertEqual(staged["models"], defaults)

    def test_staging_normalizes_summary_and_preserves_source(self):
        variants = (
            {},
            {"reasoning_summary": "concise"},
            {"reasoning_summary": "auto"},
            {"reasoning_summary": "detailed"},
            {"reasoning_summary": "none"},
        )
        for index, fields in enumerate(variants):
            self.document["model"]["bedrock-grok"].pop("reasoning_summary", None)
            self.document["model"]["bedrock-grok"].update(fields)
            self.save(self.document)
            original = self.path.read_bytes()
            root = self.root / f"stage-summary-{index}"
            root.mkdir(mode=0o700)
            CONFIG["stage"](self.runtime, root)
            staged, _ = POLICY["read_config"](root / "grok" / "config.toml")
            expected = copy.deepcopy(self.document["model"])
            for model in expected.values():
                model["auth_provider"] = POLICY["PROVIDER"]
            expected["bedrock-grok"]["reasoning_summary"] = "none"
            self.assertEqual(staged["model"], expected)
            self.assertEqual(self.path.read_bytes(), original)

    def test_launch_rejects_incompatible_summary_before_client_exec(self):
        active = CONFIG["updated_document"](
            self.runtime, self.path.read_bytes(), POLICY, disable=False
        )
        active["model"]["bedrock-grok"]["reasoning_summary"] = "none"
        self.save(active)
        with mock.patch.object(os, "execvpe") as execute:
            GROK["launch"](self.runtime, ["--model", "bedrock-grok"])
        execute.assert_called_once()
        for fields in (
            {},
            {"reasoning_summary": "concise"},
            {"reasoning_summary": "auto"},
            {"reasoning_summary": "detailed"},
            {"reasoning_summary": False},
        ):
            document = copy.deepcopy(active)
            document["model"]["bedrock-grok"].pop("reasoning_summary", None)
            document["model"]["bedrock-grok"].update(fields)
            self.save(document)
            with mock.patch.object(os, "execvpe") as execute:
                self.assertRaisesRegex(
                    ValueError,
                    "grok-configuration-preflight-failed",
                    GROK["launch"],
                    self.runtime,
                    ["--model", "bedrock-grok"],
                )
            execute.assert_not_called()

    def test_publish_preserves_other_models_fields_mode_and_xattrs(self):
        self.document["model"]["bedrock-grok"]["reasoning_summary"] = "concise"
        self.save(self.document)
        attribute = (
            "com.example.bedrock-test"
            if sys.platform == "darwin"
            else "user.bedrock-test"
        )
        if sys.platform == "darwin":
            subprocess.run(
                [
                    "/usr/bin/xattr",
                    "-w",
                    attribute,
                    "synthetic-metadata",
                    str(self.path),
                ],
                check=True,
            )
            subprocess.run(
                ["/bin/chmod", "+a", "everyone allow read", str(self.path)], check=True
            )
        else:
            set_attribute = getattr(os, "setxattr", None)
            if not callable(set_attribute):
                self.fail("platform must support extended-attribute fixtures")
            set_attribute(self.path, attribute, b"synthetic-metadata")
        original_acl = CONFIG["access_control"](self.path)
        raw = self.path.read_bytes()
        result = CONFIG["migrate"](self.runtime, CONFIG["fingerprint"](raw), False)
        self.assertEqual(result["status"], "bedrock-published")
        doc, _ = POLICY["read_config"](self.path)
        expected_models = copy.deepcopy(self.document["model"])
        expected_models["bedrock-grok"]["reasoning_summary"] = "none"
        for alias in POLICY["MODELS"]:
            expected = {
                **expected_models[alias],
                "auth_provider": "bedrock-doppler",
            }
            self.assertEqual(doc["model"][alias], expected)
        self.assertEqual(doc["unrelated"], self.document["unrelated"])
        self.assertEqual(doc["shell_environment_policy"], SHELL_POLICY)
        self.assertEqual(
            CONFIG["extended_attributes"](self.path)[attribute], b"synthetic-metadata"
        )
        self.assertEqual(CONFIG["access_control"](self.path), original_acl)
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)
        POLICY["check_config"](
            self.path, SHELL_POLICY, str(self.home / "bin" / "bedrock-api-key")
        )

    def test_stale_review_hash_cannot_overwrite(self):
        before = self.path.read_bytes()
        with self.assertRaisesRegex(ValueError, "changed-since-review"):
            CONFIG["migrate"](self.runtime, "0" * 64, False)
        self.assertEqual(self.path.read_bytes(), before)
        self.assertEqual(list(self.home.glob(".bedrock-config-*")), [])

    def test_disable_accepts_legacy_summary_without_normalizing_it(self):
        self.document["model"]["bedrock-grok"]["reasoning_summary"] = "concise"
        self.save(self.document)
        result = CONFIG["migrate"](
            self.runtime, CONFIG["fingerprint"](self.path.read_bytes()), True
        )
        self.assertEqual(result["status"], "bedrock-disabled")
        document, _ = POLICY["read_config"](self.path)
        self.assertEqual(
            document["model"]["bedrock-grok"]["reasoning_summary"], "concise"
        )
        self.assertEqual(
            document["auth_provider"]["bedrock-disabled"]["command"], "/usr/bin/false"
        )

    def test_disable_uses_failing_provider_and_legacy_policy(self):
        CONFIG["migrate"](
            self.runtime, CONFIG["fingerprint"](self.path.read_bytes()), False
        )
        result = CONFIG["migrate"](
            self.runtime, CONFIG["fingerprint"](self.path.read_bytes()), True
        )
        self.assertEqual(result["status"], "bedrock-disabled")
        doc, _ = POLICY["read_config"](self.path)
        self.assertEqual(
            doc["shell_environment_policy"], CONFIG["legacy_policy"](self.runtime)
        )
        self.assertEqual(
            doc["auth_provider"]["bedrock-disabled"]["command"], "/usr/bin/false"
        )
        self.assertTrue(
            all(
                doc["model"][alias]["auth_provider"] == "bedrock-disabled"
                for alias in POLICY["MODELS"]
            )
        )

    def test_staging_uses_build_paths_and_preserves_production(self):
        stage_root = self.root / "stage"
        stage_root.mkdir(mode=0o700)
        before = self.path.read_bytes()
        result = CONFIG["stage"](self.runtime, stage_root)
        self.assertEqual(result["status"], "staging-ready")
        self.assertEqual(self.path.read_bytes(), before)
        staged, _ = POLICY["read_config"](stage_root / "grok" / "config.toml")
        self.assertNotIn("unrelated", staged)
        self.assertEqual(
            staged["auth_provider"]["bedrock-doppler"]["command"],
            self.runtime["grok_key_helper"],
        )
        self.assertEqual(staged["ui"]["permission_mode"], "ask")
        with self.assertRaises(ValueError):
            CONFIG["stage"](self.runtime, stage_root)


if __name__ == "__main__":
    unittest.main()
