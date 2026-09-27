"""User-run, partial Grok configuration migration and isolated staging."""

import copy
import hashlib
import json
import os
import runpy
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

import tomlkit


class ConfigError(ValueError):
    """A safe migration diagnostic."""


def private_parent(path: Path) -> None:
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise ConfigError("unsafe-parent-directory")
    if stat.S_IMODE(info.st_mode) & 0o022:
        raise ConfigError("writable-parent-directory")


def fingerprint(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def legacy_policy(runtime: dict[str, Any]) -> dict[str, Any]:
    policy = copy.deepcopy(runtime["shell_policy"])
    policy["exclude"] = [
        name for name in policy["exclude"] if name != "AWS_BEARER_TOKEN_BEDROCK"
    ]
    return policy


def baseline(runtime: dict[str, Any]) -> tuple[dict[str, Any], bytes, dict[str, Any]]:
    policy = runpy.run_path(runtime["grok_policy"])
    path = Path(runtime["grok_home"]) / "config.toml"
    document, raw = policy["read_config"](path)
    if stat.S_IMODE(path.lstat().st_mode) != 0o600:
        raise ConfigError("configuration-mode-must-be-0600")
    valid_policies = (runtime["shell_policy"], legacy_policy(runtime))
    if document.get("shell_environment_policy") not in valid_policies:
        raise ConfigError("unexpected-shell-policy")
    policy["validate_models"](
        document, ("bedrock", policy["PROVIDER"], policy["DISABLED_PROVIDER"])
    )
    return document, raw, policy


def provider_table(command: str) -> Any:
    table = tomlkit.table()
    table.update(command=command, args=[], token_ttl_secs=300, timeout_secs=30)
    return table


def updated_document(
    runtime: dict[str, Any], raw: bytes, policy: dict[str, Any], *, disable: bool
) -> Any:
    document = tomlkit.parse(raw.decode("utf-8"))
    provider = policy["DISABLED_PROVIDER"] if disable else policy["PROVIDER"]
    command = (
        runtime["false_binary"]
        if disable
        else str(Path(runtime["grok_home"]) / "bin" / "bedrock-api-key")
    )
    if "auth_provider" not in document:
        document["auth_provider"] = tomlkit.table()
    document["auth_provider"][provider] = provider_table(command)
    for alias in policy["MODELS"]:
        document["model"][alias]["auth_provider"] = provider
    if not disable:
        document["model"]["bedrock-grok"]["reasoning_summary"] = "none"
    document["shell_environment_policy"] = (
        legacy_policy(runtime) if disable else runtime["shell_policy"]
    )
    return document


def darwin_attributes(path: Path) -> dict[str, bytes]:
    command = ["/usr/bin/xattr"]
    listing = subprocess.check_output(
        command + [str(path)], stderr=subprocess.DEVNULL, timeout=5
    )
    result = {}
    for name in listing.decode("utf-8").splitlines():
        if not name or name.startswith("-"):
            raise ConfigError("unsupported-extended-attribute-name")
        value = subprocess.check_output(
            command + ["-px", name, str(path)], stderr=subprocess.DEVNULL, timeout=5
        )
        result[name] = bytes.fromhex(value.decode("ascii"))
    return result


def extended_attributes(path: Path) -> dict[str, bytes]:
    if sys.platform == "darwin":
        return darwin_attributes(path)
    list_attributes = getattr(os, "listxattr", None)
    get_attribute = getattr(os, "getxattr", None)
    if not callable(list_attributes) or not callable(get_attribute):
        raise ConfigError("extended-attributes-unavailable")
    return {name: get_attribute(path, name) for name in list_attributes(path)}


def access_control(path: Path) -> bytes:
    if sys.platform != "darwin":
        return b""
    result = subprocess.run(
        ["/bin/ls", "-lde", str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=True,
        timeout=5,
    )
    return b"\n".join(result.stdout.splitlines()[1:])


def metadata(path: Path) -> tuple[Any, ...]:
    info = path.lstat()
    return (
        stat.S_IMODE(info.st_mode),
        info.st_uid,
        info.st_gid,
        extended_attributes(path),
        access_control(path),
    )


def replace_config(path: Path, old: bytes, new: bytes, policy: dict[str, Any]) -> None:
    private_parent(path.parent)
    expected = metadata(path)
    fd, name = tempfile.mkstemp(prefix=".bedrock-config-", dir=path.parent)
    os.close(fd)
    temporary = Path(name)
    try:
        preserve = "-p" if sys.platform == "darwin" else "--preserve=all"
        subprocess.run(
            ["/bin/cp", preserve, str(path), str(temporary)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
            timeout=5,
        )
        with temporary.open("wb") as stream:
            stream.write(new)
            stream.flush()
            os.fsync(stream.fileno())
        if metadata(temporary) != expected:
            raise ConfigError("configuration-metadata-not-preserved")
        _, current = policy["read_config"](path)
        if current != old or metadata(path) != expected:
            raise ConfigError("configuration-changed-concurrently")
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def migrate(
    runtime: dict[str, Any], expected_hash: str, disable: bool
) -> dict[str, Any]:
    before, raw, policy = baseline(runtime)
    if fingerprint(raw) != expected_hash:
        raise ConfigError("configuration-changed-since-review")
    updated = updated_document(runtime, raw, policy, disable=disable)
    new = tomlkit.dumps(updated).encode("utf-8")
    replace_config(Path(runtime["grok_home"]) / "config.toml", raw, new, policy)
    return {
        "status": "bedrock-disabled" if disable else "bedrock-published",
        "before_sha256": fingerprint(raw),
        "after_sha256": fingerprint(new),
        "previous_providers": {
            alias: before["model"][alias]["auth_provider"] for alias in policy["MODELS"]
        },
        "previous_shell_policy": before["shell_environment_policy"],
        "restart_required": True,
    }


def new_private_file(path: Path, content: bytes) -> None:
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(content)


def stage(runtime: dict[str, Any], root: Path) -> dict[str, Any]:
    private_parent(root)
    if stat.S_IMODE(root.lstat().st_mode) != 0o700 or any(root.iterdir()):
        raise ConfigError("staging-directory-must-be-empty-and-0700")
    before, raw, policy = baseline(runtime)
    home = root / "grok"
    home.mkdir(mode=0o700)
    document = tomlkit.document()
    models = tomlkit.table()
    for alias in policy["MODELS"]:
        models[alias] = copy.deepcopy(before["model"][alias])
        models[alias]["auth_provider"] = policy["PROVIDER"]
    models["bedrock-grok"]["reasoning_summary"] = "none"
    document["model"] = models
    defaults = before.get("models", {})
    inherited = {
        key: copy.deepcopy(defaults[key])
        for key in policy["GLOBAL_MODEL_DEFAULTS"]
        if key in defaults
    }
    if inherited:
        document["models"] = inherited
    document["auth_provider"] = {
        policy["PROVIDER"]: provider_table(runtime["grok_key_helper"])
    }
    document["shell_environment_policy"] = runtime["shell_policy"]
    document["ui"] = {"permission_mode": "ask", "yolo": False}
    new_private_file(home / "config.toml", tomlkit.dumps(document).encode("utf-8"))
    policy["check_config"](
        home / "config.toml", runtime["shell_policy"], runtime["grok_key_helper"]
    )
    _, after = policy["read_config"](Path(runtime["grok_home"]) / "config.toml")
    if after != raw:
        raise ConfigError("production-configuration-changed-during-staging")
    manifest = {
        "grok_home": str(home),
        "grok_binary": runtime["grok_binary"],
        "grok_key_helper": runtime["grok_key_helper"],
        "claude_launcher": runtime["claude_launcher"],
        "claude_overlay": runtime["claude_overlay"],
        "empty_aws_config": runtime["empty_aws_config"],
        "empty_aws_credentials": runtime["empty_aws_credentials"],
        "production_config_sha256": fingerprint(raw),
        "models": list(policy["MODELS"]),
    }
    new_private_file(root / "manifest.json", json.dumps(manifest, indent=2).encode())
    return {"status": "staging-ready", "manifest": str(root / "manifest.json")}


def main(arguments: list[str]) -> dict[str, Any]:
    if len(arguments) < 2:
        raise ConfigError("usage-runtime-check-stage-publish-disable")
    config_path, action, *rest = arguments
    runtime = json.loads(Path(config_path).read_text())
    if action == "check" and not rest:
        document, raw, policy = baseline(runtime)
        return {
            "status": "configuration-reviewed",
            "sha256": fingerprint(raw),
            "providers": {
                alias: document["model"][alias]["auth_provider"]
                for alias in policy["MODELS"]
            },
        }
    if action == "stage" and len(rest) == 1:
        return stage(runtime, Path(rest[0]).absolute())
    if (
        action in ("publish", "disable")
        and len(rest) == 2
        and rest[0] == "--expected-sha256"
    ):
        return migrate(runtime, rest[1], disable=action == "disable")
    raise ConfigError("invalid-invocation")


if __name__ == "__main__":
    try:
        print(json.dumps(main(sys.argv[1:])))
    except KeyboardInterrupt:
        print('{"status":"cancelled"}', file=sys.stderr)
        raise SystemExit(130) from None
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        print('{"status":"configuration-operation-failed"}', file=sys.stderr)
        raise SystemExit(1) from None
