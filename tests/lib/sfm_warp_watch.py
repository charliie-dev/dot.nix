"""Synthetic watchdog contracts; never invokes live SFM or network probes."""

from __future__ import annotations

import ast
import importlib.util
import io
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stdout
from dataclasses import asdict, replace
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "conf.d/sfm-warp-maintenance/watch.py"
MODULE = REPO / "modules/platform/services/sfm-warp-watch.nix"
NIX = shutil.which("nix")
SPEC = importlib.util.spec_from_file_location("sfm_warp_watch", SOURCE)
assert SPEC is not None and SPEC.loader is not None
WATCH = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = WATCH
SPEC.loader.exec_module(WATCH)
NETWORK = {"en0": ("192.0.2.10",)}
SIGNATURE = WATCH.signature(NETWORK)
BAD = WATCH.Observation(SIGNATURE, 1, "connected", "failed", "reachable")
BASE = WATCH.State(last_check=1000, last_tick=1000, signature=SIGNATURE)


def dictionary(interface: str, *addresses: str) -> bytes:
    entries = "\n".join(
        f"    {index} : {address}" for index, address in enumerate(addresses)
    )
    return (
        "<dictionary> {\n  Addresses : <array> {\n"
        f"{entries}\n  }}\n  InterfaceName : {interface}\n}}\n"
    ).encode()


class StubCommands:
    def __init__(self):
        self.calls: list[tuple[list[str], dict]] = []
        self.service = WATCH.Result(0, b"Connected\n<dictionary> {}\n")
        self.dictionaries = [dictionary("en0", "192.0.2.10")]
        self.health = WATCH.Result(0, b"warp=off\n\n200")
        self.proxy = WATCH.Result(0, b"warp=off\n\n200")
        self.underlay: dict[tuple[str, str], object] = {}
        self.default_underlay = WATCH.Result(0, b"HTTP/2 200\r\n\r\n\n200")

    def __call__(self, arguments, **options):
        self.calls.append((arguments, options))
        if arguments == [WATCH.SCUTIL, "--nc", "status", "SFM"]:
            return self.service
        if arguments == [WATCH.SCUTIL]:
            return self.scutil(options["input_data"])
        if arguments[0] != WATCH.CURL or arguments[1] != "-q":
            raise AssertionError("unexpected command")
        if "--proxy" in arguments:
            return self.proxy
        if "--interface" not in arguments:
            return self.health
        interface = arguments[arguments.index("--interface") + 1]
        target = WATCH.GOOGLE if WATCH.GOOGLE in arguments else WATCH.TRACE
        return self.underlay.get((interface, target), self.default_underlay)

    def scutil(self, input_data):
        if input_data.startswith(b"list "):
            keys = [
                f"subKey [{index}] = State:/Network/Service/fixture-{index}/IPv4\n"
                for index in range(len(self.dictionaries))
            ]
            return WATCH.Result(0, "".join(keys).encode())
        if not re.fullmatch(
            rb"(?:show State:/Network/Service/fixture-\d+/IPv4\n)+", input_data
        ):
            raise AssertionError("unexpected dynamic-store query")
        return WATCH.Result(0, b"".join(self.dictionaries))


class Fixture(unittest.TestCase):
    def setUp(self):
        directory = os.environ.get("SFM_TEST_ROOT") or os.environ.get("TMPDIR")
        self.temporary = tempfile.TemporaryDirectory(prefix="sfm-watch-", dir=directory)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.env = {
            "HOME": str(self.root / "home"),
            "XDG_STATE_HOME": str(self.root / "state"),
            "TMPDIR": str(self.root),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        }
        self.state_root = self.root / "state/sfm-warp-maintenance"

    def invoke(self, action, *options):
        output = io.StringIO()
        with mock.patch.dict(os.environ, self.env, clear=True), redirect_stdout(output):
            code = WATCH.main([action, *options])
        return code, json.loads(output.getvalue())


