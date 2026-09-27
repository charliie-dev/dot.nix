"""USER-RUN Claude preflight and launch; importing this module reads no settings."""

import hashlib
import json
import os
import plistlib
import pwd
import runpy
import shutil
import stat
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, NoReturn

KEY_NAME = "AWS_BEARER_TOKEN_BEDROCK"
SERVICE_TIER_KEY = "ANTHROPIC_BEDROCK_SERVICE_TIER"
SERVICE_TIERS = frozenset({"", "default", "priority", "flex", "reserved"})
MAX_KEY_BYTES = 65536
MAX_SETTINGS_BYTES = 8 * 1024 * 1024
BOOTSTRAP_TIMEOUT = 20.0
STORE_ROOT = Path("/nix/store")
SCRIPT_PATH = Path(__file__).resolve()
# Reviewed macOS ARM64 native builds, keyed by exact binary digest.
REVIEWED_CLIENTS = {
    "fcfd837103965c64de34a6b9b94370d77a347ea71819715a27d5f0ef01775ea4": "2.1.282",
    "d8cb1e5c79684cc12a8bfc813e3a2073406921b6245744b3009be3ab5651d21e": "2.1.283",
}
MODEL_PINS = {
    "FABLE": "global.anthropic.claude-fable-5-1[1m]",
    "OPUS": "global.anthropic.claude-opus-5-5[1m]",
    "SONNET": "global.anthropic.claude-sonnet-5",
    "HAIKU": "global.anthropic.claude-haiku-4-5-20251001-v1:0",
}
FIXED_ENV = {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_REGION": "ap-northeast-1",
    "AWS_DEFAULT_REGION": "ap-northeast-1",
    "CLAUDE_CODE_SUBPROCESS_ENV_SCRUB": "1",
    **{f"ANTHROPIC_DEFAULT_{name}_MODEL": value for name, value in MODEL_PINS.items()},
}
NEUTRALIZABLE = {
    "ANTHROPIC_API_KEY",
    "ANTHROPIC_AUTH_TOKEN",
    "ANTHROPIC_AWS_API_KEY",
    "GOOGLE_APPLICATION_CREDENTIALS",
    "ANTHROPIC_VERTEX_PROJECT_ID",
    "CLOUD_ML_REGION",
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_SESSION_TOKEN",
    "AWS_SECURITY_TOKEN",
    "ANTHROPIC_BASE_URL",
    "ANTHROPIC_BEDROCK_BASE_URL",
    "ANTHROPIC_CUSTOM_HEADERS",
    "ANTHROPIC_FOUNDRY_API_KEY",
    "ANTHROPIC_FOUNDRY_AUTH_TOKEN",
    "ANTHROPIC_FOUNDRY_BASE_URL",
    "ANTHROPIC_FOUNDRY_RESOURCE",
    "ANTHROPIC_VERTEX_BASE_URL",
    "CLAUDE_CODE_OAUTH_TOKEN",
    "CLAUDE_CODE_USE_VERTEX",
    "CLAUDE_CODE_USE_FOUNDRY",
    "CLAUDE_CODE_USE_ANTHROPIC_AWS",
    "CLAUDE_CODE_USE_ANTHROPIC_GOOGLE_CLOUD",
    "CLAUDE_CODE_USE_MANTLE",
    "CLAUDE_CODE_USE_GATEWAY",
}
AUTH_HELPERS = {
    "apiKeyHelper",
    "awsAuthRefresh",
    "awsCredentialExport",
    "gcpAuthRefresh",
}
SKIP_AUTH = {"CLAUDE_CODE_SKIP_BEDROCK_AUTH", "SKIP_BEDROCK_AUTH"}
FORBIDDEN_MODELS = {
    "ANTHROPIC_MODEL",
    "ANTHROPIC_DEFAULT_MODEL",
    "ANTHROPIC_SMALL_FAST_MODEL",
    "ANTHROPIC_SMALL_FAST_MODEL_AWS_REGION",
    "CLAUDE_CODE_SUBAGENT_MODEL",
    "CLAUDE_CODE_SUBAGENT_MODEL_FORCE",
    "CLAUDE_CODE_AUTO_MODE_MODEL",
    "CLAUDE_CODE_BG_CLASSIFIER_MODEL",
    "CLAUDE_CODE_MODEL_CATALOG",
    "CLAUDE_CODE_MODEL_CATALOG_URL",
    "CLAUDE_CODE_DISABLE_1M_CONTEXT",
    "CLAUDE_CODE_NO_MODEL_FALLBACK",
    "FALLBACK_FOR_ALL_PRIMARY_MODELS",
}
HOST_ENV = {
    "CLAUDE_CODE_CLIENT_DATA_URL",
    "CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST",
    "CLAUDE_CODE_SDK_HAS_HOST_AUTH_REFRESH",
    "CLAUDE_CODE_USE_COWORK_PLUGINS",
    "CLAUDE_CODE_MANAGED_SETTINGS_PATH",
    "CLAUDE_CODE_REMOTE_SETTINGS_PATH",
    "CLAUDE_CODE_SIMPLE",
    "CLAUDE_CODE_SAFE_MODE",
    "CLAUDE_CODE_SESSION_ACCESS_TOKEN",
    "CLAUDE_CODE_SESSION_KIND",
    "CLAUDE_CODE_BRIDGE_CHILD_MACHINE_SETTINGS",
    "CLAUDE_CODE_MOCK_REMOTE_SETTINGS",
    "CLAUDE_CODE_IDE_HOST_OVERRIDE",
    "CLAUDE_CODE_WORKSPACE_HOST_PATHS",
    "CLAUDE_PTY_HOST_EXEC",
}
HOST_PREFIXES = (
    "CLAUDE_CODE_HOST_",
    "CLAUDE_CODE_REMOTE",
    "CLAUDE_CODE_POLICY_",
    "CLAUDE_CODE_BRIDGE_",
    "CLAUDE_CODE_RESUME_",
    "CLAUDE_BG_",
    "CLAUDE_BRIDGE_",
)
AUTH_PREFIXES = (
    "AWS_",
    "ANTHROPIC_",
    "AZURE_",
    "OPENAI_",
    "DOPPLER_",
    "__DOPPLER_RUN_",
    "GROK_AUTH_PROVIDER_",
    "CLAUDE_CODE_OAUTH_",
    "CLAUDE_CODE_USE_",
    "CLAUDE_CODE_API_",
    "CLAUDE_CODE_GATEWAY_",
    "CLAUDE_CODE_FEDERATION_",
    "CLAUDE_CODE_CUSTOM_OAUTH_",
    "CLAUDE_CODE_SKIP_",
    "CLAUDE_GATEWAY_",
    "VERTEX_REGION_",
)
OTHER_AUTH = {
    "CLAUDE_CODE_HFI_BEARER_TOKEN",
    "CLAUDE_CODE_WEBSOCKET_AUTH_TOKEN",
    "GOOGLE_APPLICATION_CREDENTIALS",
    "GOOGLE_API_KEY",
    "GCLOUD_PROJECT",
    "GOOGLE_CLOUD_PROJECT",
    "CLOUD_ML_REGION",
    "CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE",
    "AGENT_PROXY_AUTH_TOKEN",
    "TSTRUCT_TOKEN",
    "CF_API_TOKEN",
    "CLOUDFLARE_API_TOKEN",
    "CF_TOKEN_CHARLIIE_RO",
    "CF_TOKEN_ANMO_RO",
}
STARTUP_ENV = {
    "BASH_ENV",
    "ENV",
    "BASHOPTS",
    "SHELLOPTS",
    "NODE_OPTIONS",
    "BUN_OPTIONS",
    "CLAUDE_CODE_EXTRA_BODY",
    "CLAUDE_CODE_EXECPATH",
    "CLAUDE_SECURESTORAGE_CONFIG_DIR",
    "_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL",
    "GIT_DIR",
    "GIT_COMMON_DIR",
    "GIT_WORK_TREE",
    "GIT_CEILING_DIRECTORIES",
    "GIT_DISCOVERY_ACROSS_FILESYSTEM",
    "DO_NOT_TRACK",
}
STARTUP_PREFIXES = ("PYTHON", "DYLD_", "LD_", "BASH_FUNC_", "GIT_CONFIG_", "BUN_ENV_")
EMPTY_AWS_KEYS = {
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_SESSION_TOKEN",
    "AWS_SECURITY_TOKEN",
}
CONFIG_FLAGS = {
    "--client-data-url",
    "--settings",
    "--setting-sources",
    "--managed-settings",
    "--config",
    "--config-file",
    "--config-path",
    "--profile",
    "--claude-home",
    "--project-config-root",
    "--cwd",
    "--add-dir",
    "--bare",
    "--safe-mode",
    "--sdk-url",
    "--input-format",
    "--await-initialize",
    "--await-claim",
    "--attach-serve",
    "--deep-link-cwd-b64",
    "--deep-link-origin",
    "--deep-link-repo",
    "--handle-uri",
    "--session-mirror",
    "--on-branch",
    "--worktree",
    "--teleport",
    "--remote",
    "--remote-control",
    "--rc",
    "--cloud",
    "--background",
    "--bg",
    "--forward-home-settings",
    "--environment",
    "--host",
    "--provider",
    "--base-url",
    "--endpoint",
    "--api-key",
    "--internal-emit",
    "--internal-exec",
    "--bedrock-preflight",
}
TRANSPORT_ENV = {
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "ALL_PROXY",
    "NO_PROXY",
    "http_proxy",
    "https_proxy",
    "all_proxy",
    "no_proxy",
    "SSL_CERT_FILE",
    "SSL_CERT_DIR",
}
BOOTSTRAP_ENV = {
    "HOME",
    "PATH",
    "LANG",
    "LC_ALL",
    "LC_CTYPE",
    "USER",
    "LOGNAME",
    "TMPDIR",
    "TEMP",
    "TMP",
} | TRANSPORT_ENV
ERRORS = {
    "arguments": "caller settings, host/source overrides, or unsupported model arguments are not allowed",
    "runtime": "rebuild the Home Manager launcher with its public store runtime and artifacts",
    "unsupported-client": "use a reviewed Claude Code 2.1.282 or 2.1.283 macOS ARM64 native build; other builds require source review and a launcher digest update",
    "unsupported-platform": "this launcher is reviewed for standalone macOS; use an approved entry on other platforms",
    "settings-unreadable": "repair the indicated settings source's readability, regular-file type, or size, then retry",
    "settings-format": "repair the indicated settings source as an unambiguous JSON object or JSON-compatible plist",
    "persisted-bearer": "USER-RUN: remove the bearer key from the indicated settings env, including empty entries; keep it only in Doppler",
    "skip-auth": "USER-RUN: unset Bedrock skip-auth, including empty entries, in the indicated source",
    "auth-helper": "USER-RUN: remove credential helpers from the indicated source before using API-key-only mode",
    "host-source": "a host or dynamic managed source cannot be evaluated here; use its approved launcher, or have the administrator supply a reviewed static policy; do not bypass enforced policy",
    "routing-conflict": "USER-RUN: reconcile provider, endpoint, credential-source, or environment overrides in the indicated source with the Bedrock overlay",
    "model-conflict": "USER-RUN: reconcile model overrides in the indicated source with the pinned Bedrock models and Sonnet fallback",
    "service-tier": "USER-RUN: set ANTHROPIC_BEDROCK_SERVICE_TIER to default, priority, flex, reserved, or empty",
    "overlay": "rebuild the nonsecret Bedrock overlay with the required pins, neutralizers, display names, and scrub enabled",
    "project-layout": "use the canonical checkout with ordinary .git metadata, or review this repository layout before enabling the launcher",
    "settings-changed": "settings or the client changed during bootstrap; review the change and restart",
    "bootstrap-start": "Doppler bootstrap could not start; USER-RUN: check the fixed Home Manager runner",
    "bootstrap-failed": "Doppler bootstrap failed; USER-RUN: check the fixed profile and existing authentication in a separate shell",
    "bootstrap-timeout": "Doppler bootstrap timed out; no credential fallback was attempted",
    "bootstrap-cleanup": "bootstrap cleanup encountered an error; USER-RUN: inspect owned child processes before retrying",
    "bootstrap-output": "Doppler bootstrap returned unexpected output; no output was forwarded",
    "invalid-key": "Doppler did not deliver one bounded, nonempty printable bearer value",
    "emitter-boundary": "the fixed emitter received an unexpected credential environment",
    "cancelled": "cancelled; bootstrap children were terminated",
    "client-exec": "the reviewed Claude executable could not start; no fallback was attempted",
    "unexpected": "startup failed safely; no settings values or child diagnostics were forwarded",
}


