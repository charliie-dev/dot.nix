#!/usr/bin/env python3
"""Compare reserved encodings with an isolated sing-box process."""

from __future__ import annotations

import argparse
import base64
import copy
import fcntl
import hashlib
import ipaddress
import json
import os
import signal
import socket
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
from collections.abc import Iterator
from contextlib import ExitStack, contextmanager
from pathlib import Path

VERSION = "1.14.2"
ARCHIVE_URL = (
    "https://github.com/SagerNet/sing-box/releases/download/v1.14.2/"
    "sing-box-1.14.2-darwin-arm64.tar.gz"
)
ARCHIVE_SHA256 = "925c5382eca8492b0150f868a6db20b18290a38700e621724b3703fd453e032d"
TRACE_URL = "https://1.1.1.1/cdn-cgi/trace"
PUBLIC_PEER = "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
# Public synthetic fixture; never used with a remote WireGuard peer.
FIXTURE_KEY = base64.b64encode(bytes([1]) * 32).decode()


class ProbeError(Exception):
    """An error code that is safe to include in the public report."""


def reserved_bytes(value: object) -> bytes:
    if isinstance(value, str):
        try:
            result = base64.b64decode(value, validate=True)
        except ValueError:
            raise ProbeError("invalid_reserved_encoding") from None
    elif isinstance(value, list) and all(type(item) is int for item in value):
        try:
            result = bytes(value)
        except ValueError:
            raise ProbeError("invalid_reserved_encoding") from None
    else:
        raise ProbeError("invalid_reserved_encoding")
    if len(result) != 3:
        raise ProbeError("reserved_must_contain_three_bytes")
    return result


def write_config(path: Path, value: dict) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as output:
        json.dump(value, output)


def checked_command(arguments: list[str]) -> None:
    result = subprocess.run(
        arguments,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=20,
        check=False,
    )
    if result.returncode:
        raise ProbeError("sing_box_command_failed")


def download_binary(directory: Path) -> Path:
    archive = directory / "sing-box.tar.gz"
    with urllib.request.urlopen(ARCHIVE_URL, timeout=30) as response:
        data = response.read(100 * 1024 * 1024 + 1)
    if hashlib.sha256(data).hexdigest() != ARCHIVE_SHA256:
        raise ProbeError("binary_digest_mismatch")
    archive.write_bytes(data)
    with tarfile.open(archive) as package:
        member = package.getmember(f"sing-box-{VERSION}-darwin-arm64/sing-box")
        source = package.extractfile(member)
        if source is None or not member.isfile():
            raise ProbeError("binary_archive_invalid")
        with source:
            data = source.read()
    binary = directory / "sing-box"
    binary.write_bytes(data)
    binary.chmod(0o700)
    return binary


def free_tcp_port() -> int:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def proxy_config(endpoint: dict, port: int) -> dict:
    return {
        "log": {"level": "error"},
        "dns": {"servers": [{"type": "local", "tag": "local"}]},
        "endpoints": [endpoint],
        "inbounds": [{"type": "mixed", "listen": "127.0.0.1", "listen_port": port}],
        "outbounds": [],
        "route": {"auto_detect_interface": True, "final": endpoint["tag"]},
    }


def fixture_endpoint(port: int) -> dict:
    return {
        "type": "wireguard",
        "tag": "warp",
        "system": False,
        "mtu": 1280,
        "address": ["172.16.0.2/32"],
        "private_key": FIXTURE_KEY,
        "bind_interface": "lo0",
        "peers": [
            {
                "address": "127.0.0.1",
                "port": port,
                "public_key": PUBLIC_PEER,
                "allowed_ips": ["0.0.0.0/0"],
                "reserved": [201, 87, 19],
            }
        ],
    }


