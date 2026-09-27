"""Synthetic process-tree tests for cancellation and bounded capture."""

import io
import json
import os
import runpy
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from typing import Any
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[2] / "conf.d/bedrock-api-key"
CONTROL = runpy.run_path(str(SCRIPTS / "process_control.py"))
PYTHON = str(Path(sys.executable).resolve())


def kill_group(pid: int) -> None:
    try:
        os.killpg(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def absent(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    return False


def wait_file(path: Path, process: subprocess.Popen[bytes]) -> None:
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline and process.poll() is None:
        if path.exists():
            return
        time.sleep(0.01)
    raise AssertionError("synthetic process did not reach its checkpoint")


class ProcessContracts(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR", "/tmp"))
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.env = {"HOME": str(self.root), "PATH": "/usr/bin:/bin"}

    def test_pending_cancel_does_not_replace_cleanup_failure(self):
        previous = {
            number: signal.getsignal(number) for number in CONTROL["CANCEL_SIGNALS"]
        }
        with (
            self.assertRaisesRegex(ValueError, "cleanup-failed"),
            CONTROL["Cancellation"]() as cancellation,
        ):
            cancellation.pending = True
            raise CONTROL["ProcessError"]("cleanup-failed")
        self.assertEqual(
            previous, {number: signal.getsignal(number) for number in previous}
        )

    def test_kill_and_wait_errors_still_close_all_pipes(self):
        for operation in ("kill", "wait"):
            process = mock.Mock(pid=123456789, stdout=io.BytesIO(), stderr=io.BytesIO())
            process.wait.side_effect = (
                OSError("synthetic wait failure") if operation == "wait" else None
            )
            with mock.patch.object(os, "killpg") as kill:
                kill.side_effect = (
                    PermissionError("synthetic kill failure")
                    if operation == "kill"
                    else None
                )
                self.assertRaisesRegex(
                    ValueError, "cleanup-failed", CONTROL["terminate"], process
                )
            self.assertEqual(kill.call_count, 2)
            self.assertEqual(process.wait.call_count, 3)
            self.assertTrue(process.stdout.closed)
            self.assertTrue(process.stderr.closed)

    def test_cancel_with_kill_failure_is_explicit_and_bounded(self):
        previous = {
            number: signal.getsignal(number) for number in CONTROL["CANCEL_SIGNALS"]
        }
        popen = subprocess.Popen
        real_killpg = os.killpg
        created: list[subprocess.Popen[Any]] = []

        def interrupted_start(command: list[str], **kwargs: Any):
            process = popen(command, text=False, **kwargs)
            created.append(process)
            os.kill(os.getpid(), signal.SIGTERM)
            return process

        started = time.monotonic()
        try:
            with (
                mock.patch.object(subprocess, "Popen", side_effect=interrupted_start),
                mock.patch.object(
                    os,
                    "killpg",
                    side_effect=PermissionError("synthetic permission failure"),
                ),
            ):
                self.assertRaisesRegex(
                    ValueError,
                    "cleanup-failed",
                    CONTROL["capture"],
                    [PYTHON, "-I", "-c", "import time;time.sleep(30)"],
                    self.env,
                    timeout=5,
                    limit=1024,
                )
            self.assertLess(time.monotonic() - started, 4)
            self.assertEqual(len(created), 1)
            self.assertFalse(absent(created[0].pid))
            self.assertTrue(
                all(
                    stream is not None and stream.closed
                    for stream in (created[0].stdout, created[0].stderr)
                )
            )
            self.assertEqual(
                previous, {number: signal.getsignal(number) for number in previous}
            )
        finally:
            for process in created:
                real_killpg(process.pid, signal.SIGKILL)
                process.wait()

    def test_process_error_preserves_exit_code_and_stream_observer(self):
        seen: list[tuple[str, bytes]] = []
        command = [
            PYTHON,
            "-I",
            "-c",
            "import sys;print('SYNTHETIC_OUT');print('SYNTHETIC_ERR',file=sys.stderr);sys.exit(7)",
        ]
        with self.assertRaises(ValueError) as raised:
            CONTROL["capture"](
                command,
                self.env,
                timeout=5,
                limit=1024,
                observe=lambda name, data: seen.append((name, data)),
            )
        self.assertEqual(str(raised.exception), "failed")
        self.assertEqual(getattr(raised.exception, "returncode", None), 7)
        self.assertEqual({name for name, _ in seen}, {"stdout", "stderr"})

    def test_observer_failure_still_cleans_owned_processes(self):
        created: list[subprocess.Popen[Any]] = []
        popen = subprocess.Popen

        def record(command: list[str], **kwargs: Any):
            process = popen(command, text=False, **kwargs)
            created.append(process)
            return process

        def broken(_name: str, _data: bytes):
            raise ValueError("synthetic-observer-failed")

        with mock.patch.object(subprocess, "Popen", side_effect=record):
            self.assertRaisesRegex(
                ValueError,
                "synthetic-observer-failed",
                CONTROL["capture"],
                [
                    PYTHON,
                    "-I",
                    "-c",
                    "import time;print('SYNTHETIC',flush=True);time.sleep(30)",
                ],
                self.env,
                timeout=5,
                limit=1024,
                observe=broken,
            )
        self.assertEqual(len(created), 1)
        self.assertTrue(absent(created[0].pid))
        self.assertTrue(
            all(
                stream is not None and stream.closed
                for stream in (created[0].stdout, created[0].stderr)
            )
        )

    def test_stdout_and_stderr_limits_are_bounded(self):
        for stream in ("stdout", "stderr"):
            command = [
                PYTHON,
                "-I",
                "-c",
                f"import sys;sys.{stream}.write('x'*1000000)",
            ]
            self.assertRaisesRegex(
                ValueError,
                "output-limit",
                CONTROL["capture"],
                command,
                self.env,
                timeout=5,
                limit=1024,
            )

    def test_signal_during_creation_and_again_during_cleanup_is_deferred(self):
        namespace = CONTROL["capture"].__globals__
        popen = subprocess.Popen
        terminate = namespace["terminate"]
        created: list[subprocess.Popen[Any]] = []

        def interrupted_start(command: list[str], **kwargs: Any):
            process = popen(command, text=False, **kwargs)
            created.append(process)
            os.kill(os.getpid(), signal.SIGTERM)
            return process

        def interrupted_cleanup(process):
            os.kill(os.getpid(), signal.SIGINT)
            terminate(process)

        try:
            with (
                mock.patch.object(subprocess, "Popen", side_effect=interrupted_start),
                mock.patch.dict(namespace, terminate=interrupted_cleanup),
            ):
                self.assertRaises(
                    KeyboardInterrupt,
                    CONTROL["capture"],
                    [PYTHON, "-I", "-c", "import time;time.sleep(30)"],
                    self.env,
                    timeout=5,
                    limit=1024,
                )
            self.assertEqual(len(created), 1)
            self.assertTrue(absent(created[0].pid))
        finally:
            for process in created:
                kill_group(process.pid)
                process.wait()

    def leader(self, directory: Path) -> tuple[Path, Path, Path]:
        ready = directory / "ready.json"
        terminating = directory / "terminating"
        source = directory / "leader.py"
        source.write_text(
            f"#!{PYTHON}\n"
            "import json,os,signal,subprocess,time\nfrom pathlib import Path\n"
            f"child=subprocess.Popen([{PYTHON!r},'-I','-c','import time;time.sleep(30)'])\n"
            "def stop(number,frame):\n"
            "    child.wait(timeout=2)\n"
            f"    Path({str(terminating)!r}).touch()\n"
            "    while True: time.sleep(1)\n"
            "signal.signal(signal.SIGTERM,stop)\n"
            f"temporary=Path({str(ready) + '.tmp'!r})\n"
            "temporary.write_text(json.dumps({'leader':os.getpid(),'child':child.pid}))\n"
            f"temporary.replace({str(ready)!r})\n"
            "while True: time.sleep(1)\n"
        )
        source.chmod(0o700)
        return source, ready, terminating

    def run_signal_case(self, caller: str, number: signal.Signals) -> None:
        directory = self.root / f"{caller}-{number}"
        directory.mkdir()
        leader, ready, terminating = self.leader(directory)
        command = self.caller_command(caller, leader, directory)
        process = subprocess.Popen(
            command, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        pids: dict[str, int] = {}
        try:
            wait_file(ready, process)
            pids = json.loads(ready.read_text())
            os.kill(process.pid, number)
            wait_file(terminating, process)
            os.kill(process.pid, signal.SIGHUP)
            stdout, _stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 130)
            self.assertEqual(stdout, b"")
            self.assertTrue(all(absent(pid) for pid in pids.values()))
        finally:
            if pids:
                kill_group(pids["leader"])
            if process.poll() is None:
                process.kill()
            process.communicate()

    def caller_command(self, caller: str, leader: Path, directory: Path) -> list[str]:
        if caller == "grok":
            runtime = directory / "runtime.json"
            runtime.write_text(
                json.dumps(
                    {
                        "doppler_run": str(leader),
                        "python": PYTHON,
                        "home": str(self.root),
                        "helper_path": "/usr/bin:/bin",
                        "process_control": str(SCRIPTS / "process_control.py"),
                    }
                )
            )
            return [PYTHON, "-I", str(SCRIPTS / "grok.py"), str(runtime), "key"]
        code = (
            "import runpy,sys\nfrom pathlib import Path\n"
            f"v=runpy.run_path({str(SCRIPTS / 'verify.py')!r})\n"
            "try:\n"
            f"    v['capture']([{str(leader)!r}],{self.env!r},Path({str(directory)!r}),{str(SCRIPTS / 'process_control.py')!r})\n"
            "except KeyboardInterrupt:\n    sys.exit(130)\n"
        )
        return [PYTHON, "-I", "-c", code]

    def test_grok_and_verifier_handle_all_cancel_signals_and_repeats(self):
        for caller in ("grok", "verify"):
            for number in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
                with self.subTest(caller=caller, signal=number):
                    self.run_signal_case(caller, number)


if __name__ == "__main__":
    unittest.main()