class LaunchError(Exception):
    def __init__(self, code: str, source: str = "launcher"):
        self.code = code
        self.source = source
        super().__init__(code)


@dataclass(frozen=True)
class Source:
    label: str
    path: Path
    managed: bool = False
    plist: bool = False


@dataclass(frozen=True)
class Layout:
    cwd: Path
    home: Path
    managed_dir: Path
    plists: tuple[Source, ...]
    root: Path = Path("/")


@dataclass
class Prepared:
    binary: Path
    environment: dict[str, str]
    snapshot: tuple[tuple[str, str], ...]
    report: dict[str, Any]


def fail(code: str, source: str = "launcher") -> NoReturn:
    raise LaunchError(code, source)


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError
        result[key] = value
    return result


class UniquePlistDict(dict[str, Any]):
    def __setitem__(self, key: str, value: Any) -> None:
        if key in self:
            raise ValueError
        super().__setitem__(key, value)


def invalid_constant(_value: str) -> NoReturn:
    raise ValueError


def read_descriptor(fd: int, limit: int, source: str) -> bytes:
    with os.fdopen(fd, "rb") as handle:
        if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
            fail("settings-unreadable", source)
        data = handle.read(limit + 1)
    if len(data) > limit:
        fail("settings-unreadable", source)
    return data