class Policy(unittest.TestCase):
    def test_three_consecutive_failures_require_reachable_underlay(self):
        state = BASE
        for index, now in enumerate((1060, 1120, 1180), 1):
            state = WATCH.transition(state, BAD, now, now)
            self.assertEqual(state.failures, index)
            self.assertEqual(state.result, "repair-ready" if index == 3 else "failed")

    def test_offline_and_unknown_reset_streak(self):
        state = replace(BASE, failures=2)
        for underlay in ("offline", "unknown"):
            next_state = WATCH.transition(
                state, replace(BAD, underlay=underlay), 1060, 1060
            )
            self.assertEqual(
                (next_state.failures, next_state.result), (0, f"underlay-{underlay}")
            )
            self.assertEqual(WATCH.transition(next_state, BAD, 1120, 1120).failures, 1)

    def test_healthy_unknown_health_and_paused_reset(self):
        state = replace(BASE, failures=2)
        healthy = WATCH.transition(state, replace(BAD, health="healthy"), 1060, 1060)
        unknown = WATCH.transition(state, replace(BAD, health="unknown"), 1060, 1060)
        paused = WATCH.transition(state, BAD, 1060, 1060, paused=True)
        self.assertEqual((healthy.result, healthy.failures), ("healthy", 0))
        self.assertEqual((unknown.result, unknown.failures), ("health-unknown", 0))
        self.assertEqual((paused.result, paused.failures), ("paused", 0))

    def test_unknown_or_transitioning_service_and_missing_interfaces_skip(self):
        cases = [
            ("unknown", "service-unknown"),
            ("connecting", "service-transition"),
            ("disconnecting", "service-transition"),
        ]
        for service, reason in cases:
            state = WATCH.transition(
                replace(BASE, failures=2), replace(BAD, service=service), 1060, 1060
            )
            self.assertEqual((state.result, state.failures), (reason, 0))
        state = WATCH.transition(
            BASE, replace(BAD, signature="", interfaces=0), 1060, 1060
        )
        self.assertEqual((state.result, state.failures), ("interfaces-unknown", 0))

    def test_known_disconnected_service_can_recover(self):
        state = WATCH.transition(
            replace(BASE, failures=2), replace(BAD, service="disconnected"), 1060, 1060
        )
        self.assertEqual(state.result, "repair-ready")

    def test_first_network_and_address_or_interface_changes_get_sixty_seconds(self):
        first = WATCH.transition(WATCH.State(), BAD, 1000, 1000)
        self.assertEqual(
            (first.result, first.failures, first.grace_until),
            ("network-grace", 0, 1060),
        )
        self.assertEqual(WATCH.transition(first, BAD, 1059, 1059).failures, 0)
        self.assertEqual(WATCH.transition(first, BAD, 1060, 1060).failures, 1)
        for network in ({"en7": ("192.0.2.10",)}, {"en0": ("192.0.2.11",)}):
            observation = replace(BAD, signature=WATCH.signature(network))
            state = WATCH.transition(replace(BASE, failures=2), observation, 1060, 1060)
            self.assertEqual(
                (state.result, state.failures, state.grace_until),
                ("network-grace", 0, 1120),
            )

    def test_change_during_probe_resets_even_if_previous_signature_returns(self):
        state = WATCH.transition(
            replace(BASE, failures=2), replace(BAD, changed=True), 1060, 1060
        )
        self.assertEqual((state.result, state.failures), ("network-grace", 0))

    def test_sleep_large_gaps_reboot_and_clock_jumps_reset(self):
        for now, tick in (
            (1300, 1300),
            (1120, 1020),
            (1060, 5),
            (990, 1060),
            (1060, 990),
        ):
            state = WATCH.transition(replace(BASE, failures=2), BAD, now, tick)
            self.assertEqual((state.result, state.failures), ("wake-grace", 0))
            self.assertEqual(state.grace_until, now + 60)

    def test_cooldown_boundary_and_backward_clock(self):
        state = replace(
            BASE, last_restart=1000, last_check=1840, last_tick=1840, failures=2
        )
        before = WATCH.transition(state, BAD, 1899, 1899)
        self.assertEqual(before.result, "cooldown")
        self.assertEqual(
            WATCH.transition(before, BAD, 1900, 1900).result, "repair-ready"
        )
        future = replace(BASE, last_restart=2000, failures=2)
        self.assertEqual(WATCH.transition(future, BAD, 1060, 1060).result, "cooldown")
        self.assertGreaterEqual(WATCH.COOLDOWN, 900)

    def test_forward_wall_clock_jump_and_sleep_cannot_shorten_cooldown(self):
        state = replace(BASE, last_restart=1000, last_restart_tick=1000)
        self.assertEqual(WATCH.cooldown_remaining(state, 100000, 1899), 1)
        self.assertEqual(WATCH.cooldown_remaining(state, 100000, 1900), 0)
        self.assertEqual(WATCH.cooldown_remaining(state, 100000, 1060), 840)
        self.assertEqual(WATCH.transition(BASE, BAD, 1062, 1060).result, "wake-grace")

    def test_reboot_rebases_monotonic_cooldown_conservatively(self):
        state = replace(BASE, last_restart=1000, last_restart_tick=1000)
        rebooted = WATCH.transition(state, BAD, 2000, 10)
        self.assertEqual(
            (rebooted.result, rebooted.last_restart_tick), ("wake-grace", 10)
        )
        self.assertEqual(WATCH.cooldown_remaining(rebooted, 2000, 10), 900)
        self.assertEqual(WATCH.cooldown_remaining(rebooted, 2900, 910), 0)


class Discovery(unittest.TestCase):
    def test_ipv4_ipv6_physical_interfaces_exclude_tunnels_and_local_only(self):
        text = b"".join(
            [
                dictionary("en0", "192.0.2.10"),
                dictionary("en0", "2001:db8::10"),
                dictionary("en7", "198.51.100.2"),
                dictionary("bridge100", "203.0.113.2"),
                dictionary("utun9", "192.0.2.20"),
                dictionary("lo0", "127.0.0.1"),
                dictionary("en8", "fe80::1%en8", "169.254.1.2"),
            ]
        )
        found = WATCH.physical_interfaces(text)
        self.assertEqual(set(found), {"en0", "en7", "bridge100"})
        self.assertEqual(found["en0"], ("192.0.2.10", "2001:db8::10"))
        self.assertEqual(
            WATCH.signature(found), WATCH.signature(dict(reversed(list(found.items()))))
        )

    def test_dynamic_store_queries_only_service_ip_state(self):
        stub = StubCommands()
        stub.dictionaries += [
            dictionary("en7", "198.51.100.2"),
            dictionary("utun3", "203.0.113.2"),
        ]
        with mock.patch.object(WATCH, "run_command", side_effect=stub):
            found = WATCH.discover(time.monotonic() + 20)
        self.assertEqual(set(found), {"en0", "en7"})
        self.assertEqual(len(stub.calls), 2)
        self.assertEqual(
            stub.calls[0][1]["input_data"], f"list {WATCH.SERVICE_KEY}\n".encode()
        )
        self.assertNotIn(
            b"Setup:", b"".join(options["input_data"] for _, options in stub.calls)
        )

    def test_nested_routes_do_not_count_as_extra_services(self):
        stub = StubCommands()
        routes = b"  AdditionalRoutes : <array> {\n    0 : <dictionary> {\n      DestinationAddress : 192.0.2.10\n    }\n  }\n"
        stub.dictionaries = [
            dictionary("en0", "192.0.2.10").replace(
                b"  Addresses", routes + b"  Addresses"
            )
        ]
        with mock.patch.object(WATCH, "run_command", side_effect=stub):
            self.assertEqual(WATCH.discover(time.monotonic() + 20), NETWORK)

    def test_nested_interface_names_do_not_turn_utun_into_physical_interface(self):
        routes = b"  ExcludedRoutes : <array> {\n    0 : <dictionary> {\n      InterfaceName : en9\n    }\n  }\n"
        snapshot = dictionary("utun11", "172.19.0.1").replace(
            b"  InterfaceName", routes + b"  InterfaceName"
        )
        self.assertEqual(WATCH.physical_interfaces(snapshot), {})

    def test_ipv6_keys_and_missing_malformed_or_oversized_snapshots(self):
        ipv6 = WATCH.Result(0, b"subKey [0] = State:/Network/Service/example/IPv6\n")
        good = WATCH.Result(0, dictionary("en5", "2001:db8::2"))
        with mock.patch.object(WATCH, "run_command", side_effect=[ipv6, good]):
            self.assertEqual(
                WATCH.discover(time.monotonic() + 20), {"en5": ("2001:db8::2",)}
            )
        responses = [
            WATCH.Result(),
            WATCH.Result(0, b"No such key\n"),
            WATCH.Result(0, dictionary("en0", "invalid-address")),
        ]
        for response in responses:
            self.assertEqual(self.discover_results([ipv6, response]), {})

    def discover_results(self, responses):
        with mock.patch.object(WATCH, "run_command", side_effect=responses):
            return WATCH.discover(time.monotonic() + 20)

    def test_unknown_service_short_circuits_all_network_access(self):
        stub = StubCommands()
        stub.service = WATCH.Result(0, b"unrecognized\n")
        with mock.patch.object(WATCH, "run_command", side_effect=stub):
            observation = WATCH.observe()
        self.assertEqual(observation, WATCH.Observation())
        self.assertEqual(len(stub.calls), 1)

    def test_missing_interfaces_skips_all_curl_probes(self):
        stub = StubCommands()
        stub.dictionaries = []
        with mock.patch.object(WATCH, "run_command", side_effect=stub):
            observation = WATCH.observe()
        self.assertEqual(observation, WATCH.Observation(service="connected"))
        self.assertEqual(
            [arguments[0] for arguments, _ in stub.calls], [WATCH.SCUTIL, WATCH.SCUTIL]
        )

    def test_network_rechecked_after_reachable_underlay(self):
        after = {"en7": ("198.51.100.2",)}
        stub = StubCommands()
        with (
            mock.patch.object(WATCH, "run_command", side_effect=stub),
            mock.patch.object(WATCH, "discover", side_effect=[NETWORK, after]),
        ):
            observation = WATCH.observe()
        self.assertTrue(observation.changed)
        self.assertEqual(observation.signature, WATCH.signature(after))