def prepare_pair(binary: Path, directory: Path, config: dict) -> dict[str, Path]:
    seed = copy.deepcopy(config)
    peer = seed["endpoints"][0]["peers"][0]
    expected = reserved_bytes(peer["reserved"])
    peer["reserved"] = list(expected)
    paths = {name: directory / f"{name}.json" for name in ("array", "formatted")}
    write_config(paths["formatted"], seed)
    checked_command([str(binary), "format", "-w", "-c", str(paths["formatted"])])
    formatted = json.loads(paths["formatted"].read_text())
    value = formatted["endpoints"][0]["peers"][0]["reserved"]
    if not isinstance(value, str) or reserved_bytes(value) != expected:
        raise ProbeError("formatter_reserved_mismatch")
    # Derive both variants from formatted output to isolate omitted default fields.
    array = copy.deepcopy(formatted)
    array["endpoints"][0]["peers"][0]["reserved"] = list(expected)
    write_config(paths["array"], array)
    for path in paths.values():
        checked_command([str(binary), "check", "-c", str(path)])
    return paths


def start_proxy(binary: Path, config: Path) -> subprocess.Popen:
    return subprocess.Popen(
        [str(binary), "run", "-c", str(config)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def signal_proxy(process: subprocess.Popen, sig: int) -> None:
    try:
        os.killpg(process.pid, sig)
    except ProcessLookupError:
        pass


def stop_proxy(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    signal_proxy(process, signal.SIGTERM)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        signal_proxy(process, signal.SIGKILL)
        process.wait(timeout=5)


def interrupted(_signal: int, _frame: object) -> None:
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, signal.SIG_IGN)
    raise ProbeError("interrupted")


def install_signal_handlers() -> None:
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, interrupted)


def connect_proxy(process: subprocess.Popen, port: int) -> socket.socket:
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline and process.poll() is None:
        try:
            return socket.create_connection(("127.0.0.1", port), timeout=2)
        except OSError:
            time.sleep(0.05)
    raise ProbeError("proxy_did_not_start")


def loopback_trial(
    binary: Path, config: Path, port: int, receiver: socket.socket
) -> str:
    process = start_proxy(binary, config)
    try:
        with connect_proxy(process, port) as client:
            client.sendall(b"\x05\x01\x00")
            if client.recv(2) != b"\x05\x00":
                raise ProbeError("socks_negotiation_failed")
            client.sendall(b"\x05\x01\x00\x01\x01\x01\x01\x01\x01\xbb")
            packet, _ = receiver.recvfrom(2048)
        if len(packet) != 148 or packet[0] != 1:
            raise ProbeError("unexpected_handshake_packet")
        return packet[:4].hex()
    finally:
        stop_proxy(process)


def loopback_round(
    binary: Path,
    directory: Path,
    receiver: socket.socket,
    name: str,
    negative_control: bool,
) -> dict:
    directory.mkdir()
    receiver.bind(("127.0.0.1", 0))
    receiver.settimeout(8)
    endpoint = fixture_endpoint(receiver.getsockname()[1])
    if negative_control:
        endpoint["peers"][0]["reserved"] = [0, 0, 0]
    port = free_tcp_port()
    paths = prepare_pair(binary, directory, proxy_config(endpoint, port))
    return {
        "encoding": name,
        "header": loopback_trial(binary, paths[name], port, receiver),
    }


def loopback(binary: Path, directory: Path, negative_control: bool = False) -> dict:
    names = ("array", "formatted", "formatted", "array")
    # Retain separate receivers so queued packets and port reuse cannot cross trials.
    with ExitStack() as stack:
        receivers = [
            stack.enter_context(socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
            for _ in names
        ]
        trials = [
            loopback_round(
                binary, directory / str(index), receiver, name, negative_control
            )
            for index, (name, receiver) in enumerate(zip(names, receivers, strict=True))
        ]
    return {
        "mode": "loopback",
        "singBoxVersion": VERSION,
        "trials": trials,
        "passed": all(trial["header"] == "01c95713" for trial in trials),
    }


def read_user_profile(path: Path) -> dict:
    profile = json.loads(path.read_text())
    if not isinstance(profile, dict):
        raise ProbeError("profile_root_invalid")
    return profile


def fixed_dial_fields(value: object, prefix: str = "") -> list[str]:
    if isinstance(value, list):
        return [
            field
            for index, item in enumerate(value)
            for field in fixed_dial_fields(item, f"{prefix}[{index}]")
        ]
    if not isinstance(value, dict):
        return []
    fields = []
    fixed = {
        "bind_interface",
        "inet4_bind_address",
        "inet6_bind_address",
        "default_interface",
        "network_type",
        "default_network_type",
    }
    for key, item in value.items():
        path = f"{prefix}.{key}" if prefix else key
        if key in fixed and item:
            fields.append(path)
        fields.extend(fixed_dial_fields(item, path))
    return fields


def audit_profile(profile: dict) -> dict:
    route = profile.get("route", {})
    rules = route.get("rules", [])
    tun = [
        inbound
        for inbound in profile.get("inbounds", [])
        if inbound.get("type") == "tun"
    ]
    exclusions = [
        network
        for inbound in tun
        for network in inbound.get("route_exclude_address", [])
    ]
    tailnet = [
        ipaddress.ip_network(value)
        for value in ("100.64.0.0/10", "fd7a:115c:a1e0::/48")
    ]
    overlap = any(
        ipaddress.ip_network(value, strict=False).overlaps(network)
        for value in exclusions
        for network in tailnet
    )
    youtube = {
        "youtube.com",
        "youtu.be",
        "youtube-nocookie.com",
        "googlevideo.com",
        "ytimg.com",
    }
    youtube_rule = any(
        rule.get("ip_version") == 4
        and rule.get("outbound") == "direct"
        and youtube <= set(rule.get("domain_suffix", []))
        for rule in rules
    )
    return {
        "mode": "audit",
        "tun_present": bool(tun),
        "auto_detect_interface": route.get("auto_detect_interface") is True,
        "fixed_dial_field_paths": fixed_dial_fields(profile),
        "default_is_warp": route.get("final") == "warp",
        "tailnet_overlaps_tun_exclusions": overlap,
        "lan_direct_rule": any(
            rule.get("ip_is_private") is True and rule.get("outbound") == "direct"
            for rule in rules
        ),
        "youtube_ipv4_direct_rule": youtube_rule,
        "https_dns_present": any(
            server.get("type") == "https"
            for server in profile.get("dns", {}).get("servers", [])
        ),
        "process_route_overrides_present": any(
            rule.get("process_path_regex") and rule.get("outbound") for rule in rules
        ),
    }


def cloudflare_endpoint(profile: dict) -> dict:
    candidates = [
        endpoint
        for endpoint in profile.get("endpoints", [])
        if endpoint.get("tag") == "warp" and endpoint.get("type") == "wireguard"
    ]
    if len(candidates) != 1 or len(candidates[0].get("peers", [])) != 1:
        raise ProbeError("expected_one_warp_endpoint_and_peer")
    source = candidates[0]
    peer = source["peers"][0]
    address = ipaddress.ip_address(peer["address"])
    allowed = (
        ipaddress.ip_network("162.159.192.0/24"),
        ipaddress.ip_network("162.159.193.0/24"),
    )
    if peer.get("public_key") != PUBLIC_PEER or not any(
        address in network for network in allowed
    ):
        raise ProbeError("expected_known_cloudflare_peer")
    fields = {"type", "tag", "mtu", "address", "private_key", "peers"}
    endpoint = {
        key: copy.deepcopy(value) for key, value in source.items() if key in fields
    }
    endpoint["system"] = False
    return endpoint


def require_test_isolation() -> None:
    base = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
    if not (base / "sfm-warp-maintenance/paused").exists():
        raise ProbeError("pause_maintenance_before_cloudflare_probe")
    result = subprocess.run(
        ["/usr/sbin/scutil", "--nc", "status", "SFM"],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    if result.stdout.splitlines()[:1] != ["Disconnected"]:
        raise ProbeError("stop_sfm_in_its_gui_before_cloudflare_probe")
    trace = subprocess.run(
        [
            "/usr/bin/curl",
            "-q",
            "--noproxy",
            "*",
            "--fail",
            "--silent",
            "--max-time",
            "10",
            "--max-filesize",
            "8192",
            TRACE_URL,
        ],
        capture_output=True,
        text=True,
        timeout=12,
        check=False,
    )
    if trace.returncode or "warp=off" not in trace.stdout.splitlines():
        raise ProbeError("direct_internet_with_other_warp_clients_off_required")


def cloudflare_trial(binary: Path, config: Path, port: int) -> dict:
    process = start_proxy(binary, config)
    try:
        connect_proxy(process, port).close()
        result = subprocess.run(
            [
                "/usr/bin/curl",
                "-q",
                "--noproxy",
                "",
                "--proxy",
                f"socks5h://127.0.0.1:{port}",
                "--fail",
                "--silent",
                "--connect-timeout",
                "5",
                "--max-time",
                "15",
                "--max-filesize",
                "8192",
                TRACE_URL,
            ],
            capture_output=True,
            text=True,
            timeout=18,
            check=False,
        )
        warp = next(
            (
                line[5:]
                for line in result.stdout.splitlines()
                if line.startswith("warp=")
            ),
            "unknown",
        )
        return {
            "passed": result.returncode == 0 and warp in ("on", "plus"),
            "curl_exit": result.returncode,
        }
    finally:
        stop_proxy(process)


def open_probe_lock(path: Path):
    descriptor = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    lock = os.fdopen(descriptor, "r+")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        lock.close()
        raise ProbeError("maintenance_in_progress_retry_after_it_finishes") from None
    except BaseException:
        lock.close()
        raise
    return lock


@contextmanager
def maintenance_locks() -> Iterator[None]:
    base = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
    directory = base / "sfm-warp-maintenance"
    if directory.is_symlink():
        raise ProbeError("maintenance_state_is_symlink")
    with ExitStack() as stack:
        for name in ("check.lock", "account-update.lock"):
            stack.enter_context(open_probe_lock(directory / name))
        yield


def cloudflare(binary: Path, directory: Path, profile: dict) -> dict:
    with maintenance_locks():
        require_test_isolation()
        port = free_tcp_port()
        paths = prepare_pair(
            binary, directory, proxy_config(cloudflare_endpoint(profile), port)
        )
        trials = [
            dict(encoding=name, **cloudflare_trial(binary, paths[name], port))
            for name in ("array", "formatted", "formatted", "array")
        ]
    return {
        "mode": "cloudflare",
        "singBoxVersion": VERSION,
        "trials": trials,
        "passed": all(trial["passed"] for trial in trials),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "mode",
        choices=("loopback", "audit", "cloudflare"),
        nargs="?",
        default="loopback",
    )
    parser.add_argument(
        "--binary", type=Path, help="Use a previously verified 1.14.2 binary"
    )
    parser.add_argument("--profile", type=Path)
    parser.add_argument(
        "--user-run",
        action="store_true",
        help="Private-profile modes are user-operated",
    )
    args = parser.parse_args()
    profile: dict = {}
    if args.mode != "loopback":
        if not args.user_run or not sys.stdin.isatty() or args.profile is None:
            raise ProbeError(
                "private_profile_modes_require_your_terminal_and_user_run_flag"
            )
        profile = read_user_profile(args.profile.expanduser())
    if args.mode == "audit":
        print(json.dumps(audit_profile(profile), indent=2))
        return 0
    with tempfile.TemporaryDirectory(
        prefix="sfm-reserved-", dir=os.environ.get("TMPDIR")
    ) as raw:
        directory = Path(raw)
        binary = args.binary or download_binary(directory)
        version = subprocess.run(
            [str(binary), "version"],
            capture_output=True,
            text=True,
            timeout=10,
            check=True,
        ).stdout.splitlines()[0]
        if version != f"sing-box version {VERSION}":
            raise ProbeError("binary_version_mismatch")
        result = (
            cloudflare(binary, directory, profile)
            if args.mode == "cloudflare"
            else loopback(binary, directory)
        )
        print(json.dumps(result, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    install_signal_handlers()
    try:
        sys.exit(main())
    except (
        ProbeError,
        OSError,
        ValueError,
        KeyError,
        subprocess.SubprocessError,
    ) as error:
        code = str(error) if isinstance(error, ProbeError) else type(error).__name__
        print(json.dumps({"passed": False, "error": code}), file=sys.stderr)
        sys.exit(1)