def read_bytes(
    path: Path, source: str, optional: bool = False, limit: int = MAX_SETTINGS_BYTES
) -> bytes | None:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        return read_descriptor(fd, limit, source)
    except FileNotFoundError:
        if optional and not path.is_symlink():
            return None
    except OSError:
        pass
    fail("settings-unreadable", source)


def document(data: bytes, source: str, plist: bool = False) -> dict[str, Any]:
    try:
        value = (
            plistlib.loads(data, dict_type=UniquePlistDict)
            if plist
            else json.loads(
                data.decode("utf-8-sig"),
                object_pairs_hook=unique_object,
                parse_constant=invalid_constant,
            )
        )
        # plutil rejects plist data/date values instead of turning them into settings.
        json.dumps(value, allow_nan=False)
    except (
        ValueError,
        TypeError,
        UnicodeError,
        OverflowError,
        plistlib.InvalidFileException,
    ):
        fail("settings-format", source)
    if not isinstance(value, dict):
        fail("settings-format", source)
    return value


def store_file(value: Any, executable: bool = False) -> Path:
    if not isinstance(value, str) or not value or "\x00" in value:
        fail("runtime")
    path = Path(value)
    if (
        not path.is_absolute()
        or not path.is_relative_to(STORE_ROOT)
        or ".." in path.parts
    ):
        fail("runtime")
    try:
        resolved = path.resolve(strict=True)
        info = resolved.stat() if executable else path.lstat()
    except OSError:
        fail("runtime")
    if not resolved.is_relative_to(STORE_ROOT):
        fail("runtime")
    if not stat.S_ISREG(info.st_mode) or (executable and not os.access(path, os.X_OK)):
        fail("runtime")
    return path


