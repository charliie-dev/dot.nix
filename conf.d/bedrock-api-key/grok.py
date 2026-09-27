"""Doppler-backed Grok credential helper and direct Bedrock launcher."""

import json
import os
import runpy
import signal
import sys
from pathlib import Path
from typing import Any

KEY_NAME = "AWS_BEARER_TOKEN_BEDROCK"
MAX_KEY_BYTES = 65536
HELPER_TIMEOUT = 20
CORE_ENVIRONMENT = (
    "LANG",
    "LC_ALL",
    "LC_CTYPE",
    "LOGNAME",
    "USER",
    "TMPDIR",
    "TEMP",
    "TMP",
)
AUTH_PREFIXES = ("AWS_", "ANTHROPIC_", "AZURE_", "DOPPLER_", "GROK_AUTH_PROVIDER_")
CONFIG_FLAGS = ("--config", "--config-file", "--config-path", "--grok-home")


class HelperError(ValueError):
    """A safe diagnostic with no child output or credential values."""


def validate_key(value: str) -> str:
    if (
        not value
        or value.startswith(("{", "[", '"'))
        or len(value.encode("utf-8")) > MAX_KEY_BYTES
    ):
        raise HelperError("invalid-key-data")
    if any(ord(char) < 33 or ord(char) > 126 for char in value):
        raise HelperError("invalid-key-data")
    return value


def helper_environment(runtime: dict[str, Any]) -> dict[str, str]:
    result = {name: os.environ[name] for name in CORE_ENVIRONMENT if name in os.environ}
    result.update(HOME=runtime["home"], PATH=runtime["helper_path"])
    return result


def read_key(runtime: dict[str, Any], config_path: str) -> str:
    command = [
        runtime["doppler_run"],
        "bedrock-grok-token",
        "--",
        runtime["python"],
        "-I",
        str(Path(__file__).resolve()),
        config_path,
        "emit",
    ]
    control = runpy.run_path(runtime["process_control"])
    try:
        output = control["capture"](
            command,
            helper_environment(runtime),
            timeout=HELPER_TIMEOUT,
            limit=MAX_KEY_BYTES,
        )
    except ValueError as error:
        code = {
            "timeout": "doppler-timeout",
            "start-or-io": "doppler-start-failed",
            "output-limit": "invalid-key-data",
            "cleanup-failed": "doppler-cleanup-failed",
        }.get(str(error), "doppler-retrieval-failed")
        raise HelperError(code) from None
    try:
        return validate_key(output.decode("ascii"))
    except UnicodeError:
        raise HelperError("invalid-key-data") from None


def model_arguments(arguments: list[str], allowed: set[str]) -> list[str]:
    selected: str | None = None
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        if argument == "--":
            break
        if any(
            argument == flag or argument.startswith(flag + "=") for flag in CONFIG_FLAGS
        ):
            raise HelperError("caller-configuration-override")
        value, consumed = model_argument(arguments, index)
        if value is not None and (selected is not None or value not in allowed):
            raise HelperError("invalid-or-duplicate-bedrock-model")
        selected = value if value is not None else selected
        index += consumed
    return (
        arguments
        if selected is not None
        else ["--model", "bedrock-opus-5.5", *arguments]
    )


def model_argument(arguments: list[str], index: int) -> tuple[str | None, int]:
    argument = arguments[index]
    if argument in ("-m", "--model"):
        if index + 1 >= len(arguments):
            raise HelperError("missing-model-value")
        return arguments[index + 1], 2
    if argument.startswith("--model="):
        return argument.removeprefix("--model="), 1
    if argument.startswith("-m") and not argument.startswith("--"):
        return argument[2:], 1
    return None, 1


def launch_environment(runtime: dict[str, Any]) -> dict[str, str]:
    sensitive = set(runtime["sensitive_names"])
    sensitive.update(
        (
            "GROK_CONFIG",
            "GROK_CONFIG_PATH",
            "CLAUDE_CODE_OAUTH_TOKEN",
            "INPUT_AWS_BEARER_TOKEN_BEDROCK",
            "OPENAI_API_KEY",
            "XAI_API_KEY",
            "GROK_CODE_XAI_API_KEY",
        )
    )
    result = {
        name: value
        for name, value in os.environ.items()
        if name not in sensitive and not name.startswith(AUTH_PREFIXES)
    }
    result["GROK_HOME"] = runtime["grok_home"]
    return result


def launch(runtime: dict[str, Any], arguments: list[str]) -> None:
    policy = runpy.run_path(runtime["grok_policy"])
    try:
        policy["check_config"](
            Path(runtime["grok_home"]) / "config.toml",
            runtime["shell_policy"],
            str(Path(runtime["grok_home"]) / "bin" / "bedrock-api-key"),
        )
    except ValueError:
        raise HelperError("grok-configuration-preflight-failed") from None
    arguments = model_arguments(arguments, set(policy["MODELS"]))
    binary = runtime["grok_binary"]
    os.execvpe(binary, [binary, *arguments], launch_environment(runtime))


def interrupted(_signum: int, _frame: Any) -> None:
    raise KeyboardInterrupt


def main(arguments: list[str]) -> int:
    if len(arguments) < 2:
        raise HelperError("invalid-invocation")
    config_path, action, *rest = arguments
    runtime = json.loads(Path(config_path).read_text())
    if action == "launch":
        launch(runtime, rest)
        return 0
    if rest or action not in ("key", "emit"):
        raise HelperError("invalid-invocation")
    key = (
        read_key(runtime, config_path)
        if action == "key"
        else validate_key(os.environ.get(KEY_NAME, ""))
    )
    sys.stdout.write(key)
    return 0


if __name__ == "__main__":
    for number in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(number, interrupted)
    try:
        raise SystemExit(main(sys.argv[1:]))
    except HelperError as error:
        print(f"bedrock-api-key: {error}", file=sys.stderr)
        raise SystemExit(1) from None
    except KeyboardInterrupt:
        print("bedrock-api-key: cancelled", file=sys.stderr)
        raise SystemExit(130) from None
    except (OSError, KeyError, TypeError, ValueError):
        print("bedrock-api-key: invalid-runtime-configuration", file=sys.stderr)
        raise SystemExit(1) from None
