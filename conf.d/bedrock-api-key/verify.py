"""USER-RUN model smoke tests; stdout contains only an allowlisted summary."""

import argparse
import json
import os
import re
import runpy
import secrets
import signal
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

CLAUDE_MODELS = {
    "fable[1m]": "global.anthropic.claude-fable-5-1",
    "opus[1m]": "global.anthropic.claude-opus-5-5",
    "sonnet": "global.anthropic.claude-sonnet-5",
    "haiku": "global.anthropic.claude-haiku-4-5-20251001-v1:0",
}
MANUAL_GATES = (
    "native_discovery_and_counting",
    "wire_model_id_and_1m_context",
    "background_and_plugin_routes",
    "tool_hook_and_mcp_environment",
    "grok_warm_cache_and_model_switch",
    "rotation_revocation_and_existing_sessions",
    "other_provider_regression_and_rollback",
)


GROK_MODELS = {
    "bedrock-grok",
    "bedrock-fable-5.1",
    "bedrock-opus-5.5",
    "bedrock-sonnet-5",
}
KNOWN_MODEL_LABELS = (
    GROK_MODELS
    | set(CLAUDE_MODELS)
    | {"grok", "unknown"}
    | {
        profile.removeprefix(prefix)
        for profile in {*CLAUDE_MODELS.values(), "global.xai.grok-4.6"}
        for prefix in ("", "global.", "global.anthropic.", "global.xai.")
    }
)
SAFE_REASONS = {
    "runtime-required",
    "explicit-run-confirmation-required",
    "manifest-build-mismatch",
    "bedrock-reasoning-summary-required",
    "invalid-stream",
    "response-model-mismatch",
    "tool-round-trip-unverified",
    "unexpected-assistant-action",
    "unexpected-tool-call",
    "duplicate-or-empty-tool-id",
    "unexpected-user-action",
    "unexpected-tool-result",
    "fixture-result-unverified",
    "invalid-client-json",
    "client-failed",
    "client-timeout",
    "client-output-limit",
    "client-start-or-io",
    "client-output",
    "cleanup-failed",
    "model-selection",
}
DIAGNOSTIC_MARKERS = {
    "cli-arguments": (
        b"unexpected argument",
        b"unrecognized option",
        b"unrecognized argument",
        b"invalid value",
    ),
    "authentication-required": (
        b"grok login",
        b"not logged in",
        b"not authenticated",
        b"authentication required",
        b"missing api key",
    ),
    "access-denied": (b"accessdenied", b"permission denied", b"forbidden"),
    "unauthorized": (b"unauthorized", b"unrecognizedclient", b"invalidclienttoken"),
    "expired-token": (b"expiredtoken", b"expired token", b"token has expired"),
    "throttled": (b"throttling", b"too many requests", b"rate limit"),
    "validation": (b"validationexception", b"invalid model", b"model not found"),
    "request-validation": (
        b"invalid_request_error",
        b"invalidrequest",
        b"invalid request",
        b"invalid_argument",
        b"validation_error",
    ),
    "unsupported": (
        b"unsupported",
        b"not supported",
        b"not implemented",
        b"unrecognized field",
        b"unknown parameter",
        b"unknown field",
    ),
    "missing-parameter": (
        b"missing required",
        b"required parameter",
        b"required field",
    ),
    "tool-schema": (
        b"invalid tool",
        b"tool schema",
        b"function schema",
        b"invalid json schema",
    ),
    "token-limit": (
        b"context_length_exceeded",
        b"too many tokens",
        b"token limit",
        b"maximum context length",
    ),
    "network": (
        b"connection refused",
        b"connection reset",
        b"failed to connect",
        b"certificate verify failed",
    ),
    "claude-launcher": (b"claude-bedrock: ",),
    "mcp-configuration": (
        b"invalid mcp configuration",
        b"--mcp-config validation failed",
    ),
    "key-helper": (
        b"bedrock-api-key: doppler-",
        b"bedrock-api-key: invalid-key-data",
        b"claude-bedrock: bootstrap-",
        b"claude-bedrock: invalid-key",
    ),
}
DIAGNOSTIC_PARAMETERS = {
    "background",
    "frequency_penalty",
    "include",
    "input",
    "max_completion_tokens",
    "max_output_tokens",
    "max_tokens",
    "messages",
    "metadata",
    "model",
    "parallel_tool_calls",
    "presence_penalty",
    "previous_response_id",
    "reasoning",
    "reasoning.effort",
    "reasoning.summary",
    "reasoning_effort",
    "reasoning_summary",
    "response_format",
    "service_tier",
    "store",
    "stream",
    "stream_options",
    "stream_tool_calls",
    "temperature",
    "text",
    "text.format",
    "tool_choice",
    "tools",
    "top_p",
    "truncation",
    "user",
}
ERROR_PARAMETER = re.compile(
    rb"""\b(?:param(?:eter)?|field)\b["']?\s{0,16}[:=]?\s{0,16}["'`]?([a-z_][a-z0-9_.\[\]-]{0,127})(?=["'`\s,}])"""
)
HTTP_STATUS = re.compile(
    rb"\b(?:http(?:/[0-9.]+)?|status(?:_code| code|code)?)[\s\"':=]+(400|401|402|403|404|408|409|413|422|429|500|502|503|504)\b"
)