def load_runtime(path: str) -> dict[str, Any]:
    location = store_file(path)
    data = read_bytes(location, "runtime")
    if data is None:
        fail("runtime")
    runtime = document(data, "runtime")
    for name in ("python", "doppler_run"):
        store_file(runtime.get(name), executable=True)
    for name in (
        "claude_overlay",
        "empty_aws_config",
        "empty_aws_credentials",
        "process_control",
    ):
        store_file(runtime.get(name))
    home = runtime.get("claude_home")
    if (
        not isinstance(home, str)
        or not home
        or "\x00" in home
        or not Path(home).is_absolute()
    ):
        fail("runtime")
    binary = runtime.get("claude_binary", "claude")
    if not isinstance(binary, str) or not binary or "\x00" in binary:
        fail("runtime")
    runtime["claude_binary"] = binary
    return runtime


def fixed_environment(runtime: dict[str, Any]) -> dict[str, str]:
    return {
        **FIXED_ENV,
        "CLAUDE_CONFIG_DIR": runtime["claude_home"],
        "AWS_CONFIG_FILE": runtime["empty_aws_config"],
        "AWS_SHARED_CREDENTIALS_FILE": runtime["empty_aws_credentials"],
        "AWS_EC2_METADATA_DISABLED": "true",
    }