class Probes(unittest.TestCase):
    def test_warp_on_and_plus_are_healthy_off_is_failed(self):
        for value in (b"on", b"plus"):
            self.assertEqual(
                WATCH.trace_health(b"ip=192.0.2.1\nwarp=" + value + b"\n"), "healthy"
            )
        self.assertEqual(WATCH.trace_health(b"warp=off\n"), "failed")

    def test_malformed_trace_is_unknown_not_success_or_restart_evidence(self):
        for value in (
            b"",
            b"warp=",
            b"warp=ON",
            b"warp=on\nwarp=off",
            b"warp=plus\nwarp=plus",
            b"<html>warp=on</html>",
            b"ip=192.0.2.1",
            b"warp=on\ninvalid",
            b"\xff",
        ):
            self.assertEqual(WATCH.trace_health(value), "unknown")

    def test_health_is_numeric_verified_https_without_proxy_config_or_dns(self):
        stub = StubCommands()
        stub.health = WATCH.Result(0, b"warp=plus\n\n200")
        with mock.patch.object(WATCH, "run_command", side_effect=stub):
            self.assertEqual(WATCH.warp_health(time.monotonic() + 20), "healthy")
        arguments, options = stub.calls[0]
        self.assertEqual(arguments[:4], ["/usr/bin/curl", "-q", "--noproxy", "*"])
        self.assertIn("https://1.1.1.1/cdn-cgi/trace", arguments)
        self.assertIn("--max-time", arguments)
        self.assertIn("--max-filesize", arguments)
        self.assertEqual(options["limit"], 4096)
        self.assertTrue(
            {
                "-k",
                "--insecure",
                "--location",
                "--netrc",
                "--config",
                "--interface",
            }.isdisjoint(arguments)
        )

    def test_underlay_binds_interface_and_google_fallback_is_pinned_without_dns(self):
        stub = self.fallback_stub()
        with mock.patch.object(WATCH, "run_command", side_effect=stub):
            self.assertEqual(
                WATCH.underlay_health(
                    {"en7": ("198.51.100.2",)}, time.monotonic() + 20
                ),
                "reachable",
            )
        self.assertEqual(len(stub.calls), 2)
        for arguments, _ in stub.calls:
            self.assertIn("if!en7", arguments)
            self.assertIn("--head", arguments)
            self.assertTrue(
                {"--insecure", "-k", "--location", "--netrc", "--proxy"}.isdisjoint(
                    arguments
                )
            )
        google = stub.calls[1][0]
        self.assertEqual(
            google[google.index("--resolve") + 1], "dns.google:443:8.8.8.8"
        )
        self.assertIn("https://dns.google/", google)

    def fallback_stub(self):
        stub = StubCommands()
        stub.underlay[("if!en7", WATCH.TRACE)] = WATCH.Result(7)
        return stub

    def test_underlay_offline_unknown_and_other_interface_fallback(self):
        stub = StubCommands()
        stub.default_underlay = WATCH.Result(28)
        with mock.patch.object(WATCH, "run_command", side_effect=stub):
            self.assertEqual(
                WATCH.underlay_health(NETWORK, time.monotonic() + 20), "offline"
            )
        stub.default_underlay = WATCH.Result(60)
        with mock.patch.object(WATCH, "run_command", side_effect=stub):
            self.assertEqual(
                WATCH.underlay_health(NETWORK, time.monotonic() + 20), "unknown"
            )
        stub.underlay[("if!en7", WATCH.TRACE)] = WATCH.Result(0, b"headers\n200")
        with mock.patch.object(WATCH, "run_command", side_effect=stub):
            self.assertEqual(
                WATCH.underlay_health(
                    {**NETWORK, "en7": ("198.51.100.2",)}, time.monotonic() + 20
                ),
                "reachable",
            )

    def test_http_redirect_or_bad_status_and_transport_errors_are_not_healthy(self):
        responses = [
            WATCH.Result(0, b"warp=on\n301"),
            WATCH.Result(0, b"warp=on\n500"),
            WATCH.Result(60),
            WATCH.Result(),
            WATCH.Result(7),
            WATCH.Result(28),
        ]
        expected = ["unknown", "unknown", "unknown", "unknown", "failed", "failed"]
        for response, health in zip(responses, expected, strict=True):
            self.assertEqual(self.health_result(response), health)

    def health_result(self, response):
        with mock.patch.object(WATCH, "run_command", return_value=response):
            return WATCH.warp_health(time.monotonic() + 20)

    def direct_result(self, proxy, service="connected"):
        stub = StubCommands()
        stub.proxy = proxy
        stub.service = WATCH.Result(0, service.encode() + b"\n")
        with mock.patch.object(WATCH, "run_command", side_effect=stub):
            health = WATCH.warp_health(1040, allow_sfm_direct_probe=True)
        return health, stub.calls

    def test_direct_confirmation_off_is_healthy_on_and_plus_are_failed(self):
        for value, expected in (
            (b"off", "healthy"),
            (b"on", "failed"),
            (b"plus", "failed"),
        ):
            response = WATCH.Result(0, b"warp=" + value + b"\n200")
            health, calls = self.direct_result(response)
            self.assertEqual(health, expected)
            self.assertEqual(len(calls), 3)
            self.assertEqual(calls[-1][0], [WATCH.SCUTIL, "--nc", "status", "SFM"])

    def test_direct_proxy_arguments_are_fixed_verified_and_never_bypassed(self):
        _, calls = self.direct_result(WATCH.Result(0, b"warp=off\n200"))
        self.assertEqual(
            calls[1],
            (
                [
                    "/usr/bin/curl",
                    "-q",
                    "--noproxy",
                    "",
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
                    "--proxy",
                    "socks5h://127.0.0.1:18082",
                    "https://1.1.1.1/cdn-cgi/trace",
                ],
                {"deadline": 1040, "limit": 4096},
            ),
        )
        self.assertEqual(calls[0][0], WATCH.curl_arguments(WATCH.TRACE))
        self.assertEqual(calls[-1][1], {"timeout": 3, "deadline": 1040})

    def test_proxy_errors_and_ambiguous_traces_are_unknown_without_direct_fallback(
        self,
    ):
        responses = [
            WATCH.Result(code) for code in sorted(WATCH.NETWORK_ERRORS | {60, 97})
        ]
        responses += [
            WATCH.Result(),
            WATCH.Result(7, b"warp=off\n200"),
            WATCH.Result(0, b"warp=off\n301"),
            WATCH.Result(0, b"warp=off\n500"),
            WATCH.Result(0, b"warp=off"),
            WATCH.Result(0, b"\n200"),
            WATCH.Result(0, b"warp=OFF\n200"),
            WATCH.Result(0, b"ip=192.0.2.1\n200"),
            WATCH.Result(0, b"warp=off\nwarp=off\n200"),
            WATCH.Result(0, b"warp=off\nwarp=on\n200"),
            WATCH.Result(0, b"warp=plus\nwarp=plus\n200"),
            WATCH.Result(0, b"warp=off\ninvalid\n200"),
            WATCH.Result(0, b"\xff\n200"),
        ]
        for response in responses:
            health, calls = self.direct_result(response)
            self.assertEqual(health, "unknown", response)
            self.assertEqual(len(calls), 2)
            self.assertIn("--proxy", calls[-1][0])

    def test_service_changes_after_proxy_cannot_confirm_direct_or_failure(self):
        for service in ("disconnected", "connecting", "disconnecting", "unknown"):
            off = self.direct_result(WATCH.Result(0, b"warp=off\n200"), service)
            on = self.direct_result(WATCH.Result(0, b"warp=on\n200"), service)
            self.assertEqual((off[0], on[0]), ("unknown", "unknown"))

    def test_opt_in_does_not_rescue_transport_errors_or_probe_other_system_results(
        self,
    ):
        responses = [WATCH.Result(code) for code in sorted(WATCH.NETWORK_ERRORS)]
        expected = ["failed"] * len(responses)
        responses += [
            WATCH.Result(0, b"warp=on\n200"),
            WATCH.Result(0, b"warp=plus\n200"),
            WATCH.Result(0, b"warp=off\nwarp=off\n200"),
            WATCH.Result(0, b"warp=off\n301"),
            WATCH.Result(0, b"warp=off\n500"),
            WATCH.Result(60, b"warp=off\n200"),
            WATCH.Result(),
        ]
        expected += [
            "healthy",
            "healthy",
            "unknown",
            "unknown",
            "unknown",
            "unknown",
            "unknown",
        ]
        for response, health in zip(responses, expected, strict=True):
            self.assert_system_result_without_proxy(response, health)

    def assert_system_result_without_proxy(self, response, expected):
        with mock.patch.object(WATCH, "run_command", return_value=response) as runner:
            health = WATCH.warp_health(1040, allow_sfm_direct_probe=True)
        self.assertEqual(health, expected)
        runner.assert_called_once_with(
            WATCH.curl_arguments(WATCH.TRACE), deadline=1040, limit=4096
        )

    def test_direct_confirmation_requires_opt_in_and_connected_initial_service(self):
        for enabled, service in ((False, "connected"), (True, "disconnected")):
            stub = StubCommands()
            stub.service = WATCH.Result(0, service.encode() + b"\n")
            self.assert_observation_without_proxy(stub, enabled)

    def assert_observation_without_proxy(self, stub, enabled):
        with mock.patch.object(WATCH, "run_command", side_effect=stub):
            observation = WATCH.observe(allow_sfm_direct_probe=enabled)
        self.assertEqual(observation.health, "failed")
        self.assertEqual(observation.underlay, "reachable")
        self.assertFalse(any("--proxy" in arguments for arguments, _ in stub.calls))

    def test_direct_observation_shares_deadline_and_skips_underlay(self):
        stub = StubCommands()
        with (
            mock.patch.object(WATCH, "run_command", side_effect=stub),
            mock.patch.object(WATCH.time, "monotonic", return_value=1000),
        ):
            observation = WATCH.observe(allow_sfm_direct_probe=True)
        self.assertEqual(
            observation, replace(BAD, health="healthy", underlay="unknown")
        )
        self.assertEqual(len(stub.calls), 6)
        self.assertEqual({options["deadline"] for _, options in stub.calls}, {1040})
        self.assertFalse(any("--interface" in arguments for arguments, _ in stub.calls))

    def test_expired_direct_probe_deadline_never_launches_a_process(self):
        with mock.patch.object(WATCH.subprocess, "Popen") as popen:
            self.assertEqual(WATCH.sfm_direct_health(0), "unknown")
        popen.assert_not_called()

    def test_direct_and_warp_path_changes_do_not_cache_previous_health(self):
        stub = StubCommands()
        with mock.patch.object(WATCH, "run_command", side_effect=stub):
            direct = WATCH.observe(allow_sfm_direct_probe=True)
            stub.proxy = WATCH.Result(0, b"warp=on\n200")
            mismatch = WATCH.observe(allow_sfm_direct_probe=True)
            stub.health = WATCH.Result(0, b"warp=on\n200")
            warp = WATCH.observe(allow_sfm_direct_probe=True)
        state = WATCH.transition(replace(BASE, failures=2), direct, 1060, 1060)
        self.assertEqual((state.health, state.failures), ("healthy", 0))
        state = WATCH.transition(state, mismatch, 1120, 1120)
        self.assertEqual((state.health, state.failures), ("failed", 1))
        state = WATCH.transition(state, warp, 1180, 1180)
        self.assertEqual((state.health, state.failures), ("healthy", 0))