class VerificationError(ValueError):
    def __init__(
        self,
        reason: str,
        *,
        phase: str = "stream",
        returncode: int | None = None,
        diagnostics: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(reason)
        self.phase = phase
        self.returncode = returncode
        self.diagnostics = diagnostics or {}


def known_parameter(raw: bytes) -> str | None:
    name = raw.decode("ascii")
    if name in DIAGNOSTIC_PARAMETERS:
        return name
    root = name.partition(".")[0].partition("[")[0]
    return root if root in DIAGNOSTIC_PARAMETERS else None


class ClientDiagnostics:
    def __init__(self) -> None:
        self.tails = {"stdout": b"", "stderr": b""}
        self.received = {"stdout": False, "stderr": False}
        self.codes: set[str] = set()
        self.http_statuses: set[int] = set()
        self.parameters: set[str] = set()

    def observe(self, stream: str, chunk: bytes) -> None:
        if stream not in self.tails:
            return
        self.received[stream] = self.received[stream] or bool(chunk)
        sample = (self.tails[stream] + chunk).lower()
        self.codes.update(
            code
            for code, markers in DIAGNOSTIC_MARKERS.items()
            if any(marker in sample for marker in markers)
        )
        self.http_statuses.update(int(value) for value in HTTP_STATUS.findall(sample))
        unescaped = sample.replace(b'\\"', b'"').replace(b"\\'", b"'")
        self.parameters.update(
            name
            for value in ERROR_PARAMETER.findall(unescaped)
            if (name := known_parameter(value)) is not None
        )
        self.tails[stream] = sample[-512:]

    def report(self) -> dict[str, Any]:
        return {
            "codes": sorted(self.codes),
            "http_statuses": sorted(self.http_statuses),
            "parameters": sorted(self.parameters),
            "stdout_received": self.received["stdout"],
            "stderr_received": self.received["stderr"],
        }


def valid_case(client: Any, model: Any) -> bool:
    if not isinstance(model, str):
        return False
    return (
        client == "grok"
        and model in GROK_MODELS
        or client == "claude"
        and model in CLAUDE_MODELS
    )


def safe_model_label(value: Any) -> str:
    if not isinstance(value, str):
        return "unrecognized"
    if value in KNOWN_MODEL_LABELS:
        return value
    normalized = value.removesuffix("[1m]")
    return normalized if normalized in KNOWN_MODEL_LABELS else "unrecognized"


def model_identity(expected: str, reported: Any) -> dict[str, str]:
    kind = "missing" if reported is None else "non-string"
    if isinstance(reported, str):
        kind = "string"
    return {
        "expected": safe_model_label(expected),
        "reported": safe_model_label(reported),
        "reported_type": kind,
    }


def safe_diagnostics(details: Any) -> dict[str, Any]:
    if not isinstance(details, dict):
        return {}
    codes = details.get("codes", [])
    statuses = details.get("http_statuses", [])
    parameters = details.get("parameters", [])
    if not all(isinstance(value, list) for value in (codes, statuses, parameters)):
        return {}
    result: dict[str, Any] = {
        "codes": sorted(
            {
                code
                for code in codes
                if isinstance(code, str) and code in DIAGNOSTIC_MARKERS
            }
        ),
        "http_statuses": sorted(
            {
                code
                for code in statuses
                if type(code) is int
                and code
                in {
                    400,
                    401,
                    402,
                    403,
                    404,
                    408,
                    409,
                    413,
                    422,
                    429,
                    500,
                    502,
                    503,
                    504,
                }
            }
        ),
        "parameters": sorted(
            {
                name
                for name in parameters
                if isinstance(name, str) and name in DIAGNOSTIC_PARAMETERS
            }
        ),
        "stdout_received": details.get("stdout_received") is True,
        "stderr_received": details.get("stderr_received") is True,
    }
    identity = details.get("model_identity")
    if isinstance(identity, dict):
        kind = identity.get("reported_type")
        result["model_identity"] = {
            "expected": safe_model_label(identity.get("expected")),
            "reported": safe_model_label(identity.get("reported")),
            "reported_type": kind
            if isinstance(kind, str) and kind in {"missing", "string", "non-string"}
            else "unrecognized",
        }
    return result


def safe_setting(
    table: dict[str, Any], key: str, allowed: tuple[str | bool, ...]
) -> str | bool:
    if key not in table:
        return "unset"
    value = table[key]
    for item in allowed:
        if type(value) is type(item) and value == item:
            return value
    return "other"


def staged_request_settings(document: Any, model: Any) -> dict[str, Any]:
    if not isinstance(document, dict) or not isinstance(model, str):
        return {}
    models = document.get("model", {})
    defaults = document.get("models", {})
    if (
        model not in GROK_MODELS
        or not isinstance(models, dict)
        or not isinstance(defaults, dict)
        or not isinstance(models.get(model), dict)
    ):
        return {}
    selected = models[model]
    return {
        "reasoning_summary": safe_setting(
            selected, "reasoning_summary", ("none", "auto", "concise", "detailed")
        ),
        "model_stream_tool_calls": safe_setting(
            selected, "stream_tool_calls", (True, False)
        ),
        "global_stream_tool_calls": safe_setting(
            defaults, "stream_tool_calls", (True, False)
        ),
    }


def failure_report(
    error: Exception,
    *,
    client: str | None = None,
    model: str | None = None,
    completed: list[dict[str, Any]] | None = None,
    phase: str = "preflight",
    staged_config: Any = None,
) -> dict[str, Any]:
    reason = str(error) if str(error) in SAFE_REASONS else "unclassified"
    selected_phase = getattr(error, "phase", phase)
    if not isinstance(selected_phase, str) or selected_phase not in {
        "preflight",
        "client",
        "stream",
    }:
        selected_phase = "unclassified"
    result: dict[str, Any] = {
        "status": "cleanup-failed"
        if reason == "cleanup-failed"
        else "verification-failed",
        "reason": reason,
        "phase": selected_phase,
        "deployment_ready": False,
    }
    if valid_case(client, model):
        result.update(client=client, model=model)
    if client == "grok" and (settings := staged_request_settings(staged_config, model)):
        result["staged_request_settings"] = settings
    returncode = getattr(error, "returncode", None)
    if type(returncode) is int and -128 <= returncode <= 255:
        result["returncode"] = returncode
    result["diagnostics"] = safe_diagnostics(getattr(error, "diagnostics", {}))
    result["completed_models"] = [
        {"client": item["client"], "model": item["model"]}
        for item in completed or []
        if isinstance(item, dict) and valid_case(item.get("client"), item.get("model"))
    ]
    return result


def selected_cases(
    client: str, model: str | None, policy: dict[str, Any]
) -> list[tuple[str, str]]:
    if model is not None:
        allowed = policy["MODELS"] if client == "grok" else CLAUDE_MODELS
        if client == "all" or model not in allowed:
            raise VerificationError("model-selection", phase="preflight")
        return [(client, model)]
    cases = (
        [("grok", name) for name in policy["MODELS"]]
        if client in ("all", "grok")
        else []
    )
    if client in ("all", "claude"):
        cases.extend(("claude", name) for name in CLAUDE_MODELS)
    return cases


def content_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(
            block.get("text", "")
            for block in content
            if isinstance(block, dict) and block.get("type") == "text"
        )
    return ""


def tool_matches(block: dict[str, Any], fixture: Path, tool: str) -> bool:
    if block.get("name") != tool or not isinstance(block.get("input"), dict):
        return False
    arguments = block["input"]
    paths = [
        arguments[key]
        for key in ("path", "target_file", "file_path")
        if key in arguments
    ]
    if not paths:
        return False
    for value in paths:
        if not isinstance(value, str):
            return False
        path = Path(value)
        if not path.is_absolute():
            # The client runs in the directory containing the fixture.
            path = fixture.parent / path
        if path.resolve() != fixture:
            return False
    return True


def inspect_stream(
    raw: bytes,
    fixture: Path,
    nonce: str,
    tool: str,
    profile: str,
    *,
    client_alias: str | None = None,
) -> dict[str, Any]:
    qualified = profile.removeprefix("global.")
    identities = {
        profile,
        qualified,
        qualified.removeprefix("anthropic.").removeprefix("xai."),
    }
    calls: set[str] = set()
    completed: set[str] = set()
    final_seen = False
    result_seen = False
    terminal_count = 0
    last_kind = None
    context_windows: set[int] = set()
    model_id_seen = False
    catalog_key_seen = False
    for line in raw.splitlines():
        event = json.loads(line)
        if not isinstance(event, dict):
            raise VerificationError("invalid-stream")
        kind = event.get("type")
        last_kind = kind
        message = event.get("message", {})
        blocks: Any = message.get("content", []) if isinstance(message, dict) else []
        if kind == "assistant":
            if not isinstance(message, dict):
                raise VerificationError("invalid-stream")
            reported = message.get("model")
            matches_id = (
                isinstance(reported, str)
                and reported.removesuffix("[1m]") in identities
            )
            matches_alias = (
                isinstance(client_alias, str)
                and client_alias in GROK_MODELS
                and isinstance(reported, str)
                and reported.removesuffix("[1m]") == client_alias
            )
            if not matches_id and not matches_alias:
                raise VerificationError(
                    "response-model-mismatch",
                    diagnostics={"model_identity": model_identity(profile, reported)},
                )
            model_id_seen = model_id_seen or matches_id
            catalog_key_seen = catalog_key_seen or (matches_alias and not matches_id)
            final_seen = (
                inspect_assistant(blocks, fixture, nonce, tool, calls, completed)
                or final_seen
            )
        if kind == "user":
            inspect_results(blocks, nonce, calls, completed)
        if kind == "result":
            terminal_count += 1
            result_seen = (
                event.get("subtype") == "success"
                and event.get("is_error") is False
                and isinstance(event.get("result"), str)
                and nonce in event["result"]
            )
            context_windows.update(reported_windows(event.get("modelUsage", {})))
    if (
        not calls
        or calls != completed
        or not final_seen
        or not result_seen
        or terminal_count != 1
        or last_kind != "result"
    ):
        raise VerificationError("tool-round-trip-unverified")
    identity_source = "model-id"
    if catalog_key_seen:
        identity_source = "mixed" if model_id_seen else "catalog-key"
    return {
        "tool_round_trip": True,
        "client_model_label_verified": True,
        "response_model_verified": model_id_seen and not catalog_key_seen,
        "model_identity_source": identity_source,
        "reported_context_windows": sorted(context_windows),
        "wire_model_id_verified": False,
    }


def inspect_assistant(
    blocks: Any,
    fixture: Path,
    nonce: str,
    tool: str,
    calls: set[str],
    completed: set[str],
) -> bool:
    if not isinstance(blocks, list):
        raise VerificationError("invalid-stream")
    final_seen = bool(completed) and nonce in content_text(blocks)
    for block in blocks:
        if not isinstance(block, dict) or block.get("type") not in {
            "text",
            "thinking",
            "redacted_thinking",
            "tool_use",
        }:
            raise VerificationError("unexpected-assistant-action")
        if block.get("type") != "tool_use":
            continue
        if not tool_matches(block, fixture, tool) or not isinstance(
            block.get("id"), str
        ):
            raise VerificationError("unexpected-tool-call")
        if not block["id"] or block["id"] in calls:
            raise VerificationError("duplicate-or-empty-tool-id")
        calls.add(block["id"])
    return final_seen


def inspect_results(
    blocks: Any, nonce: str, calls: set[str], completed: set[str]
) -> None:
    if not isinstance(blocks, list):
        raise VerificationError("invalid-stream")
    for block in blocks:
        if not isinstance(block, dict) or block.get("type") not in {
            "text",
            "tool_result",
        }:
            raise VerificationError("unexpected-user-action")
        if block.get("type") != "tool_result":
            continue
        if block.get("tool_use_id") not in calls or block.get("is_error"):
            raise VerificationError("unexpected-tool-result")
        if nonce not in content_text(block.get("content")):
            raise VerificationError("fixture-result-unverified")
        completed.add(block["tool_use_id"])


def reported_windows(usage: Any) -> set[int]:
    if not isinstance(usage, dict):
        return set()
    return {
        row["contextWindow"]
        for row in usage.values()
        if isinstance(row, dict)
        and type(row.get("contextWindow")) is int
        and 0 < row["contextWindow"] <= 10000000
    }


def capture(
    command: list[str],
    env: dict[str, str],
    cwd: Path,
    control_path: str,
    *,
    diagnostics: ClientDiagnostics | None = None,
) -> bytes:
    control = runpy.run_path(control_path)
    if diagnostics is None:
        diagnostics = ClientDiagnostics()
    try:
        return control["capture"](
            command,
            env,
            cwd=cwd,
            timeout=180,
            limit=16 * 1024 * 1024,
            observe=diagnostics.observe,
        )
    except ValueError as error:
        reason = (
            "cleanup-failed" if str(error) == "cleanup-failed" else f"client-{error}"
        )
        if reason not in SAFE_REASONS:
            reason = "client-failed"
        code = getattr(error, "returncode", None)
        raise VerificationError(
            reason,
            phase="client",
            returncode=code if type(code) is int else None,
            diagnostics=diagnostics.report(),
        ) from None


def test_model(
    client: str, model: str, runtime: dict[str, Any], stage: dict[str, Any]
) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(
        prefix="bedrock-verify-", dir=os.environ.get("TMPDIR", "/tmp")
    ) as directory:
        root = Path(directory).resolve()
        fixture = root / "fixture.txt"
        nonce = secrets.token_hex(16)
        fixture.write_text(nonce)
        env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("AWS_", "ANTHROPIC_", "AZURE_"))
            and key
            not in (
                "GROK_CONFIG",
                "GROK_CONFIG_PATH",
                "INPUT_AWS_BEARER_TOKEN_BEDROCK",
                "OPENAI_API_KEY",
                "XAI_API_KEY",
                "GROK_CODE_XAI_API_KEY",
            )
        }
        env.update(
            AWS_CONFIG_FILE=runtime["empty_aws_config"],
            AWS_SHARED_CREDENTIALS_FILE=runtime["empty_aws_credentials"],
            AWS_EC2_METADATA_DISABLED="true",
        )
        prompt = f"Use the file-reading tool to read only {fixture}, then quote its entire contents. Do not call any other tool."
        if client == "grok":
            env["GROK_HOME"] = stage["grok_home"]
            command = [
                runtime["grok_binary"],
                "--model",
                model,
                "--tools",
                "read_file",
                "--deny",
                "MCPTool",
                "--max-turns",
                "4",
                "--output-format",
                "streaming-messages-json",
                "-p",
                prompt,
            ]
        else:
            command = [
                runtime["claude_launcher"],
                "--model",
                model,
                "--tools",
                "Read",
                "--allowedTools",
                f"Read({fixture})",
                "--disallowedTools",
                "mcp__*",
                "--strict-mcp-config",
                "--mcp-config",
                '{"mcpServers":{}}',
                "--max-turns",
                "4",
                "--output-format",
                "stream-json",
                "--verbose",
                "-p",
                prompt,
            ]
        expected = (
            runpy.run_path(runtime["grok_policy"])["MODELS"][model][0]
            if client == "grok"
            else CLAUDE_MODELS[model]
        )
        diagnostics = ClientDiagnostics()
        raw = capture(
            command, env, root, runtime["process_control"], diagnostics=diagnostics
        )
        try:
            result = inspect_stream(
                raw,
                fixture,
                nonce,
                "read_file" if client == "grok" else "Read",
                expected,
                client_alias=model if client == "grok" else None,
            )
        except (UnicodeError, json.JSONDecodeError, RecursionError):
            raise VerificationError(
                "invalid-client-json", returncode=0, diagnostics=diagnostics.report()
            ) from None
        except VerificationError as error:
            error.returncode = 0
            error.diagnostics = {
                **safe_diagnostics(error.diagnostics),
                **diagnostics.report(),
            }
            raise
        except (
            OSError,
            ValueError,
            KeyError,
            TypeError,
            AttributeError,
            subprocess.SubprocessError,
        ):
            raise VerificationError(
                "unclassified", returncode=0, diagnostics=diagnostics.report()
            ) from None
    return {"client": client, "model": model, **result}