def settings_env(doc: dict[str, Any], source: str) -> dict[str, str]:
    env = doc.get("env", {})
    if not isinstance(env, dict) or any(
        not isinstance(k, str) or not isinstance(v, str) for k, v in env.items()
    ):
        fail("settings-format", source)
    return env


def validate_overlay(runtime: dict[str, Any]) -> dict[str, str]:
    for name in ("empty_aws_config", "empty_aws_credentials"):
        if read_bytes(store_file(runtime[name]), "runtime", limit=0) != b"":
            fail("runtime")
    raw = read_bytes(store_file(runtime["claude_overlay"]), "overlay")
    overlay = document(raw if raw is not None else b"", "overlay")
    if (
        set(overlay) != {"env", "model", "fallbackModel"}
        or overlay["model"] != "opus[1m]"
        or overlay["fallbackModel"] != ["sonnet"]
    ):
        fail("overlay", "overlay")
    env = settings_env(overlay, "overlay")
    if any(env.get(key) != value for key, value in FIXED_ENV.items()):
        fail("overlay", "overlay")
    for key in (
        "CLAUDE_CODE_USE_VERTEX",
        "CLAUDE_CODE_USE_FOUNDRY",
        "ANTHROPIC_FOUNDRY_API_KEY",
    ):
        if env.get(key) != "":
            fail("overlay", "overlay")
    names = {f"ANTHROPIC_DEFAULT_{name}_MODEL_NAME" for name in MODEL_PINS}
    if any(not env.get(key) or "bedrock" not in env[key].casefold() for key in names):
        fail("overlay", "overlay")
    expected = fixed_environment(runtime)
    for key, value in env.items():
        valid = (
            key in names
            or (key in expected and value == expected[key])
            or (key in NEUTRALIZABLE and value == "")
        )
        if not valid:
            fail("overlay", "overlay")
    return env


def is_host_env(key: str) -> bool:
    return key in HOST_ENV or key.startswith(HOST_PREFIXES)


def validate_service_tier(value: str, source: str) -> None:
    if value not in SERVICE_TIERS:
        fail("service-tier", source)


def validate_ambient(env: dict[str, str]) -> None:
    if SERVICE_TIER_KEY in env:
        validate_service_tier(env[SERVICE_TIER_KEY], "environment")
    keys = {key.upper() for key in env}
    if keys & SKIP_AUTH:
        fail("skip-auth", "environment")
    if any(is_host_env(key) for key in keys):
        fail("host-source", "environment")
    if AUTH_HELPERS.intersection(env):
        fail("auth-helper", "environment")


def sanitize_environment(
    env: dict[str, str], runtime: dict[str, Any], overlay: dict[str, str], home: Path
) -> dict[str, str]:
    remove = (
        STARTUP_ENV
        | OTHER_AUTH
        | FORBIDDEN_MODELS
        | SKIP_AUTH
        | AUTH_HELPERS
        | {"CLAUDE_CONFIG_DIR"}
    )
    clean = {
        key: value
        for key, value in env.items()
        if key not in remove
        and not key.upper().startswith(AUTH_PREFIXES + STARTUP_PREFIXES)
    }
    if SERVICE_TIER_KEY in env:
        validate_service_tier(env[SERVICE_TIER_KEY], "environment")
        clean[SERVICE_TIER_KEY] = env[SERVICE_TIER_KEY]
    clean.update(overlay)
    clean.update(fixed_environment(runtime))
    clean["HOME"] = str(home)
    return clean