class Runtime(Fixture):
    def setUp(self):
        super().setUp()
        self.store = self.enterContext(WATCH.Store(self.state_root))
        self.store.save(replace(BASE, failures=2))
        self.enterContext(mock.patch.object(WATCH.sys, "platform", "darwin"))
        self.enterContext(mock.patch.object(WATCH.time, "time", return_value=1060))
        self.enterContext(mock.patch.object(WATCH.time, "monotonic", return_value=1060))
        self.real_observe = WATCH.observe
        self.observation = self.enterContext(
            mock.patch.object(WATCH, "observe", return_value=BAD)
        )
        self.service = self.enterContext(
            mock.patch.object(WATCH, "service_status", return_value="connected")
        )
        self.commands = self.enterContext(
            mock.patch.object(WATCH, "run_command", return_value=WATCH.Result(0))
        )

    def test_successful_restart_uses_only_persisted_service_commands(self):
        code, result = self.invoke("check")
        self.assertEqual((code, result["result"]), (0, "restarted"))
        self.assertEqual(
            [call.args[0] for call in self.commands.call_args_list],
            [
                ["/usr/sbin/scutil", "--nc", "stop", "SFM"],
                ["/usr/sbin/scutil", "--nc", "start", "SFM"],
            ],
        )
        self.assertEqual(
            (self.store.load().last_restart, result["cooldown_remaining"]), (1060, 900)
        )

    def test_disconnected_service_starts_without_stopping(self):
        self.service.return_value = "disconnected"
        self.observation.return_value = replace(BAD, service="disconnected")
        self.assertEqual(self.invoke("check")[1]["result"], "restarted")
        self.commands.assert_called_once_with(
            ["/usr/sbin/scutil", "--nc", "start", "SFM"],
            timeout=5,
        )
        self.assertEqual(self.store.load().last_restart, 1060)

    def test_disconnected_start_failure_also_precommits_cooldown(self):
        self.service.return_value = "disconnected"
        self.commands.side_effect = self.assert_recorded
        self.assertEqual(self.invoke("check")[1]["result"], "start-failed")
        self.commands.assert_called_once_with(
            ["/usr/sbin/scutil", "--nc", "start", "SFM"],
            timeout=5,
        )
        self.assertEqual(self.store.load().last_restart, 1060)

    def assert_recorded(self, arguments, **options):
        state = self.store.load()
        self.assertEqual(
            (state.result, state.last_restart, state.failures),
            ("restart-attempt", 1060, 0),
        )
        return WATCH.Result(1)

    def test_stop_failure_keeps_precommitted_cooldown_and_never_starts(self):
        self.commands.side_effect = self.assert_recorded
        _, result = self.invoke("check")
        self.assertEqual(result["result"], "stop-failed")
        self.assertEqual(self.commands.call_count, 1)
        self.commands.reset_mock()
        _, result = self.invoke("check")
        self.assertEqual(result["result"], "cooldown")
        self.commands.assert_not_called()

    def test_start_failure_and_crash_leave_cooldown_on_disk(self):
        self.commands.side_effect = [WATCH.Result(0), WATCH.Result(1)]
        self.assertEqual(self.invoke("check")[1]["result"], "start-failed")
        self.assertEqual(self.store.load().last_restart, 1060)
        self.store.save(replace(BASE, failures=2))
        self.commands.side_effect = RuntimeError("synthetic termination")
        with self.assertRaises(RuntimeError):
            self.invoke("check")
        self.assertEqual(
            (self.store.load().result, self.store.load().last_restart),
            ("restart-attempt", 1060),
        )
        self.assertEqual(
            WATCH.transition(self.store.load(), BAD, 1120, 1120).result, "cooldown"
        )

    def test_pause_before_and_during_probe_prevents_restart(self):
        self.assertEqual(self.invoke("pause")[1]["result"], "paused")
        self.assertEqual(self.invoke("check")[1]["result"], "paused")
        self.observation.assert_not_called()
        self.invoke("resume")
        self.store.save(replace(BASE, failures=2))
        self.observation.side_effect = self.pause_in_probe
        self.assertEqual(self.invoke("check")[1]["result"], "paused")
        self.assertEqual(self.store.load().failures, 0)
        self.commands.assert_not_called()

    def pause_in_probe(self, allow_sfm_direct_probe=False):
        WATCH.atomic_write(self.store.fd, "paused", b"")
        return BAD

    def test_pause_after_cooldown_commit_and_between_stop_start(self):
        original = WATCH.Store.save

        def save_and_pause(store, state):
            original(store, state)
            WATCH.atomic_write(store.fd, "paused", b"")

        with mock.patch.object(WATCH.Store, "save", new=save_and_pause):
            self.assertEqual(self.invoke("check")[1]["result"], "paused")
        self.commands.assert_not_called()
        self.invoke("resume")
        self.store.save(replace(BASE, failures=2))
        self.commands.side_effect = self.pause_at_stop
        self.assertEqual(self.invoke("check")[1]["result"], "paused")
        self.assertEqual(self.commands.call_count, 1)
        self.assertEqual(self.store.load().last_restart, 1060)

    def pause_at_stop(self, arguments, **options):
        WATCH.atomic_write(self.store.fd, "paused", b"")
        return WATCH.Result(0)

    def test_resume_resets_streak_and_grants_grace(self):
        self.invoke("pause")
        _, result = self.invoke("resume")
        self.assertFalse(self.store.paused())
        self.assertEqual(
            (result["result"], result["failures"], result["grace_remaining"]),
            ("resumed", 0, 60),
        )
        self.commands.assert_not_called()

    def test_overlap_excludes_check_probe_and_resume_but_not_pause(self):
        with WATCH.check_lock(self.store) as acquired:
            self.assertTrue(acquired)
            self.assertEqual(self.invoke("check")[1]["result"], "busy")
            self.assertEqual(self.invoke("probe")[1]["result"], "busy")
            self.assertEqual(self.invoke("pause")[1]["result"], "paused")
            self.assertEqual(self.invoke("resume")[1]["result"], "busy")
        self.assertTrue(self.store.paused())
        self.observation.assert_not_called()
        self.commands.assert_not_called()

    def test_probe_and_status_do_not_change_policy_or_restart(self):
        before = (self.state_root / "state.json").read_bytes()
        self.assertEqual(self.invoke("probe")[1]["result"], "probe")
        _, result = self.invoke("status")
        self.assertEqual(result["failures"], 2)
        self.assertEqual((self.state_root / "state.json").read_bytes(), before)
        self.commands.assert_not_called()
        self.assertNotIn(SIGNATURE, json.dumps(result))
        self.assertNotIn("192.0.2.10", json.dumps(result))

    def test_unknown_service_before_restart_skips_mutation(self):
        self.service.return_value = "unknown"
        self.assertEqual(self.invoke("check")[1]["result"], "service-unknown")
        self.assertEqual(self.store.load().failures, 0)
        self.commands.assert_not_called()

    def test_cli_direct_probe_flag_propagates_to_check_and_probe_only(self):
        self.observation.return_value = replace(BAD, health="healthy")
        cases = [
            ("check", (), False),
            ("probe", (), False),
            ("check", ("--allow-sfm-direct-probe",), True),
            ("probe", ("--allow-sfm-direct-probe",), True),
        ]
        for action, options, enabled in cases:
            self.observation.reset_mock()
            self.assertEqual(self.invoke(action, *options)[0], 0)
            self.observation.assert_called_once_with(allow_sfm_direct_probe=enabled)
        self.observation.reset_mock()
        for action in ("status", "pause", "resume"):
            self.assertEqual(self.invoke(action, "--allow-sfm-direct-probe")[0], 0)
        self.observation.assert_not_called()
        self.commands.assert_not_called()

    def test_opted_in_paused_check_skips_all_observation(self):
        self.invoke("pause")
        _, report = self.invoke("check", "--allow-sfm-direct-probe")
        self.assertEqual(report["result"], "paused")
        self.observation.assert_not_called()
        self.commands.assert_not_called()

    def test_pause_during_opted_in_observation_still_prevents_repair(self):
        self.observation.side_effect = self.pause_in_probe
        _, report = self.invoke("check", "--allow-sfm-direct-probe")
        self.assertEqual((report["result"], report["failures"]), ("paused", 0))
        self.observation.assert_called_once_with(allow_sfm_direct_probe=True)
        self.commands.assert_not_called()

    def test_proxy_failures_reset_existing_streak_without_underlay_or_repair(self):
        for response in (
            WATCH.Result(7),
            WATCH.Result(60),
            WATCH.Result(0, b"bad\n200"),
        ):
            self.assert_unknown_proxy_checks(response)

    def assert_unknown_proxy_checks(self, response):
        stub = StubCommands()
        stub.proxy = response
        self.commands.side_effect = stub
        self.observation.side_effect = self.real_observe
        self.store.save(replace(BASE, failures=2))
        for _ in range(3):
            _, report = self.invoke("check", "--allow-sfm-direct-probe")
            self.assertEqual((report["health"], report["failures"]), ("unknown", 0))
            self.assertEqual(report["result"], "health-unknown")
            self.assertEqual(report["last_restart"], 0)
        self.assertFalse(any("--interface" in arguments for arguments, _ in stub.calls))
        self.assertFalse(any("--nc" in arguments for arguments, _ in stub.calls))

    def test_confirmed_direct_check_is_healthy_without_schema_or_report_changes(self):
        self.commands.side_effect = StubCommands()
        self.observation.side_effect = self.real_observe
        before = set(asdict(self.store.load()))
        _, report = self.invoke("check", "--allow-sfm-direct-probe")
        self.assertEqual((report["result"], report["failures"]), ("healthy", 0))
        self.assertEqual(report["last_restart"], 0)
        self.assertEqual(set(asdict(self.store.load())), before)
        self.assertNotIn("127.0.0.1", json.dumps(report))
        self.assertNotIn("socks5h", json.dumps(report))

    def test_service_change_during_direct_probe_resets_streak_without_repair(self):
        self.commands.side_effect = StubCommands()
        self.observation.side_effect = self.real_observe
        self.service.side_effect = ["connected", "disconnected"]
        _, report = self.invoke("check", "--allow-sfm-direct-probe")
        self.assertEqual((report["result"], report["failures"]), ("health-unknown", 0))
        self.assertEqual(report["last_restart"], 0)


