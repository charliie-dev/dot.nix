"""Non-secret Grok configuration checks shared by launch and staging."""

import os
import stat
from pathlib import Path
from typing import Any

import tomllib

KEY_NAME = "AWS_BEARER_TOKEN_BEDROCK"
PROVIDER = "bedrock-doppler"
DISABLED_PROVIDER = "bedrock-disabled"
REGION = "ap-northeast-1"
RUNTIME_URL = f"https://bedrock-runtime.{REGION}.amazonaws.com"
MODELS = {
    "bedrock-grok": ("global.xai.grok-4.6", "responses", "/openai/v1"),
    "bedrock-fable-5.1": (
        "global.anthropic.claude-fable-5-1",
        "messages",
        "/anthropic/v1",
    ),
    "bedrock-opus-5.5": (
        "global.anthropic.claude-opus-5-5",
        "messages",
        "/anthropic/v1",
    ),
    "bedrock-sonnet-5": (
        "global.anthropic.claude-sonnet-5",
        "messages",
        "/anthropic/v1",
    ),
    "bedrock-haiku-5.5": (
        "global.anthropic.claude-haiku-5-5",
        "messages",
        "/anthropic/v1",
    ),
}
GLOBAL_MODEL_DEFAULTS = (
    "temperature",
    "top_p",
    "max_completion_tokens",
    "max_retries",
    "rate_limit_retry_threshold",
    "inference_idle_timeout_secs",
    "subagent_rate_limit_max_attempts",
    "stream_tool_calls",
    "default_reasoning_effort",
)
MAX_CONFIG_BYTES = 1024 * 1024


class PolicyError(ValueError):
    """A safe, fixed diagnostic suitable for a launcher."""


def read_config(path: str | Path) -> tuple[dict[str, Any], bytes]:
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        with os.fdopen(fd, "rb") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
                raise PolicyError("configuration-file-ownership-or-type")
            raw = stream.read(MAX_CONFIG_BYTES + 1)
        if len(raw) > MAX_CONFIG_BYTES:
            raise PolicyError("configuration-too-large")
        return tomllib.loads(raw.decode("utf-8")), raw
    except (OSError, UnicodeError, tomllib.TOMLDecodeError):
        raise PolicyError("configuration-unreadable-or-malformed") from None


def validate_shell_policy(document: dict[str, Any], expected: dict[str, Any]) -> None:
    policy = document.get("shell_environment_policy")
    if not isinstance(policy, dict) or policy != expected:
        raise PolicyError("shell-environment-policy-drift")
    if policy.get("ignore_default_excludes") is not True:
        raise PolicyError("shell-environment-policy-drift")


def validate_headers(model: dict[str, Any], backend: str) -> None:
    headers = model.get("extra_headers", {})
    expected = {"anthropic-version": "2023-06-01"} if backend == "messages" else {}
    if not isinstance(headers, dict) or any(
        not isinstance(key, str) for key in headers
    ):
        raise PolicyError("model-headers-drift")
    normalized = {key.lower(): value for key, value in headers.items()}
    if len(normalized) != len(headers) or normalized != expected:
        raise PolicyError("model-headers-drift")


def validate_models(
    document: dict[str, Any], providers: tuple[str, ...] = (PROVIDER,)
) -> None:
    models = document.get("model")
    if not isinstance(models, dict):
        raise PolicyError("bedrock-models-missing")
    for alias, (model_id, backend, suffix) in MODELS.items():
        model = models.get(alias)
        if not isinstance(model, dict):
            raise PolicyError("bedrock-models-missing")
        actual = (model.get("model"), model.get("api_backend"), model.get("base_url"))
        if actual != (model_id, backend, RUNTIME_URL + suffix):
            raise PolicyError("bedrock-model-routing-drift")
        if model.get("auth_provider") not in providers:
            raise PolicyError("bedrock-provider-drift")
        if "api_key" in model or "env_key" in model:
            raise PolicyError("competing-model-credential")
        if "model_provider" in model:
            raise PolicyError("model-provider-inheritance-requires-review")
        if any(
            model.get(key, {}) != {} for key in ("env_http_headers", "query_params")
        ):
            raise PolicyError("model-routing-options-require-review")
        validate_headers(model, backend)
    defaults = document.get("models", {})
    if not isinstance(defaults, dict):
        raise PolicyError("global-model-settings-malformed")
    headers = defaults.get("extra_headers", {})
    if not isinstance(headers, dict):
        raise PolicyError("global-headers-malformed")
    if headers:
        raise PolicyError("global-headers-require-review")


def validate_provider(document: dict[str, Any], command: str) -> None:
    providers = document.get("auth_provider", {})
    if not isinstance(providers, dict):
        raise PolicyError("bedrock-provider-missing")
    provider = providers.get(PROVIDER)
    expected: dict[str, Any] = {
        "command": command,
        "args": [],
        "token_ttl_secs": 300,
        "timeout_secs": 30,
    }
    if provider != expected:
        raise PolicyError("bedrock-provider-drift")


def check_config(
    path: str | Path, expected_policy: dict[str, Any], command: str
) -> dict[str, Any]:
    document, _ = read_config(path)
    validate_shell_policy(document, expected_policy)
    validate_models(document)
    validate_provider(document, command)
    if document["model"]["bedrock-grok"].get("reasoning_summary") != "none":
        raise PolicyError("bedrock-reasoning-summary-required")
    return document