def validate_env_entry(
    key: str, value: str, overlay: dict[str, str], fixed: dict[str, str], source: Source
) -> None:
    upper = key.upper()
    if upper == KEY_NAME:
        fail("persisted-bearer", source.label)
    if upper in SKIP_AUTH:
        fail("skip-auth", source.label)
    if is_host_env(upper):
        fail("host-source", source.label)
    if upper in FORBIDDEN_MODELS:
        fail("model-conflict", source.label)
    if key in AUTH_HELPERS:
        fail("auth-helper", source.label)
    if key == SERVICE_TIER_KEY:
        validate_service_tier(value, source.label)
        return
    expected = {**overlay, **fixed}
    if key in expected and (
        not source.managed and key in overlay or value == expected[key]
    ):
        return
    if key in EMPTY_AWS_KEYS and value == "":
        return
    routing = upper.startswith(
        AUTH_PREFIXES + STARTUP_PREFIXES
    ) or upper in OTHER_AUTH | STARTUP_ENV | set(expected)
    if routing or upper == "CLAUDE_CONFIG_DIR":
        fail("routing-conflict", source.label)


def validate_settings(
    doc: dict[str, Any], source: Source, overlay: dict[str, str], fixed: dict[str, str]
) -> None:
    if AUTH_HELPERS.intersection(doc):
        fail("auth-helper", source.label)
    dynamic = {
        "policyHelper",
        "policyHelpers",
        "forceRemoteSettingsRefresh",
        "forceLoginMethod",
        "forceLoginOrgUUID",
        "forceLoginGatewayUrl",
    }
    if dynamic.intersection(doc):
        fail("host-source", source.label)
    if source.managed and {"availableModelsMatch", "deniedModels"}.intersection(doc):
        fail("model-conflict", source.label)
    if {
        "modelOverrides",
        "modelPicker",
        "availableModels",
        "enforceAvailableModels",
    }.intersection(doc):
        fail("model-conflict", source.label)
    if source.managed and any(
        key in doc and doc[key] != value
        for key, value in {"model": "opus[1m]", "fallbackModel": ["sonnet"]}.items()
    ):
        fail("model-conflict", source.label)
    for key, value in settings_env(doc, source.label).items():
        validate_env_entry(key, value, overlay, fixed, source)


def host_layout() -> Layout:
    if sys.platform != "darwin":
        fail("unsupported-platform")
    user = pwd.getpwuid(os.getuid())
    base = Path("/Library/Managed Preferences")
    name = "com.anthropic.claudecode.plist"
    return Layout(
        Path.cwd().resolve(),
        Path(user.pw_dir),
        Path("/Library/Application Support/ClaudeCode"),
        (
            Source("managed-plist-user", base / user.pw_name / name, True, True),
            Source("managed-plist-device", base / name, True, True),
        ),
    )


def ancestors(path: Path, root: Path) -> list[Path]:
    resolved = path.resolve()
    if not resolved.is_relative_to(root):
        fail("project-layout", "project")
    return [
        resolved,
        *[parent for parent in resolved.parents if parent.is_relative_to(root)],
    ]


def git_common_root(directory: Path) -> Path | None:
    marker = directory / ".git"
    if marker.is_dir() or not os.path.lexists(marker):
        return None
    raw = read_bytes(marker, "project", limit=4096)
    try:
        text = (raw or b"").decode("utf-8").strip()
        if not text.startswith("gitdir: ") or "\n" in text:
            fail("project-layout", "project")
        gitdir = (directory / text[8:]).resolve()
        common = read_bytes(gitdir / "commondir", "project", optional=True, limit=4096)
        target = (
            (gitdir / common.decode("utf-8").strip()).resolve()
            if common is not None
            else gitdir
        )
    except (UnicodeError, ValueError):
        fail("project-layout", "project")
    if target.name != ".git":
        fail("project-layout", "project")
    return target.parent


def project_sources(layout: Layout) -> list[Source]:
    directories = ancestors(layout.cwd, layout.root)
    extra: list[Path] = []
    for directory in directories:
        common = git_common_root(directory)
        if common is not None:
            extra.extend(ancestors(common, layout.root))
    result: list[Source] = []
    for directory in dict.fromkeys(directories + extra):
        result.extend(
            (
                Source("project", directory / ".claude/settings.json"),
                Source("local", directory / ".claude/settings.local.json"),
            )
        )
    return result