class Storage(Fixture):
    def test_default_and_xdg_paths(self):
        with mock.patch.dict(os.environ, {"HOME": self.env["HOME"]}, clear=True):
            self.assertEqual(
                WATCH.state_directory(),
                Path(self.env["HOME"]) / ".local/state/sfm-warp-maintenance",
            )
        with mock.patch.dict(os.environ, self.env, clear=True):
            self.assertEqual(WATCH.state_directory(), self.state_root)
        with (
            mock.patch.dict(os.environ, {"XDG_STATE_HOME": "relative"}, clear=True),
            self.assertRaises(WATCH.UnsafeState),
        ):
            WATCH.state_directory()

    def test_private_modes_atomic_replacement_and_bounded_state(self):
        store = self.enterContext(WATCH.Store(self.state_root))
        store.save(BASE)
        self.invoke("pause")
        with WATCH.check_lock(store) as acquired:
            self.assertTrue(acquired)
        self.assertEqual(stat.S_IMODE(self.state_root.stat().st_mode), 0o700)
        for name in ("state.json", "paused", "check.lock"):
            self.assertEqual(
                stat.S_IMODE((self.state_root / name).stat().st_mode), 0o600
            )
        before = (self.state_root / "state.json").read_bytes()
        with (
            mock.patch.object(WATCH.os, "replace", side_effect=OSError("synthetic")),
            self.assertRaises(OSError),
        ):
            store.save(replace(BASE, failures=2))
        self.assertEqual((self.state_root / "state.json").read_bytes(), before)
        self.assertEqual(
            sorted(path.name for path in self.state_root.iterdir()),
            ["check.lock", "paused", "state.json"],
        )
        self.assertLess(len(before), WATCH.STATE_LIMIT)

    def test_invalid_state_fails_closed_without_probes(self):
        store = self.enterContext(WATCH.Store(self.state_root))
        self.enterContext(mock.patch.object(WATCH.sys, "platform", "darwin"))
        malformed = [b"{", b"[]", b"x" * (WATCH.STATE_LIMIT + 1)]
        malformed += [
            json.dumps({**asdict(BASE), key: value}).encode()
            for key, value in (
                ("failures", True),
                ("failures", 4),
                ("last_restart", float("nan")),
                ("last_restart", -1),
                ("last_restart", 10**500),
                ("signature", "raw-address"),
                ("result", "raw-response"),
            )
        ]
        runner = self.enterContext(
            mock.patch.object(
                WATCH, "observe", side_effect=AssertionError("live probe")
            )
        )
        for data in malformed:
            WATCH.atomic_write(store.fd, "state.json", data)
            self.assertEqual(
                self.invoke("status"), (1, {"result": "state-unavailable"})
            )
            self.assertEqual(self.invoke("check"), (1, {"result": "state-unavailable"}))
        self.assertEqual(self.invoke("pause")[1]["result"], "paused")
        runner.assert_not_called()

    def test_symlink_directory_state_and_lock_are_rejected(self):
        destination = self.root / "destination"
        destination.mkdir()
        link = self.root / "linked"
        link.symlink_to(destination, target_is_directory=True)
        with self.assertRaises(OSError):
            WATCH.Store(link).__enter__()
        store = self.enterContext(WATCH.Store(self.state_root))
        target = self.root / "synthetic-private-file"
        target.write_bytes(b"synthetic untouched")
        for name in ("state.json", "check.lock"):
            (self.state_root / name).symlink_to(target)
            self.assertEqual(
                self.invoke("status" if name == "state.json" else "resume")[0], 1
            )
            (self.state_root / name).unlink()
        self.assertEqual(target.read_bytes(), b"synthetic untouched")
        (self.state_root / "paused").symlink_to(target)
        self.assertTrue(store.paused())

    def test_hardlinked_state_and_fifo_are_rejected_before_reading(self):
        store = self.enterContext(WATCH.Store(self.state_root))
        target = self.root / "synthetic-file"
        target.write_bytes(b"synthetic untouched")
        state_path = self.state_root / "state.json"
        os.link(target, state_path)
        with self.assertRaises(WATCH.UnsafeState):
            store.load()
        state_path.unlink()
        os.mkfifo(state_path)
        with self.assertRaises(WATCH.UnsafeState):
            store.load()
        self.assertEqual(target.read_bytes(), b"synthetic untouched")


