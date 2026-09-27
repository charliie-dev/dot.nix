"""Bounded capture with cancellation-safe ownership of a child process group."""

import os
import selectors
import signal
import subprocess
import time
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Self

CANCEL_SIGNALS = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)


class ProcessError(ValueError):
    """Contains only a fixed error code and optional exit status."""

    def __init__(self, code: str, returncode: int | None = None) -> None:
        super().__init__(code)
        self.returncode = returncode


class Cancellation:
    def __init__(self) -> None:
        self.deferred = 0
        self.pending = False
        self.previous: dict[signal.Signals, Any] = {}

    def requested(self, _number: int, _frame: Any) -> None:
        self.pending = True
        self.check()

    def check(self) -> None:
        if self.pending and not self.deferred:
            raise KeyboardInterrupt

    @contextmanager
    def critical(self) -> Iterator[None]:
        self.deferred += 1
        try:
            yield
        finally:
            self.deferred -= 1

    def __enter__(self) -> Self:
        self.previous = {
            number: signal.signal(number, self.requested) for number in CANCEL_SIGNALS
        }
        return self

    def __exit__(self, _type: object, _value: object, _traceback: object) -> None:
        with self.critical():
            for number, handler in self.previous.items():
                signal.signal(number, handler)
        if _type is None:
            self.check()


def termination_attempt(
    process: subprocess.Popen[bytes], number: signal.Signals
) -> bool:
    failed = False
    try:
        os.killpg(process.pid, number)
    except ProcessLookupError:
        pass
    except OSError:
        failed = True
    try:
        process.wait(timeout=0.5)
    except subprocess.TimeoutExpired:
        pass
    except OSError:
        failed = True
    return failed


def close_pipes(process: subprocess.Popen[bytes]) -> bool:
    failed = False
    for stream in (process.stdout, process.stderr):
        if stream is None:
            continue
        try:
            stream.close()
        except (OSError, ValueError):
            failed = True
    return failed


def terminate(process: subprocess.Popen[bytes]) -> None:
    failed = False
    try:
        for number in (signal.SIGTERM, signal.SIGKILL):
            failed = termination_attempt(process, number) or failed
        try:
            process.wait(timeout=0.5)
        except (OSError, subprocess.TimeoutExpired):
            failed = True
    finally:
        failed = close_pipes(process) or failed
    if failed:
        raise ProcessError("cleanup-failed")


def drain(
    selector: selectors.BaseSelector,
    events: list[tuple[selectors.SelectorKey, int]],
    output: bytearray,
    observe: Callable[[str, bytes], None] | None = None,
) -> int:
    stderr_size = 0
    for key, _ in events:
        chunk = os.read(key.fd, 8192)
        if chunk and observe is not None:
            observe(key.data, chunk)
        if not chunk:
            selector.unregister(key.fileobj)
        elif key.data == "stdout":
            output.extend(chunk)
        else:
            stderr_size += len(chunk)
    return stderr_size


def collect(
    process: subprocess.Popen[bytes],
    deadline: float,
    limit: int,
    reject_stderr: bool,
    observe: Callable[[str, bytes], None] | None = None,
) -> bytes:
    if process.stdout is None or process.stderr is None:
        raise ProcessError("output")
    output = bytearray()
    stderr_size = 0
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ, "stdout")
        selector.register(process.stderr, selectors.EVENT_READ, "stderr")
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ProcessError("timeout")
            stderr_size += drain(selector, selector.select(remaining), output, observe)
            if len(output) > limit or stderr_size > limit:
                raise ProcessError("output-limit")
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise ProcessError("timeout")
    try:
        status = process.wait(timeout=remaining)
    except subprocess.TimeoutExpired:
        raise ProcessError("timeout") from None
    if status:
        raise ProcessError("failed", returncode=status)
    if reject_stderr and stderr_size:
        raise ProcessError("output")
    return bytes(output)


def capture(
    command: list[str],
    environment: dict[str, str],
    *,
    timeout: float,
    limit: int,
    cwd: Path | None = None,
    reject_stderr: bool = False,
    observe: Callable[[str, bytes], None] | None = None,
) -> bytes:
    deadline = time.monotonic() + timeout
    process: subprocess.Popen[bytes] | None = None
    with Cancellation() as cancellation:
        try:
            with cancellation.critical():
                process = subprocess.Popen(
                    command,
                    env=environment,
                    cwd=cwd,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    start_new_session=True,
                )
            cancellation.check()
            return collect(process, deadline, limit, reject_stderr, observe)
        except OSError:
            raise ProcessError("start-or-io") from None
        finally:
            with cancellation.critical():
                if process is not None:
                    terminate(process)
            cancellation.check()