def managed_dropins(directory: Path) -> list[Source]:
    try:
        entries = sorted(directory.iterdir())
    except FileNotFoundError:
        if directory.is_symlink():
            fail("settings-unreadable", "managed-dropin")
        return []
    except OSError:
        fail("settings-unreadable", "managed-dropin")
    if len(entries) > 512:
        fail("settings-unreadable", "managed-dropin")
    return [
        Source("managed-dropin", path, True)
        for path in entries
        if path.name.endswith(".json") and not path.name.startswith(".")
    ]


def discover_sources(runtime: dict[str, Any], layout: Layout) -> list[Source]:
    home = Path(runtime["claude_home"])
    return [
        Source("user", home / "settings.json"),
        Source("legacy-global", home / ".config.json"),
        Source("legacy-global", home / ".claude.json"),
        *project_sources(layout),
        *layout.plists,
        Source("managed-json", layout.managed_dir / "managed-settings.json", True),
        *managed_dropins(layout.managed_dir / "managed-settings.d"),
        Source("server-managed", home / "remote-settings.json", True),
    ]


def reviewed_client(
    runtime: dict[str, Any], env: dict[str, str]
) -> tuple[Path, str, str]:
    candidate = shutil.which(runtime["claude_binary"], path=env.get("PATH", os.defpath))
    if candidate is None:
        fail("unsupported-client")
    path = Path(candidate).resolve()
    try:
        if not stat.S_ISREG(path.stat().st_mode):
            fail("unsupported-client")
        with path.open("rb") as handle:
            digest = hashlib.file_digest(handle, "sha256").hexdigest()
    except OSError:
        fail("unsupported-client")
    version = REVIEWED_CLIENTS.get(digest)
    if version is None:
        fail("unsupported-client")
    return path, version, digest


def validate_arguments(arguments: list[str]) -> tuple[str, list[str]]:
    model = "opus[1m]"
    fallback = ["sonnet"]
    seen: set[str] = set()
    allowed = {"fable[1m]", "opus[1m]", "sonnet", "haiku", *MODEL_PINS.values()}
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        if argument == "--":
            break
        flag, separator, inline = argument.partition("=")
        if flag in CONFIG_FLAGS or (
            argument.startswith(("-w", "-b")) and not argument.startswith("--")
        ):
            fail("arguments", "arguments")
        if flag not in {"--model", "--fallback-model"}:
            index += 1
            continue
        value = (
            inline
            if separator
            else (arguments[index + 1] if index + 1 < len(arguments) else "")
        )
        permitted = allowed if flag == "--model" else {"sonnet", MODEL_PINS["SONNET"]}
        if flag in seen or value not in permitted:
            fail("arguments", "arguments")
        seen.add(flag)
        model = value if flag == "--model" else model
        fallback = [value] if flag == "--fallback-model" else fallback
        index += 1 if separator else 2
    return model, fallback


def preflight(
    runtime: dict[str, Any],
    arguments: list[str],
    ambient: dict[str, str],
    layout: Layout,
) -> Prepared:
    model, fallback = validate_arguments(arguments)
    validate_ambient(ambient)
    overlay = validate_overlay(runtime)
    clean = sanitize_environment(ambient, runtime, overlay, layout.home)
    binary, version, digest = reviewed_client(runtime, clean)
    snapshot = [("client", digest)]
    labels: list[str] = []
    for source in discover_sources(runtime, layout):
        raw = read_bytes(source.path, source.label, optional=True)
        if raw is None:
            continue
        validate_settings(
            document(raw, source.label, source.plist),
            source,
            overlay,
            fixed_environment(runtime),
        )
        snapshot.append((str(source.path), hashlib.sha256(raw).hexdigest()))
        labels.append(source.label)
    report = {
        "status": "ok",
        "client_version": version,
        "checked_sources": sorted(set(labels)),
        "persisted_bearer_present": False,
        "credential_helpers_present": False,
        "region": FIXED_ENV["AWS_REGION"],
        "model": model,
        "fallbackModel": fallback,
        "model_pins": MODEL_PINS,
        "scope": "trusted-host-startup-check-not-request-binding",
        "proxy_tls_requires_user_trust": True,
    }
    return Prepared(binary, clean, tuple(snapshot), report)