class Safety(Fixture):
    def test_command_runner_scrubs_environment_stdin_and_discards_stderr(self):
        script = "import json,os,sys; print(json.dumps(dict(os.environ))); print('synthetic raw response',file=sys.stderr)"
        poison = {
            "HTTPS_PROXY": "synthetic",
            "CURL_HOME": "/synthetic",
            "SSLKEYLOGFILE": "/synthetic",
        }
        with mock.patch.dict(os.environ, poison):
            result = WATCH.run_command([sys.executable, "-IS", "-c", script])
        self.assertEqual(result.code, 0)
        environment = json.loads(result.output)
        # CoreFoundation adds this process-local encoding hint on Darwin.
        environment.pop("__CF_USER_TEXT_ENCODING", None)
        self.assertEqual(environment, WATCH.CLEAN_ENV)
        echo = WATCH.run_command(
            [
                sys.executable,
                "-IS",
                "-c",
                "import sys;sys.stdout.buffer.write(sys.stdin.buffer.read())",
            ],
            input_data=b"synthetic",
        )
        self.assertEqual(echo, WATCH.Result(0, b"synthetic"))

    def test_command_output_time_and_global_deadline_are_bounded(self):
        output = WATCH.run_command(
            [sys.executable, "-IS", "-c", "print('x'*1000000)"], limit=128
        )
        self.assertEqual(output, WATCH.Result())
        start = time.monotonic()
        result = WATCH.run_command(
            [sys.executable, "-IS", "-c", "import time;time.sleep(5)"], timeout=0.1
        )
        self.assertEqual(result, WATCH.Result())
        self.assertLess(time.monotonic() - start, 2)
        with mock.patch.object(WATCH.subprocess, "Popen") as popen:
            self.assertEqual(
                WATCH.run_command(["unexecuted"], deadline=0), WATCH.Result()
            )
            self.assertEqual(
                WATCH.run_command(["unexecuted"], input_data=b"x" * 4097),
                WATCH.Result(),
            )
        popen.assert_not_called()

    def test_only_fixed_noncredential_commands_and_no_network_details_in_reports(self):
        stub = StubCommands()
        with mock.patch.object(WATCH, "run_command", side_effect=stub):
            observation = WATCH.observe()
        self.assertEqual(observation.underlay, "reachable")
        source = SOURCE.read_text()
        for forbidden in (
            "wgcf",
            ".config/sfm-warp",
            "keychain",
            "security find",
            "--insecure",
            "netrc",
            "launchctl",
        ):
            self.assertNotIn(forbidden, source)
        rendered = json.dumps(
            WATCH.report(WATCH.transition(BASE, observation, 1060, 1060), False)
        )
        for private in ("192.0.2.10", "https://", SIGNATURE, "<dictionary>"):
            self.assertNotIn(private, rendered)
        self.assertEqual(
            {arguments[0] for arguments, _ in stub.calls}, {WATCH.SCUTIL, WATCH.CURL}
        )

    def test_python_statement_indentation_is_at_most_three_levels(self):
        for source in (SOURCE, Path(__file__)):
            statements = [
                node
                for node in ast.walk(ast.parse(source.read_text()))
                if isinstance(node, ast.stmt)
            ]
            self.assertLessEqual(
                max(node.col_offset for node in statements), 12, str(source)
            )

    def test_runtime_file_access_is_only_private_state(self):
        store = self.enterContext(WATCH.Store(self.state_root))
        store.save(BASE)
        opened = []
        original = os.open

        def guarded(path, flags, mode=0o777, *, dir_fd=None):
            opened.append((path, dir_fd))
            return original(path, flags, mode, dir_fd=dir_fd)

        with mock.patch.object(WATCH.os, "open", side_effect=guarded):
            self.invoke("pause")
            self.invoke("status")
        for path, directory in opened:
            permitted = path == self.state_root or (
                directory is not None and str(path) in {"state.json"}
            )
            self.assertTrue(
                permitted
                or (
                    directory is not None
                    and re.fullmatch(r"\.paused-[a-f0-9]{16}", str(path))
                )
            )


