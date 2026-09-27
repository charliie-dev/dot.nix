"""Non-credential SFM health checks and conservative reconnect policy."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import ipaddress
import json
import math
import os
import re
import secrets
import selectors
import stat
import subprocess
import sys
import time
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import asdict, dataclass, replace
from itertools import product
from pathlib import Path
from typing import Self

FAILURE_THRESHOLD = 3
COOLDOWN = 900
NETWORK_GRACE = 60
MAX_CHECK_GAP = 180
CLOCK_TOLERANCE = 1
PROBE_BUDGET = 40
STATE_LIMIT = 4096
SCUTIL = "/usr/sbin/scutil"
CURL = "/usr/bin/curl"
TRACE = "https://1.1.1.1/cdn-cgi/trace"
GOOGLE = "https://dns.google/"
CLEAN_ENV = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"}
NETWORK_ERRORS = {5, 6, 7, 28, 52, 55, 56}
SERVICE_KEY = r"State:/Network/Service/[A-Za-z0-9._:-]{1,64}/IPv[46]"
RESULTS = {
    "never",
    "paused",
    "resumed",
    "service-unknown",
    "service-transition",
    "interfaces-unknown",
    "network-grace",
    "wake-grace",
    "healthy",
    "health-unknown",
    "underlay-offline",
    "underlay-unknown",
    "failed",
    "cooldown",
    "repair-ready",
    "restart-attempt",
    "stop-failed",
    "start-failed",
    "restarted",
}
SERVICES = {"connected", "disconnected", "connecting", "disconnecting", "unknown"}
HEALTH = {"healthy", "failed", "unknown"}
UNDERLAY = {"reachable", "offline", "unknown"}


@dataclass(frozen=True)
class Result:
    code: int | None = None
    output: bytes = b""


@dataclass(frozen=True)
class Observation:
    signature: str = ""
    interfaces: int = 0
    service: str = "unknown"
    health: str = "unknown"
    underlay: str = "unknown"
    changed: bool = False


@dataclass(frozen=True)
class State:
    last_check: float = 0
    last_tick: float = 0
    grace_until: float = 0
    last_restart: float = 0
    last_restart_tick: float = 0
    failures: int = 0
    signature: str = ""
    result: str = "never"
    service: str = "unknown"
    health: str = "unknown"
    underlay: str = "unknown"
    interfaces: int = 0


class UnsafeState(ValueError):
    pass


def drain(
    process: subprocess.Popen[bytes],
    selector: selectors.BaseSelector,
    deadline: float,
    limit: int,
) -> Result:
    assert process.stdout is not None
    output = bytearray()
    while time.monotonic() < deadline:
        remaining = max(0, deadline - time.monotonic())
        if not selector.select(remaining):
            return Result()
        chunk = os.read(process.stdout.fileno(), min(4096, limit + 1 - len(output)))
        if not chunk:
            code = process.wait(timeout=max(0, deadline - time.monotonic()))
            return Result(code, bytes(output))
        output.extend(chunk)
        if len(output) > limit:
            return Result()
    return Result()


def read_output(
    process: subprocess.Popen[bytes], deadline: float, limit: int
) -> Result:
    assert process.stdout is not None
    selector = selectors.DefaultSelector()
    try:
        selector.register(process.stdout, selectors.EVENT_READ)
        return drain(process, selector, deadline, limit)
    finally:
        selector.close()


def close_process(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is None:
        process.kill()
    process.wait()
    if process.stdout is not None:
        process.stdout.close()
    if process.stdin is not None:
        try:
            process.stdin.close()
        except OSError:
            pass


def run_command(
    arguments: list[str],
    *,
    input_data: bytes = b"",
    timeout: float = 5,
    limit: int = 8192,
    deadline: float | None = None,
) -> Result:
    end = min(
        time.monotonic() + timeout, deadline if deadline is not None else math.inf
    )
    if time.monotonic() >= end or len(input_data) > 4096:
        return Result()
    try:
        process = subprocess.Popen(
            arguments,
            stdin=subprocess.PIPE if input_data else subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=CLEAN_ENV,
        )
    except OSError:
        return Result()
    try:
        if process.stdin is not None:
            process.stdin.write(input_data)
            process.stdin.close()
        return read_output(process, end, limit)
    except (OSError, subprocess.TimeoutExpired):
        return Result()
    finally:
        close_process(process)


def service_status(deadline: float) -> str:
    result = run_command(
        [SCUTIL, "--nc", "status", "SFM"], timeout=3, deadline=deadline
    )
    first = result.output.splitlines()[:1]
    status = first[0].decode("ascii", errors="replace").lower() if first else "unknown"
    return status if result.code == 0 and status in SERVICES else "unknown"


def addresses(section: str) -> set[str]:
    array = re.search(r"(?ms)^  Addresses\s*:\s*<array>\s*\{(.*?)^  \}", section)
    values = re.findall(r"(?m)^\s*\d+\s*:\s*(\S+)\s*$", array[1] if array else "")
    parsed = set()
    for value in values:
        address = ipaddress.ip_address(value.split("%", 1)[0])
        unusable = address.is_loopback or address.is_unspecified or address.is_multicast
        if not unusable and not address.is_link_local:
            parsed.add(str(address))
    return parsed


def physical_interfaces(output: bytes) -> dict[str, tuple[str, ...]]:
    text = output.decode("ascii")
    sections = re.findall(r"(?ms)^<dictionary> \{(.*?)^\}", text)
    found: dict[str, set[str]] = {}
    for section in sections:
        # Nested route entries can name interfaces other than the service's interface.
        match = re.search(r"(?m)^  InterfaceName\s*:\s*((?:en|bridge)\d+)\s*$", section)
        if match:
            found.setdefault(match[1], set()).update(addresses(section))
    return {name: tuple(sorted(values)) for name, values in found.items() if values}


def discover(deadline: float) -> dict[str, tuple[str, ...]]:
    listing = run_command(
        [SCUTIL],
        input_data=f"list {SERVICE_KEY}\n".encode(),
        timeout=3,
        limit=32768,
        deadline=deadline,
    )
    keys = sorted(
        set(re.findall(SERVICE_KEY, listing.output.decode("ascii", errors="replace")))
    )
    if listing.code != 0 or not keys or len(keys) > 32:
        return {}
    result = run_command(
        [SCUTIL],
        input_data="".join(f"show {key}\n" for key in keys).encode(),
        timeout=3,
        limit=65536,
        deadline=deadline,
    )
    dictionaries = re.findall(rb"(?m)^<dictionary> \{$", result.output)
    if result.code != 0 or len(dictionaries) != len(keys):
        return {}
    try:
        interfaces = physical_interfaces(result.output)
    except ValueError:
        return {}
    return interfaces if len(interfaces) <= 8 else {}


def signature(interfaces: dict[str, tuple[str, ...]]) -> str:
    if not interfaces:
        return ""
    data = json.dumps(interfaces, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(data).hexdigest()


def curl_arguments(target: str) -> list[str]:
    return [
        CURL,
        "-q",
        "--noproxy",
        "*",
        "--silent",
        "--fail",
        "--ipv4",
        "--proto",
        "=https",
        "--connect-timeout",
        "2",
        "--max-time",
        "4",
        "--max-filesize",
        "8192",
        "--write-out",
        "\n%{http_code}",
        target,
    ]


def https_body(result: Result) -> bytes | None:
    body, separator, status = result.output.rpartition(b"\n")
    if result.code != 0 or not separator or status not in {b"200", b"204"}:
        return None
    return body


def trace_health(body: bytes) -> str:
    try:
        lines = body.decode("ascii").splitlines()
    except UnicodeError:
        return "unknown"
    if not lines or any(not re.fullmatch(r"[a-z_]+=[^\r\n]*", line) for line in lines):
        return "unknown"
    values = [line.removeprefix("warp=") for line in lines if line.startswith("warp=")]
    if values in [["on"], ["plus"]]:
        return "healthy"
    return "failed" if values == ["off"] else "unknown"


def warp_health(deadline: float) -> str:
    result = run_command(curl_arguments(TRACE), deadline=deadline, limit=4096)
    if result.code in NETWORK_ERRORS:
        return "failed"
    body = https_body(result)
    return trace_health(body) if body is not None else "unknown"


def underlay_probe(interface: str, target: str, deadline: float) -> str:
    arguments = curl_arguments(target) + ["--head", "--interface", f"if!{interface}"]
    if target == GOOGLE:
        arguments += ["--resolve", "dns.google:443:8.8.8.8"]
    result = run_command(arguments, deadline=deadline)
    if https_body(result) is not None:
        return "reachable"
    return "offline" if result.code in NETWORK_ERRORS else "unknown"


def underlay_health(interfaces: dict[str, tuple[str, ...]], deadline: float) -> str:
    results = []
    for interface, target in product(sorted(interfaces), (TRACE, GOOGLE)):
        result = underlay_probe(interface, target, deadline)
        if result == "reachable":
            return result
        results.append(result)
    return (
        "offline"
        if results and all(value == "offline" for value in results)
        else "unknown"
    )


def observe() -> Observation:
    deadline = time.monotonic() + PROBE_BUDGET
    service = service_status(deadline)
    if service not in {"connected", "disconnected"}:
        return Observation(service=service)
    before = discover(deadline)
    if not before:
        return Observation(service=service)
    health = warp_health(deadline)
    underlay = underlay_health(before, deadline) if health == "failed" else "unknown"
    after = discover(deadline) if underlay == "reachable" else before
    return Observation(
        signature(after),
        len(after),
        service,
        health,
        underlay,
        before != after,
    )


def check_gap(state: State, now: float, tick: float) -> bool:
    if not state.last_check:
        return False
    wall, elapsed = now - state.last_check, tick - state.last_tick
    return (
        wall < 0
        or elapsed < 0
        or wall > MAX_CHECK_GAP
        or abs(wall - elapsed) > CLOCK_TOLERANCE
    )


def cooldown_remaining(state: State, now: float, tick: float) -> float:
    if not state.last_restart:
        return 0
    # Neither a forward wall-clock jump nor suspended uptime can shorten cooldown.
    elapsed = min(now - state.last_restart, tick - state.last_restart_tick)
    return max(0, COOLDOWN - elapsed)


def transition(
    state: State,
    observation: Observation,
    now: float,
    tick: float,
    paused: bool = False,
) -> State:
    gap = check_gap(state, now, tick)
    changed = observation.signature != state.signature or observation.changed
    next_state = replace(
        state,
        last_check=now,
        last_tick=tick,
        last_restart_tick=tick if tick < state.last_tick else state.last_restart_tick,
        signature=observation.signature,
        interfaces=observation.interfaces,
        service=observation.service,
        health=observation.health,
        underlay=observation.underlay,
        grace_until=now + NETWORK_GRACE if gap or changed else state.grace_until,
        failures=0,
    )
    if paused:
        return replace(next_state, result="paused")
    if observation.service == "unknown":
        return replace(next_state, result="service-unknown")
    if observation.service not in {"connected", "disconnected"}:
        return replace(next_state, result="service-transition")
    if not observation.signature:
        return replace(next_state, result="interfaces-unknown")
    if now < next_state.grace_until:
        return replace(next_state, result="wake-grace" if gap else "network-grace")
    if observation.health == "healthy":
        return replace(next_state, result="healthy")
    if observation.health != "failed":
        return replace(next_state, result="health-unknown")
    if observation.underlay != "reachable":
        return replace(next_state, result=f"underlay-{observation.underlay}")
    failures = min(FAILURE_THRESHOLD, state.failures + 1)
    next_state = replace(next_state, failures=failures)
    if cooldown_remaining(next_state, now, tick):
        return replace(next_state, result="cooldown")
    return replace(
        next_state, result="repair-ready" if failures == FAILURE_THRESHOLD else "failed"
    )


def state_directory() -> Path:
    base = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    if not base.is_absolute():
        raise UnsafeState("relative state directory")
    return base / "sfm-warp-maintenance"


def private_file(directory: int, name: str, flags: int) -> int:
    fd = os.open(name, flags | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600, dir_fd=directory)
    info = os.fstat(fd)
    if (
        not stat.S_ISREG(info.st_mode)
        or info.st_uid != os.getuid()
        or info.st_nlink != 1
    ):
        os.close(fd)
        raise UnsafeState("unsafe state file")
    os.fchmod(fd, 0o600)
    return fd


def atomic_write(directory: int, name: str, data: bytes) -> None:
    temporary = f".{name}-{secrets.token_hex(8)}"
    fd = private_file(directory, temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, name, src_dir_fd=directory, dst_dir_fd=directory)
        os.fsync(directory)
    finally:
        try:
            os.unlink(temporary, dir_fd=directory)
        except FileNotFoundError:
            pass


def decode_state(data: bytes) -> State:
    if len(data) > STATE_LIMIT:
        raise UnsafeState("oversized state")
    values = json.loads(data)
    if not isinstance(values, dict) or set(values) != set(asdict(State())):
        raise UnsafeState("unknown state format")
    clocks = (
        "last_check",
        "last_tick",
        "grace_until",
        "last_restart",
        "last_restart_tick",
    )
    if any(type(values[key]) not in (int, float) for key in clocks):
        raise UnsafeState("invalid clock")
    if any(not math.isfinite(values[key]) or values[key] < 0 for key in clocks):
        raise UnsafeState("invalid clock")
    counts = {"failures": FAILURE_THRESHOLD, "interfaces": 8}
    if any(
        type(values[key]) is not int or not 0 <= values[key] <= cap
        for key, cap in counts.items()
    ):
        raise UnsafeState("invalid count")
    choices = {
        "result": RESULTS,
        "service": SERVICES,
        "health": HEALTH,
        "underlay": UNDERLAY,
    }
    if any(
        not isinstance(values[key], str) or values[key] not in allowed
        for key, allowed in choices.items()
    ):
        raise UnsafeState("invalid status")
    if not isinstance(values["signature"], str) or not re.fullmatch(
        r"(?:[a-f0-9]{64})?", values["signature"]
    ):
        raise UnsafeState("invalid signature")
    return State(**values)


class Store:
    def __init__(self, root: Path):
        self.root = root
        self.fd = -1

    def __enter__(self) -> Self:
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.fd = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        if os.fstat(self.fd).st_uid != os.getuid():
            os.close(self.fd)
            raise UnsafeState("unsafe state directory")
        os.fchmod(self.fd, 0o700)
        return self

    def __exit__(self, *arguments: object) -> None:
        os.close(self.fd)

    def paused(self) -> bool:
        try:
            os.stat("paused", dir_fd=self.fd, follow_symlinks=False)
            return True
        except FileNotFoundError:
            return False

    def load(self) -> State:
        try:
            fd = private_file(self.fd, "state.json", os.O_RDONLY)
        except FileNotFoundError:
            return State()
        with os.fdopen(fd, "rb") as source:
            return decode_state(source.read(STATE_LIMIT + 1))

    def save(self, state: State) -> None:
        atomic_write(
            self.fd,
            "state.json",
            (json.dumps(asdict(state), sort_keys=True) + "\n").encode(),
        )


@contextmanager
def check_lock(store: Store) -> Iterator[bool]:
    fd = private_file(store.fd, "check.lock", os.O_RDWR | os.O_CREAT)
    acquired = False
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            acquired = True
        except BlockingIOError:
            pass
        yield acquired
    finally:
        os.close(fd)


def repair(store: Store, state: State) -> State:
    if store.paused():
        return replace(state, failures=0, result="paused")
    service = service_status(time.monotonic() + 3)
    if service not in {"connected", "disconnected"}:
        return replace(state, failures=0, service=service, result="service-unknown")
    # Persist the cooldown before either mutating command, including failed attempts.
    state = replace(
        state,
        last_restart=time.time(),
        last_restart_tick=time.monotonic(),
        failures=0,
        service=service,
        result="restart-attempt",
    )
    store.save(state)
    if store.paused():
        return replace(state, result="paused")
    if service == "connected":
        stopped = run_command([SCUTIL, "--nc", "stop", "SFM"], timeout=5)
        if stopped.code != 0:
            return replace(state, result="stop-failed")
    if store.paused():
        return replace(state, result="paused")
    started = run_command([SCUTIL, "--nc", "start", "SFM"], timeout=5)
    return replace(state, result="restarted" if started.code == 0 else "start-failed")


def report(state: State, paused: bool) -> dict[str, object]:
    remaining = cooldown_remaining(state, time.time(), time.monotonic())
    return {
        "result": "paused" if paused else state.result,
        "paused": paused,
        "failures": 0 if paused else state.failures,
        "service": state.service,
        "health": state.health,
        "underlay": state.underlay,
        "interfaces": state.interfaces,
        "last_check": state.last_check,
        "last_restart": state.last_restart,
        "cooldown_remaining": math.ceil(remaining),
        "grace_remaining": math.ceil(max(0, state.grace_until - time.time())),
    }


def emit(value: dict[str, object]) -> int:
    print(json.dumps(value, sort_keys=True))
    return 0


def locked_command(store: Store, command: str) -> int:
    if command == "resume":
        state = replace(
            store.load(),
            failures=0,
            grace_until=time.time() + NETWORK_GRACE,
            result="resumed",
        )
        store.save(state)
        if store.paused():
            os.unlink("paused", dir_fd=store.fd)
        return emit(report(state, False))
    if sys.platform != "darwin":
        return emit({"result": "unsupported-platform"})
    if command == "probe":
        observation = observe()
        return emit(
            {
                "result": "probe",
                "paused": store.paused(),
                "service": observation.service,
                "health": observation.health,
                "underlay": observation.underlay,
                "interfaces": observation.interfaces,
            }
        )
    state = store.load()
    observation = Observation() if store.paused() else observe()
    state = transition(
        state, observation, time.time(), time.monotonic(), store.paused()
    )
    if state.result == "repair-ready":
        state = repair(store, state)
    store.save(state)
    return emit(report(state, store.paused()))


def command(store: Store, action: str) -> int:
    if action == "pause":
        # Pause does not wait for a potentially in-flight probe's lock.
        atomic_write(store.fd, "paused", b"")
        return emit({"result": "paused", "paused": True})
    if action == "status":
        return emit(report(store.load(), store.paused()))
    with check_lock(store) as acquired:
        return locked_command(store, action) if acquired else emit({"result": "busy"})


def main(arguments: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command", choices=("pause", "resume", "status", "check", "probe")
    )
    args = parser.parse_args(arguments)
    try:
        with Store(state_directory()) as store:
            return command(store, args.command)
    except (OSError, ValueError, OverflowError):
        emit({"result": "state-unavailable"})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
