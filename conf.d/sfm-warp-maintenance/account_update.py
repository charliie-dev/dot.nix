#!/usr/bin/env python3
"""User-installed Cloudflare account maintenance; never upgrades SFM or wgcf."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import platform
import plistlib
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

LABEL = "local.sfm-warp-account-update"
INTERVAL = 43200
WGCF_URL = (
    "https://github.com/ViRb3/wgcf/releases/download/v2.3.0/wgcf_2.3.0_darwin_arm64"
)
WGCF_SHA256 = "852d7fc7b74a5f9dca54c7cbd49068689aead71fe8f42f4af74eb9429cf87642"


class UpdateError(Exception):
    """A public error code containing no account data."""


def state_directory() -> Path:
    base = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
    return base / "sfm-warp-maintenance"


def private_directory(path: Path) -> None:
    if path.is_symlink():
        raise UpdateError("state_directory_is_symlink")
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.stat().st_uid != os.getuid():
        raise UpdateError("state_directory_owner_mismatch")
    path.chmod(0o700)


def save_state(path: Path, state: dict) -> None:
    descriptor, temporary = tempfile.mkstemp(prefix="account-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as output:
            json.dump(state, output)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def online() -> bool:
    result = subprocess.run(
        [
            "/usr/bin/curl",
            "-q",
            "--noproxy",
            "*",
            "--head",
            "--fail",
            "--silent",
            "--connect-timeout",
            "3",
            "--max-time",
            "8",
            "https://1.1.1.1",
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=10,
        check=False,
    )
    return result.returncode == 0


def update_account(binary: Path, account: Path, directory: Path, now: float) -> dict:
    state_file = directory / "account-update.json"
    if state_file.is_symlink():
        raise UpdateError("account_update_state_is_symlink")
    state: dict = json.loads(state_file.read_text()) if state_file.exists() else {}
    if not isinstance(state, dict):
        raise UpdateError("account_update_state_invalid")
    last_success = state.get("last_success", 0)
    if type(last_success) not in (int, float) or last_success < 0:
        raise UpdateError("account_update_state_invalid")
    if (directory / "paused").exists():
        return {"status": "paused"}
    if last_success and 0 <= now - last_success < INTERVAL:
        return {"status": "not_due"}
    if not online():
        return {"status": "offline"}
    if (directory / "paused").exists():
        return {"status": "paused"}
    environment = {
        key: value for key, value in os.environ.items() if not key.startswith("WGCF_")
    }
    try:
        result = subprocess.run(
            [str(binary), "--config", str(account), "update"],
            cwd=account.parent,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=90,
            check=False,
        )
        status = "updated" if result.returncode == 0 else "update_failed"
    except subprocess.TimeoutExpired:
        status = "update_timeout"
    state.update(last_attempt=now, status=status)
    if status == "updated":
        state["last_success"] = now
    save_state(state_file, state)
    return {"status": status}


def run(binary: Path, account: Path) -> dict:
    directory = state_directory()
    private_directory(directory)
    descriptor = os.open(
        directory / "account-update.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600
    )
    with os.fdopen(descriptor, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return {"status": "already_running"}
        return update_account(binary, account, directory, time.time())


def install_binary(directory: Path) -> Path:
    binary = directory / "wgcf-2.3.0"
    if binary.exists():
        if (
            binary.is_symlink()
            or hashlib.sha256(binary.read_bytes()).hexdigest() != WGCF_SHA256
        ):
            raise UpdateError("existing_wgcf_binary_differs")
        return binary
    with urllib.request.urlopen(WGCF_URL, timeout=30) as response:
        data = response.read(64 * 1024 * 1024 + 1)
    if hashlib.sha256(data).hexdigest() != WGCF_SHA256:
        raise UpdateError("wgcf_digest_mismatch")
    descriptor = os.open(binary, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o700)
    with os.fdopen(descriptor, "wb") as output:
        output.write(data)
    return binary


def launch_agent(binary: Path, account: Path) -> dict:
    return {
        "Label": LABEL,
        "ProgramArguments": [
            "/opt/homebrew/bin/python3",
            "-IS",
            str(Path(__file__).absolute()),
            "run",
            "--binary",
            str(binary),
            "--account",
            str(account),
        ],
        "EnvironmentVariables": {"XDG_STATE_HOME": str(state_directory().parent)},
        "StartInterval": INTERVAL,
        "RunAtLoad": True,
        "ProcessType": "Background",
        "StandardOutPath": "/dev/null",
        "StandardErrorPath": "/dev/null",
    }


def require_job_unloaded() -> str:
    domain = f"gui/{os.getuid()}"
    loaded = subprocess.run(
        ["/bin/launchctl", "print", f"{domain}/{LABEL}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=10,
        check=False,
    )
    if loaded.returncode == 0:
        raise UpdateError("job_already_loaded_unload_before_reinstall")
    return domain


def install(account: Path) -> dict:
    if sys.platform != "darwin" or platform.machine() != "arm64":
        raise UpdateError("installer_requires_apple_silicon_macos")
    if not Path("/opt/homebrew/bin/python3").is_file():
        raise UpdateError("homebrew_python3_required")
    if not sys.stdin.isatty():
        raise UpdateError("install_requires_your_interactive_terminal")
    print("將啟用每 12 小時的 wgcf 帳號更新；首次載入會立即執行。")
    print("wgcf 會使用指定帳號檔，可能更新 Cloudflare 帳號／裝置資料及本機帳號檔。")
    if input("確認在你的獨立終端啟用？輸入 INSTALL：") != "INSTALL":
        return {"status": "cancelled"}
    domain = require_job_unloaded()
    if not account.is_file():
        raise UpdateError("account_file_missing")
    data_home = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share")))
    directory = data_home / "sfm-warp-maintenance"
    private_directory(directory)
    binary = install_binary(directory)
    path = Path.home() / "Library/LaunchAgents" / f"{LABEL}.plist"
    content = launch_agent(binary, account)
    if path.exists() and plistlib.loads(path.read_bytes()) != content:
        raise UpdateError("existing_launch_agent_differs")
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(descriptor, "wb") as output:
            plistlib.dump(content, output)
    subprocess.run(
        ["/bin/launchctl", "bootstrap", domain, str(path)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=10,
        check=True,
    )
    return {"status": "installed", "interval_seconds": INTERVAL}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("install", "run"))
    parser.add_argument(
        "--account",
        type=Path,
        default=Path.home() / ".config/sfm-warp/wgcf-account.toml",
    )
    parser.add_argument("--binary", type=Path)
    args = parser.parse_args()
    account = args.account.expanduser().absolute()
    if args.command == "install":
        result = install(account)
    else:
        if args.binary is None or not args.binary.is_absolute():
            raise UpdateError("absolute_wgcf_binary_path_required")
        result = run(args.binary, account)
    print(json.dumps(result))
    return 1 if result["status"] in ("update_failed", "update_timeout") else 0


if __name__ == "__main__":
    os.umask(0o077)
    try:
        sys.exit(main())
    except (UpdateError, OSError, ValueError, subprocess.SubprocessError) as error:
        code = str(error) if isinstance(error, UpdateError) else type(error).__name__
        print(json.dumps({"status": "error", "error": code}), file=sys.stderr)
        sys.exit(1)
