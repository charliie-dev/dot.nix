"""Synthetic account/profile tests and optional loopback packet experiments."""

from __future__ import annotations

import copy
import fcntl
import importlib.util
import json
import os
import select
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "conf.d/sfm-warp-maintenance"


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, SOURCE / f"{name}.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


account = load("account_update")
probe = load("reserved_probe")


SIGNAL_HELPER = """
import importlib.util, json, signal, subprocess, sys, tempfile
from pathlib import Path
spec = importlib.util.spec_from_file_location('probe', sys.argv[1])
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
probe.install_signal_handlers()
try:
    with tempfile.TemporaryDirectory(prefix='sfm-signal-probe-') as directory:
        child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'], start_new_session=True)
        try:
            Path(directory, 'synthetic-config').write_text('synthetic-only')
            print(json.dumps({'pid': child.pid, 'directory': directory}), flush=True)
            signal.pause()
        finally:
            probe.stop_proxy(child)
except probe.ProbeError:
    pass
"""


def kill_if_present(pid: int) -> None:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def signal_cleanup_result(sig: int) -> dict:
    process = subprocess.Popen(
        [sys.executable, "-u", "-c", SIGNAL_HELPER, str(SOURCE / "reserved_probe.py")],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    metadata: dict = {}
    try:
        assert process.stdout is not None
        if not select.select([process.stdout], [], [], 5)[0]:
            raise AssertionError("signal fixture did not start")
        metadata = json.loads(process.stdout.readline())
        process.send_signal(sig)
        process.wait(timeout=8)
        cleaned = not Path(metadata["directory"]).exists()
        gone = False
        try:
            os.kill(metadata["pid"], 0)
        except ProcessLookupError:
            gone = True
        return {"exit": process.returncode, "child_gone": gone, "temp_cleaned": cleaned}
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
        if metadata:
            kill_if_present(metadata["pid"])
            shutil.rmtree(metadata["directory"], ignore_errors=True)
        if process.stdout is not None:
            process.stdout.close()
        if process.stderr is not None:
            process.stderr.close()


def queued_noise_trial(previous: list, ports: list[int], sender: socket.socket):
    def trial(_binary, _config, _port, receiver):
        if previous:
            sender.sendto(
                bytes.fromhex("01ffffff") + bytes(144), previous[-1].getsockname()
            )
        sender.sendto(bytes.fromhex("01c95713") + bytes(144), receiver.getsockname())
        previous.append(receiver)
        ports.append(receiver.getsockname()[1])
        return receiver.recvfrom(2048)[0][:4].hex()

    return trial


class AccountTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="sfm-account-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.binary = self.directory / "fake-wgcf"
        self.account = self.directory / "synthetic-account.toml"
        self.now = 100000.0

    def invoke(self):
        return account.update_account(
            self.binary, self.account, self.directory, self.now
        )

    @patch.object(account, "online", return_value=True)
    @patch.object(account.subprocess, "run")
    def test_explicit_account_command_and_output_redaction(self, run, online):
        run.return_value = subprocess.CompletedProcess(
            [], 0, "PRIVATE_SENTINEL", "PRIVATE_SENTINEL"
        )
        with patch.dict(os.environ, {"WGCF_LICENSE_KEY": "PRIVATE_SENTINEL"}):
            result = self.invoke()
        self.assertEqual(result, {"status": "updated"})
        self.assertEqual(
            run.call_args.args[0],
            [str(self.binary), "--config", str(self.account), "update"],
        )
        self.assertNotIn("WGCF_LICENSE_KEY", run.call_args.kwargs["env"])
        self.assertEqual(run.call_args.kwargs["stdout"], subprocess.DEVNULL)
        self.assertEqual(run.call_args.kwargs["stderr"], subprocess.DEVNULL)
        self.assertEqual(run.call_args.kwargs["timeout"], 90)
        self.assertNotIn(
            "PRIVATE_SENTINEL", (self.directory / "account-update.json").read_text()
        )

    @patch.object(account, "online", return_value=False)
    @patch.object(account.subprocess, "run")
    def test_offline_skips_account_access(self, run, online):
        self.assertEqual(self.invoke(), {"status": "offline"})
        run.assert_not_called()

    @patch.object(account, "online")
    def test_pause_skips_network_and_account(self, online):
        (self.directory / "paused").touch()
        self.assertEqual(self.invoke(), {"status": "paused"})
        online.assert_not_called()

    @patch.object(account, "online")
    def test_success_is_throttled_for_twelve_hours(self, online):
        account.save_state(
            self.directory / "account-update.json", {"last_success": self.now - 1}
        )
        self.assertEqual(self.invoke(), {"status": "not_due"})
        online.assert_not_called()

    @patch.object(account.subprocess, "run")
    def test_pause_during_connectivity_probe_prevents_account_operation(self, run):
        def pause_now():
            (self.directory / "paused").touch()
            return True

        with patch.object(account, "online", side_effect=pause_now):
            self.assertEqual(self.invoke(), {"status": "paused"})
        run.assert_not_called()

    @patch.object(account, "online", return_value=True)
    @patch.object(
        account.subprocess, "run", side_effect=subprocess.TimeoutExpired("fake", 90)
    )
    def test_timeout_is_recorded_without_raw_error(self, run, online):
        self.assertEqual(self.invoke(), {"status": "update_timeout"})
        state = json.loads((self.directory / "account-update.json").read_text())
        self.assertNotIn("last_success", state)
        self.assertEqual(state["status"], "update_timeout")

    def test_agent_is_account_only_and_uses_stable_python(self):
        agent = account.launch_agent(self.binary, self.account)
        self.assertEqual(agent["StartInterval"], 43200)
        self.assertEqual(
            agent["ProgramArguments"][:2], ["/opt/homebrew/bin/python3", "-IS"]
        )
        self.assertNotIn("upgrade", json.dumps(agent))
        self.assertTrue(agent["RunAtLoad"])

    def test_symlinked_state_is_rejected_before_read(self):
        (self.directory / "account-update.json").symlink_to(self.directory / "missing")
        self.assertRaises(account.UpdateError, self.invoke)


class SafetyRegressions(unittest.TestCase):
    def test_sigterm_reaps_child_and_removes_temporary_config(self):
        self.assertEqual(
            signal_cleanup_result(signal.SIGTERM),
            {"exit": 0, "child_gone": True, "temp_cleaned": True},
        )

    def test_sighup_reaps_child_and_removes_temporary_config(self):
        self.assertEqual(
            signal_cleanup_result(signal.SIGHUP),
            {"exit": 0, "child_gone": True, "temp_cleaned": True},
        )

    @patch.object(probe.os, "killpg", side_effect=ProcessLookupError)
    def test_child_exit_race_is_tolerated(self, killpg):
        process = Mock()
        process.poll.return_value = None
        probe.stop_proxy(process)
        process.wait.assert_called_once_with(timeout=5)

    @patch.object(account.subprocess, "run")
    def test_loaded_job_is_rejected_even_if_disk_plist_is_missing(self, run):
        run.return_value = subprocess.CompletedProcess([], 0)
        self.assertRaises(account.UpdateError, account.require_job_unloaded)
        self.assertEqual(run.call_args.args[0][1], "print")

    @patch.object(account.subprocess, "run")
    def test_unloaded_job_can_be_installed(self, run):
        run.return_value = subprocess.CompletedProcess([], 113)
        self.assertEqual(account.require_job_unloaded(), f"gui/{os.getuid()}")

    def test_existing_account_operation_blocks_probe(self):
        with tempfile.TemporaryDirectory(prefix="sfm-lock-test-") as raw:
            directory = Path(raw)
            first = probe.open_probe_lock(directory / "account-update.lock")
            self.addCleanup(first.close)
            self.assertRaises(
                probe.ProbeError,
                probe.open_probe_lock,
                directory / "account-update.lock",
            )
            first.close()

    def test_probe_holds_both_maintenance_locks(self):
        with tempfile.TemporaryDirectory(prefix="sfm-lock-test-") as raw:
            directory = Path(raw) / "sfm-warp-maintenance"
            directory.mkdir()
            self.check_held_locks(raw, directory)

    def check_held_locks(self, root, directory):
        with (
            patch.dict(os.environ, {"XDG_STATE_HOME": root}),
            probe.maintenance_locks(),
        ):
            self.assertRaises(
                probe.ProbeError, probe.open_probe_lock, directory / "check.lock"
            )
            self.assertRaises(
                probe.ProbeError,
                probe.open_probe_lock,
                directory / "account-update.lock",
            )
        with probe.open_probe_lock(directory / "account-update.lock") as lock:
            fcntl.flock(lock, fcntl.LOCK_UN)

    def test_queued_previous_packet_is_not_assigned_to_next_trial(self):
        sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.addCleanup(sender.close)
        ports: list[int] = []
        trial = queued_noise_trial([], ports, sender)
        paths = {"array": Path("array"), "formatted": Path("formatted")}
        with (
            tempfile.TemporaryDirectory(prefix="sfm-noise-test-") as raw,
            patch.object(probe, "prepare_pair", return_value=paths),
            patch.object(probe, "loopback_trial", side_effect=trial),
        ):
            result = probe.loopback(Path("fake"), Path(raw))
        self.assertTrue(result["passed"])
        self.assertEqual(len(set(ports)), 4)


class ProfileTests(unittest.TestCase):
    def test_reserved_encodings_match(self):
        self.assertEqual(
            probe.reserved_bytes([201, 87, 19]), probe.reserved_bytes("yVcT")
        )

    def test_bad_reserved_values_are_rejected(self):
        values = (
            [True, 87, 19],
            [201.0, 87, 19],
            [256, 87, 19],
            [1, 2],
            "???",
            "AAAAAA==",
            None,
        )
        for value in values:
            self.assertRaises(probe.ProbeError, probe.reserved_bytes, value)

    def test_audit_reports_constraints_without_profile_values(self):
        profile: dict = {
            "route": {"auto_detect_interface": True, "final": "warp", "rules": []},
            "inbounds": [
                {"type": "tun", "route_exclude_address": ["162.159.192.0/24"]}
            ],
            "endpoints": [
                {
                    "bind_interface": "PRIVATE_SENTINEL",
                    "private_key": "PRIVATE_SENTINEL",
                }
            ],
        }
        result = probe.audit_profile(profile)
        self.assertTrue(result["auto_detect_interface"])
        self.assertFalse(result["tailnet_overlaps_tun_exclusions"])
        self.assertEqual(
            result["fixed_dial_field_paths"], ["endpoints[0].bind_interface"]
        )
        self.assertNotIn("PRIVATE_SENTINEL", json.dumps(result))
        profile["inbounds"][0]["route_exclude_address"] = ["100.0.0.0/8"]
        self.assertTrue(probe.audit_profile(profile)["tailnet_overlaps_tun_exclusions"])

    def test_cloudflare_copy_preserves_source(self):
        endpoint = probe.fixture_endpoint(2408)
        endpoint["peers"][0]["address"] = "162.159.192.6"
        profile = {"endpoints": [endpoint]}
        original = copy.deepcopy(profile)
        result = probe.cloudflare_endpoint(profile)
        result["peers"][0]["reserved"] = "yVcT"
        self.assertEqual(profile, original)
        self.assertNotIn("bind_interface", result)
        self.assertFalse(result["system"])

    def test_unexpected_remote_peer_is_rejected(self):
        endpoint = probe.fixture_endpoint(2408)
        endpoint["peers"][0]["address"] = "192.0.2.1"
        self.assertRaises(
            probe.ProbeError, probe.cloudflare_endpoint, {"endpoints": [endpoint]}
        )


@unittest.skipUnless(
    os.environ.get("SFM_TEST_BINARY"), "set SFM_TEST_BINARY for actual loopback packets"
)
class PacketTests(unittest.TestCase):
    def check_packets(self, negative: bool):
        with tempfile.TemporaryDirectory(prefix="sfm-packet-test-") as directory:
            return probe.loopback(
                Path(os.environ["SFM_TEST_BINARY"]), Path(directory), negative
            )

    def test_real_array_and_formatted_packets_match(self):
        report = self.check_packets(False)
        self.assertTrue(report["passed"])
        self.assertEqual(
            [trial["header"] for trial in report["trials"]], ["01c95713"] * 4
        )

    def test_negative_control_catches_wrong_wire_bytes(self):
        report = self.check_packets(True)
        self.assertFalse(report["passed"])
        self.assertEqual(
            [trial["header"] for trial in report["trials"]], ["01000000"] * 4
        )


if __name__ == "__main__":
    unittest.main()