def main(arguments: list[str]) -> int:
    if not arguments:
        raise VerificationError("runtime-required", phase="preflight")
    runtime = json.loads(Path(arguments[0]).read_text())
    parser = argparse.ArgumentParser(
        description="USER-RUN only: eight billable client smoke prompts, with read-only tool allowlists and redacted output."
    )
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--client", choices=("all", "grok", "claude"), default="all")
    parser.add_argument(
        "--model", help="Run one configured model; requires --client grok or claude"
    )
    parser.add_argument(
        "--run",
        action="store_true",
        help="Confirm model charges, trusted fixture use, and user-reviewed plugin/hook isolation",
    )
    options = parser.parse_args(arguments[1:])
    if not options.run:
        raise VerificationError("explicit-run-confirmation-required", phase="preflight")
    stage = json.loads(options.manifest.read_text())
    if (
        stage.get("grok_key_helper") != runtime["grok_key_helper"]
        or stage.get("claude_launcher") != runtime["claude_launcher"]
    ):
        raise VerificationError("manifest-build-mismatch", phase="preflight")
    policy = runpy.run_path(runtime["grok_policy"])
    staged_config = policy["check_config"](
        Path(stage["grok_home"]) / "config.toml",
        runtime["shell_policy"],
        runtime["grok_key_helper"],
    )
    results: list[dict[str, Any]] = []
    for client, model in selected_cases(options.client, options.model, policy):
        try:
            results.append(test_model(client, model, runtime, stage))
        except (
            OSError,
            ValueError,
            KeyError,
            TypeError,
            AttributeError,
            subprocess.SubprocessError,
        ) as error:
            print(
                json.dumps(
                    failure_report(
                        error,
                        client=client,
                        model=model,
                        completed=results,
                        staged_config=staged_config,
                    )
                ),
                file=sys.stderr,
            )
            return 1
        if results[-1].get("response_model_verified") is not True:
            break
    complete = bool(results) and all(
        result.get("response_model_verified") is True for result in results
    )
    print(
        json.dumps(
            {
                "status": "base-smoke-passed" if complete else "base-smoke-partial",
                "results": results,
                "manual_gates_remaining": MANUAL_GATES,
                "deployment_ready": False,
            }
        )
    )
    return 0 if complete else 2


def interrupted(_number: int, _frame: Any) -> None:
    raise KeyboardInterrupt


if __name__ == "__main__":
    for number in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(number, interrupted)
    try:
        raise SystemExit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        print('{"status":"cancelled","deployment_ready":false}', file=sys.stderr)
        raise SystemExit(130) from None
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        AttributeError,
        subprocess.SubprocessError,
    ) as error:
        print(json.dumps(failure_report(error)), file=sys.stderr)
        raise SystemExit(1) from None