def nix_fixture(root: Path, system: str) -> str:
    return f'''
let
  flake = builtins.getFlake "git+file://{REPO}";
  pkgs = flake.inputs.nixpkgs.legacyPackages.{system};
  fixture = {{
    home.username = "sfm-fixture";
    home.homeDirectory = "{root}/home";
    home.stateVersion = "26.05";
    xdg.stateHome = "{root}/state";
  }};
  home = flake.inputs.home-manager.lib.homeManagerConfiguration {{
    inherit pkgs;
    modules = [ {MODULE} fixture ];
  }};
  watches = builtins.filter (p: (p.name or "") == "sfm-watch") home.config.home.packages;
'''


class NixModule(Fixture):
    def nix(self, arguments, expression):
        self.assertIsNotNone(NIX, "nix is required for the isolated module contract")
        result = subprocess.run(
            [
                str(NIX),
                "--extra-experimental-features",
                "nix-command flakes",
                *arguments,
                "--impure",
                "--expr",
                expression,
            ],
            capture_output=True,
            text=True,
            timeout=240,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def test_darwin_agent_interval_wrapper_and_source_only_store_input(self):
        expression = nix_fixture(self.root, "aarch64-darwin")
        result = json.loads(
            self.nix(
                ["eval", "--json"],
                expression
                + """
in {
  packages = builtins.length watches;
  agent = home.config.launchd.agents.sfm-warp-watch;
}
""",
            )
        )
        self.assertEqual(result["packages"], 1)
        agent = result["agent"]
        self.assertTrue(agent["enable"])
        self.assertFalse(agent["waitForNixStore"])
        self.assertEqual(agent["config"]["StartInterval"], 60)
        self.assertTrue(agent["config"]["RunAtLoad"])
        self.assertEqual(
            agent["config"]["ProgramArguments"][1:],
            ["check", "--allow-sfm-direct-probe"],
        )
        self.assertEqual(
            agent["config"]["EnvironmentVariables"]["XDG_STATE_HOME"],
            str(self.root / "state"),
        )
        self.assertIsNone(agent["config"].get("StandardOutPath"))
        self.assertIsNone(agent["config"].get("StandardErrorPath"))
        if sys.platform != "darwin":
            return
        package = Path(
            self.nix(
                ["build", "--no-link", "--print-out-paths"],
                expression + "in builtins.head watches",
            )
        )
        wrapper = package / "bin/sfm-watch"
        match = re.search(
            r'exec (\S+)/bin/python3 -IS (\S+) "\$@"', wrapper.read_text()
        )
        self.assertIsNotNone(match)
        assert match is not None
        self.assertEqual(Path(match[2]).read_bytes(), SOURCE.read_bytes())
        result = subprocess.run(
            [wrapper, "status"],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["result"], "never")

    def test_linux_module_has_no_watchdog_package_or_agent(self):
        expression = (
            nix_fixture(self.root, "x86_64-linux")
            + """
in {
  packages = builtins.length watches;
  agent = builtins.hasAttr "sfm-warp-watch" home.config.launchd.agents;
}
"""
        )
        result = json.loads(self.nix(["eval", "--json"], expression))
        self.assertEqual(result, {"packages": 0, "agent": False})


if __name__ == "__main__":
    unittest.main()