def validate_key(value: str) -> str:
    if (
        not value
        or value.startswith(("{", "[", '"'))
        or len(value) > MAX_KEY_BYTES
        or any(ord(char) < 33 or ord(char) > 126 for char in value)
    ):
        fail("invalid-key")
    return value


def emit_key(env: dict[str, str]) -> None:
    # macOS Python can add this nonsecret locale metadata before main.
    allowed = BOOTSTRAP_ENV | {
        KEY_NAME,
        "DOPPLER_CONFIG_DIR",
        "PWD",
        "SHLVL",
        "_",
        "__CF_USER_TEXT_ENCODING",
        "PYTHONNOUSERSITE",
    }
    # The Nix Python wrapper sets this before the isolated interpreter starts.
    if "PYTHONNOUSERSITE" in env and env["PYTHONNOUSERSITE"] != "true":
        fail("emitter-boundary")
    if set(env) - allowed:
        fail("emitter-boundary")
    sys.stdout.write(validate_key(env.get(KEY_NAME, "")))
    sys.stdout.flush()


def read_key(runtime: dict[str, Any], clean: dict[str, str]) -> str:
    command = [
        runtime["doppler_run"],
        "bedrock-claude",
        "--",
        runtime["python"],
        "-I",
        str(SCRIPT_PATH),
        "--internal-emit",
    ]
    env = {key: value for key, value in clean.items() if key in BOOTSTRAP_ENV}
    control = runpy.run_path(runtime["process_control"])
    try:
        output = control["capture"](
            command,
            env,
            timeout=BOOTSTRAP_TIMEOUT,
            limit=MAX_KEY_BYTES,
            reject_stderr=True,
        )
    except ValueError as error:
        code = {
            "timeout": "bootstrap-timeout",
            "start-or-io": "bootstrap-start",
            "output": "bootstrap-output",
            "output-limit": "bootstrap-output",
            "cleanup-failed": "bootstrap-cleanup",
        }.get(str(error), "bootstrap-failed")
        fail(code)
    try:
        return validate_key(output.decode("ascii"))
    except UnicodeError:
        fail("invalid-key")


def launch(
    runtime: dict[str, Any],
    arguments: list[str],
    ambient: dict[str, str],
    layout: Layout,
) -> None:
    prepared = preflight(runtime, arguments, ambient, layout)
    key = read_key(runtime, prepared.environment)
    checked = preflight(runtime, arguments, ambient, layout)
    if prepared.snapshot != checked.snapshot:
        fail("settings-changed")
    final = prepared.environment | {KEY_NAME: key}
    command = [
        str(prepared.binary),
        "--settings",
        runtime["claude_overlay"],
        *arguments,
    ]
    try:
        os.execve(prepared.binary, command, final)
    except OSError:
        fail("client-exec")


def main(arguments: list[str] | None = None) -> int:
    try:
        args = list(sys.argv[1:] if arguments is None else arguments)
        if args == ["--internal-emit"]:
            emit_key(dict(os.environ))
            return 0
        if not args or args[0].startswith("-"):
            fail("arguments", "arguments")
        runtime = load_runtime(args[0])
        layout = host_layout()
        if args[1:] == ["--bedrock-preflight"]:
            print(
                json.dumps(
                    preflight(runtime, [], dict(os.environ), layout).report,
                    sort_keys=True,
                )
            )
            return 0
        launch(runtime, args[1:], dict(os.environ), layout)
        return 0
    except LaunchError as error:
        print(
            f"claude-bedrock: {error.code} ({error.source}): {ERRORS[error.code]}",
            file=sys.stderr,
        )
        return 130 if error.code == "cancelled" else 1
    except KeyboardInterrupt:
        print(f"claude-bedrock: cancelled: {ERRORS['cancelled']}", file=sys.stderr)
        return 130
    except (OSError, ValueError, TypeError, KeyError, RuntimeError):
        safe_exception()
        return 1


def safe_exception(
    _type: Any = None, _value: Any = None, _traceback: Any = None
) -> None:
    print(f"claude-bedrock: unexpected: {ERRORS['unexpected']}", file=sys.stderr)


if __name__ == "__main__":
    sys.excepthook = safe_exception
    sys.exit(main())
