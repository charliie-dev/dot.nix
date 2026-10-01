"""Synthetic GL-XE3000 profile contracts; never opens a user's SFM profile."""

from __future__ import annotations

import ast
import base64
import copy
import importlib.util
import io
import ipaddress
import json
import os
import re
import stat
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "conf.d/sfm-warp-maintenance/gl_profile.py"
SPEC = importlib.util.spec_from_file_location("sfm_gl_profile", SOURCE)
assert SPEC is not None and SPEC.loader is not None
PROFILE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROFILE)
SSID = "GL-XE3000-b04-5G"
NETWORKS = ["192.168.8.0/24", "fd40:ffeb:eb06::/64"]
INTERFACE_ADDRESSES = ("192.168.8.246/24", "fd40:ffeb:eb06::1234/64")
BINARY = os.environ.get("SFM_PROFILE_TEST_BINARY")


def fixture() -> dict:
    return {
        "log": {"level": "error", "timestamp": True},
        "dns": {
            "servers": [
                {"type": "udp", "tag": "bootstrap", "server": "127.0.0.1"},
                {
                    "type": "https",
                    "tag": "adguard",
                    "server": "127.0.0.1",
                    "server_port": 443,
                    "path": "/SYNTHETIC_PRIVATE_SENTINEL/dns-query",
                    "tls": {"enabled": True, "server_name": "dns.example.invalid"},
                    "detour": "warp",
                },
            ],
            "rules": [{"domain": ["router.lan"], "server": "bootstrap"}],
            "final": "adguard",
            "strategy": "ipv4_only",
        },
        "inbounds": [
            {
                "type": "tun",
                "tag": "tun-in",
                "address": ["172.19.0.1/30"],
                "auto_route": True,
            }
        ],
        "outbounds": [{"type": "direct", "tag": "direct"}],
        "endpoints": [
            {
                "type": "wireguard",
                "tag": "warp",
                "system": False,
                "address": ["172.16.0.2/32"],
                "bind_interface": "lo0",
                "private_key": base64.b64encode(bytes([1]) * 32).decode(),
                "peers": [
                    {
                        "address": "127.0.0.1",
                        "port": 2408,
                        "public_key": base64.b64encode(bytes([2]) * 32).decode(),
                        "allowed_ips": ["0.0.0.0/0"],
                        "reserved": [201, 87, 19],
                    }
                ],
            }
        ],
        "route": {
            "auto_detect_interface": True,
            "default_domain_resolver": "bootstrap",
            "final": "warp",
            "rules": [
                {"action": "sniff"},
                {"protocol": "dns", "action": "hijack-dns"},
                {"action": "resolve", "strategy": "ipv4_only"},
                {"ip_is_private": True, "outbound": "direct"},
                {
                    "ip_cidr": ["100.64.0.0/10", "fd7a:115c:a1e0::/48"],
                    "outbound": "direct",
                },
                {
                    "domain_suffix": list(PROFILE.YOUTUBE_SUFFIXES),
                    "domain": list(PROFILE.YOUTUBE_DOMAINS),
                    "ip_version": 4,
                    "outbound": "direct",
                },
            ],
        },
    }


def prefixes_overlap(first: str, second: str) -> bool:
    left = ipaddress.ip_network(first, strict=False)
    right = ipaddress.ip_network(second, strict=False)
    return (
        left.version == right.version
        and int(left.network_address) <= int(right.broadcast_address)
        and int(right.network_address) <= int(left.broadcast_address)
    )


def matches(rule: dict, **traffic) -> bool:
    if rule.get("type") == "logical":
        outcomes = [matches(child, **traffic) for child in rule["rules"]]
        result = all(outcomes) if rule["mode"] == "and" else any(outcomes)
    else:
        result = matches_default(rule, **traffic)
    return not result if rule.get("invert", False) else result


def matches_default(
    rule: dict,
    *,
    ssid=SSID,
    network_type="wifi",
    domain="",
    address="8.8.4.4",
    port=443,
    network="tcp",
    inbound="tun-in",
    query_type="A",
    interface_addresses=INTERFACE_ADDRESSES,
) -> bool:
    values = {
        "wifi_ssid": ssid,
        "network_type": network_type,
        "network": network,
        "inbound": inbound,
        "port": port,
        "query_type": query_type,
    }
    for field, value in values.items():
        allowed = rule.get(field, value)
        if allowed == []:
            continue
        if value not in (allowed if isinstance(allowed, list) else [allowed]):
            return False
    if not all(
        any(prefixes_overlap(prefix, local) for local in interface_addresses)
        for prefix in rule.get("default_interface_address", [])
    ):
        return False
    ip = ipaddress.ip_address(address)
    if rule.get("ip_version", ip.version) != ip.version:
        return False
    if "ip_is_private" in rule and rule["ip_is_private"] != ip.is_private:
        return False
    if PROFILE.strings(rule.get("ip_cidr")):
        return any(
            ip in ipaddress.ip_network(cidr)
            for cidr in PROFILE.strings(rule["ip_cidr"])
        )
    if not any(
        PROFILE.strings(rule.get(field))
        for field in ("domain", "domain_suffix", "domain_regex")
    ):
        return True
    exact = domain in PROFILE.strings(rule.get("domain"))
    suffix = any(
        domain == name or domain.endswith("." + name)
        for name in PROFILE.strings(rule.get("domain_suffix"))
    )
    regex = any(
        re.search(pattern, domain)
        for pattern in PROFILE.strings(rule.get("domain_regex"))
    )
    return exact or suffix or regex


def dns_server(profile: dict, **traffic) -> str:
    for rule in profile["dns"]["rules"]:
        if not matches(rule, **traffic):
            continue
        action = rule.get("action", "route")
        if action == "route":
            return rule["server"]
        if action in {"reject", "predefined"}:
            return action
    return profile["dns"]["final"]


def routed(profile: dict, **traffic) -> str:
    for rule in profile["route"]["rules"]:
        action = rule.get("action", "route")
        if action in {"route", "reject"} and matches(rule, **traffic):
            return "reject" if action == "reject" else rule["outbound"]
    return profile["route"]["final"]


class Build(unittest.TestCase):
    def test_full_source_preservation_and_exact_dns_clone(self):
        source = fixture()
        original = PROFILE.canonical(source)
        generated = PROFILE.build_profile(source, SSID, "warp", "warp")
        self.assertEqual(PROFILE.canonical(source), original)
        restored = copy.deepcopy(generated)
        restored["inbounds"].pop()
        clone = restored["dns"]["servers"].pop()
        restored["dns"]["rules"].pop()
        restored["route"]["rules"] = source["route"]["rules"]
        self.assertEqual(PROFILE.canonical(restored), original)
        expected = copy.deepcopy(source["dns"]["servers"][-1])
        expected["tag"] = PROFILE.DNS_TAG
        del expected["detour"]
        self.assertEqual(PROFILE.canonical(clone), PROFILE.canonical(expected))
        self.assertEqual(clone["path"], "/SYNTHETIC_PRIVATE_SENTINEL/dns-query")
        self.assertNotIn("detour", clone)
        generated["endpoints"][0]["peers"][0]["reserved"][0] = 0
        self.assertEqual(PROFILE.canonical(source), original)

    def test_canonical_comparison_distinguishes_boolean_and_integer(self):
        self.assertNotEqual(
            PROFILE.canonical({"value": True}), PROFILE.canonical({"value": 1})
        )
        source = fixture()
        source["route"]["auto_detect_interface"] = 1
        self.assertRaises(PROFILE.ProfileError, PROFILE.build_profile, source, SSID)

    def test_exact_rule_order_and_condition_consistency(self):
        source = fixture()
        generated = PROFILE.build_profile(source, SSID, "warp", "warp")
        rules = generated["route"]["rules"]
        self.assertEqual(
            PROFILE.canonical(rules[3:8]),
            PROFILE.canonical(source["route"]["rules"][:5]),
        )
        self.assertEqual(
            PROFILE.canonical(rules[11:]),
            PROFILE.canonical(source["route"]["rules"][5:]),
        )
        self.assertEqual(rules[8]["domain_suffix"], list(PROFILE.YOUTUBE_SUFFIXES))
        self.assertEqual(rules[8]["domain"], list(PROFILE.YOUTUBE_DOMAINS))
        self.assertEqual(rules[9]["domain_suffix"], list(PROFILE.GITHUB_SUFFIXES))
        self.assertEqual(rules[10]["outbound"], "direct")
        for rule in [rules[0], *rules[8:11], generated["dns"]["rules"][-1]]:
            self.assertEqual(rule["wifi_ssid"], [SSID])
            self.assertEqual(rule["network_type"], ["wifi"])
        self.assertEqual(generated["dns"]["rules"][:-1], source["dns"]["rules"])
        self.assertEqual(generated["dns"]["final"], source["dns"]["final"])

    def test_probe_listener_and_complete_guarded_block(self):
        profile = PROFILE.build_profile(fixture(), SSID)
        self.assertEqual(
            profile["inbounds"][-1],
            {
                "type": "socks",
                "tag": "maintenance-probe",
                "listen": "127.0.0.1",
                "listen_port": 18082,
            },
        )
        self.assertEqual(
            profile["route"]["rules"][2],
            {
                "inbound": ["maintenance-probe"],
                "action": "reject",
                "method": "default",
                "no_drop": True,
            },
        )
        cases = [
            ({"address": "1.1.1.1"}, "direct"),
            ({"address": "1.1.1.1", "ssid": "other"}, "warp"),
            ({"address": "1.1.1.1", "ssid": SSID.lower()}, "warp"),
            ({"address": "1.1.1.1", "network_type": "ethernet"}, "warp"),
            ({"address": "1.1.1.1", "port": 80}, "reject"),
            ({"address": "1.1.1.1", "network": "udp"}, "reject"),
            ({"address": "1.0.0.1"}, "reject"),
            ({"address": "127.0.0.1"}, "reject"),
            ({"address": "::1"}, "reject"),
        ]
        for traffic, expected in cases:
            self.assertEqual(
                routed(profile, inbound=PROFILE.PROBE_TAG, **traffic), expected
            )

    def test_target_exceptions_and_non_target_original_behavior(self):
        profile = PROFILE.build_profile(fixture(), SSID, "warp", "warp")
        for domain in (
            *PROFILE.YOUTUBE_SUFFIXES,
            *PROFILE.YOUTUBE_DOMAINS,
            *PROFILE.GITHUB_SUFFIXES,
        ):
            self.assertEqual(routed(profile, domain=domain), "warp")
        self.assertEqual(routed(profile, domain="cdn.googlevideo.com"), "warp")
        self.assertEqual(routed(profile, domain="notyoutube.com"), "direct")
        self.assertEqual(
            routed(profile, domain="other.youtubei.googleapis.com"), "direct"
        )
        self.assertEqual(
            routed(profile, domain="github.com", address="100.64.0.1"), "direct"
        )
        self.assertEqual(
            routed(profile, domain="github.com", address="192.168.8.1"), "direct"
        )
        self.assertEqual(routed(profile, domain="youtube.com", ssid="other"), "direct")
        self.assertEqual(routed(profile, domain="github.com", ssid="other"), "warp")
        self.assertEqual(
            routed(profile, domain="example.com", ssid=SSID.lower()), "warp"
        )
        self.assertEqual(
            routed(profile, domain="example.com", network_type="ethernet"), "warp"
        )
        direct = PROFILE.build_profile(fixture(), SSID)
        self.assertEqual(routed(direct, domain="github.com"), "direct")
        self.assertEqual(routed(direct, domain="youtube.com"), "direct")

    def test_youtube_fallback_rule_is_optional_and_combined_private_rule_supported(
        self,
    ):
        source = fixture()
        source["route"]["rules"].pop()
        source["route"]["rules"][-1]["ip_is_private"] = True
        generated = PROFILE.build_profile(source, SSID)
        self.assertEqual(generated["route"]["rules"][-1]["outbound"], "direct")
        self.assertEqual(routed(generated, domain="youtube.com", ssid="other"), "warp")

    def test_dns_without_warp_detour_still_clones_without_adding_direct_detour(self):
        source = fixture()
        del source["dns"]["servers"][-1]["detour"]
        self.assertNotIn(
            "detour", PROFILE.build_profile(source, SSID)["dns"]["servers"][-1]
        )

    def test_all_direct_preserves_existing_direct_conditions_and_order(self):
        rules = [
            {
                "domain_suffix": ["youtubei.googleapis.com"],
                "ip_version": 4,
                "outbound": "direct",
            },
            {"ip_cidr": ["224.0.0.0/4", "ff00::/8"], "outbound": "direct"},
            {"domain_regex": ["^SYNTHETIC_PRIVATE_RULE_VALUE$"], "outbound": "direct"},
        ]
        for rule in rules:
            self.assert_preserved_direct_rule(rule)

    def assert_preserved_direct_rule(self, rule):
        source = fixture()
        source["route"]["rules"].insert(5, rule)
        source["route"]["rules"].append({"action": "sniff"})
        original = PROFILE.canonical(source)
        generated = PROFILE.build_profile(source, networks=NETWORKS)
        self.assertEqual(PROFILE.canonical(source), original)
        self.assertEqual(
            PROFILE.canonical(generated["route"]["rules"][3:-1]),
            PROFILE.canonical(source["route"]["rules"]),
        )
        self.assertEqual(generated["route"]["rules"][-1]["outbound"], "direct")
        self.assertEqual(generated["route"]["final"], "warp")
        self.assertEqual(generated["endpoints"], source["endpoints"])

    def test_all_direct_still_rejects_existing_non_direct_routes(self):
        source = fixture()
        source["route"]["rules"].append(
            {"domain_suffix": ["example.com"], "outbound": "warp"}
        )
        self.assertRaises(
            PROFILE.ProfileError, PROFILE.build_profile, source, networks=NETWORKS
        )

    def assert_bad_rule(self, rule):
        source = fixture()
        source["route"]["rules"].append(rule)
        self.assertRaises(
            PROFILE.ProfileError, PROFILE.build_profile, source, SSID, "warp", "warp"
        )

    def test_warp_exceptions_reject_unsupported_public_terminal_rules(self):
        rules = [
            {"outbound": "direct"},
            {"domain_suffix": ["example.com"], "outbound": "direct"},
            {"ip_cidr": ["0.0.0.0/0"], "outbound": "direct"},
            {"ip_cidr": ["1.1.1.1/32"], "outbound": "direct"},
            {"type": "logical", "mode": "and", "rules": [], "outbound": "direct"},
            {"action": "reject"},
            {"rule_set": "private-file", "outbound": "direct"},
            {"action": "hijack-dns"},
        ]
        for rule in rules:
            self.assert_bad_rule(rule)

    def test_warp_exceptions_reject_infrastructure_after_public_rule(self):
        self.assert_bad_rule({"action": "sniff"})

    def test_dns_rules_for_other_servers_and_nonrouting_actions_are_preserved(self):
        source = fixture()
        source["dns"]["rules"].extend(
            [
                {"query_type": ["HTTPS"], "action": "reject"},
                {"domain_regex": ["[.]internal$"], "server": "bootstrap"},
                {"domain": ["example.com"], "invert": True, "server": "bootstrap"},
                {"server": "bootstrap"},
            ]
        )
        original = PROFILE.canonical(source)
        generated = PROFILE.build_profile(source, networks=NETWORKS)
        self.assertEqual(PROFILE.canonical(source), original)
        self.assertEqual(generated["dns"]["rules"][:-1], source["dns"]["rules"])
        self.assertEqual(dns_server(generated, query_type="HTTPS"), "reject")

    def test_warp_exceptions_reject_invalid_domain_fields_and_ipv4_versions(self):
        for field, value in (("domain", 3), ("domain_suffix", []), ("ip_version", 4.0)):
            source = fixture()
            source["route"]["rules"][-1][field] = value
            self.assertRaises(
                PROFILE.ProfileError,
                PROFILE.build_profile,
                source,
                SSID,
                "warp",
                "warp",
            )

    def test_dns_selection_preserves_bootstrap_and_matches_only_exact_target_wifi(self):
        generated = PROFILE.build_profile(fixture(), SSID)
        rules = generated["dns"]["rules"]
        self.assertTrue(matches(rules[0], domain="router.lan"))
        self.assertEqual(rules[0]["server"], "bootstrap")
        self.assertTrue(matches(rules[-1], domain="example.com"))
        self.assertFalse(matches(rules[-1], ssid=SSID.lower()))
        self.assertFalse(matches(rules[-1], network_type="ethernet"))
        self.assertEqual(rules[-1]["server"], PROFILE.DNS_TAG)

    def test_reserved_tag_and_port_collisions(self):
        for item in (
            {"type": "socks", "tag": PROFILE.PROBE_TAG},
            {"type": "socks", "tag": "other", "listen_port": PROFILE.PROBE_PORT},
            {"type": "socks", "tag": PROFILE.DNS_TAG},
        ):
            source = fixture()
            source["inbounds"].append(item)
            self.assertRaises(PROFILE.ProfileError, PROFILE.build_profile, source, SSID)

    def test_invalid_options_and_source_policy(self):
        for ssid in ("", "x" * 33, "wifi\nsecret"):
            self.assertRaises(
                PROFILE.ProfileError, PROFILE.build_profile, fixture(), ssid
            )
        self.assertRaises(
            PROFILE.ProfileError, PROFILE.build_profile, fixture(), SSID, "unknown"
        )
        source = fixture()
        source["dns"]["servers"][-1]["detour"] = "direct"
        self.assertRaises(PROFILE.ProfileError, PROFILE.build_profile, source, SSID)


class DNSRules(unittest.TestCase):
    def test_final_server_rule_uses_direct_clone_only_on_target_network(self):
        source = fixture()
        original = {
            "query_type": ["A", "AAAA"],
            "server": "adguard",
            "strategy": "as_is",
            "disable_cache": True,
            "rewrite_ttl": 60,
        }
        source["dns"]["rules"].append(original)
        before = PROFILE.canonical(source)
        profile = PROFILE.build_profile(source, networks=NETWORKS)
        override = profile["dns"]["rules"][1]
        self.assertEqual(PROFILE.canonical(source), before)
        self.assertEqual(profile["dns"]["rules"][2], original)
        self.assertEqual(override["server"], PROFILE.DNS_TAG)
        for field in ("strategy", "disable_cache", "rewrite_ttl"):
            self.assertEqual(override[field], original[field])
        self.assertTrue(
            {"action", "server", "strategy", "disable_cache", "rewrite_ttl"}.isdisjoint(
                override["rules"][1]
            )
        )
        self.assertEqual(dns_server(profile, domain="router.lan"), "bootstrap")
        self.assertEqual(dns_server(profile, domain="example.com"), PROFILE.DNS_TAG)
        self.assertEqual(
            dns_server(profile, domain="example.com", network_type="ethernet"),
            "adguard",
        )

    def test_inverted_and_logical_conditions_keep_original_meaning(self):
        conditions = [
            {"domain": ["excluded.example"], "invert": True},
            {
                "type": "logical",
                "mode": "or",
                "rules": [{"domain": ["normal.example"]}, {"query_type": ["AAAA"]}],
            },
        ]
        for condition in conditions:
            self.assert_dns_condition_scoped(condition)

    def assert_dns_condition_scoped(self, condition):
        source = fixture()
        source["dns"]["rules"] = [
            {**condition, "server": "adguard"},
            {"server": "bootstrap"},
        ]
        profile = PROFILE.build_profile(source, networks=NETWORKS)
        self.assertEqual(dns_server(profile, domain="normal.example"), PROFILE.DNS_TAG)
        self.assertEqual(dns_server(profile, domain="excluded.example"), "bootstrap")
        self.assertEqual(
            dns_server(profile, domain="normal.example", network_type="ethernet"),
            "adguard",
        )
        self.assertEqual(
            dns_server(profile, domain="excluded.example", network_type="ethernet"),
            "bootstrap",
        )
        preserved = [
            rule
            for rule in profile["dns"]["rules"]
            if rule.get("server") != PROFILE.DNS_TAG
        ]
        self.assertEqual(preserved, source["dns"]["rules"])

    def test_unconditional_final_server_rule_cannot_shadow_gl_dns(self):
        source = fixture()
        source["dns"]["rules"] = [{"server": "adguard"}]
        profile = PROFILE.build_profile(source, networks=NETWORKS)
        self.assertEqual(dns_server(profile), PROFILE.DNS_TAG)
        self.assertEqual(dns_server(profile, network_type="ethernet"), "adguard")
        self.assertEqual(profile["dns"]["rules"][1], source["dns"]["rules"][0])

    def test_existing_network_conditions_are_combined_instead_of_replaced(self):
        source = fixture()
        source["dns"]["rules"] = [
            {"network_type": ["ethernet"], "server": "adguard"},
            {"server": "bootstrap"},
        ]
        profile = PROFILE.build_profile(source, networks=NETWORKS)
        self.assertEqual(dns_server(profile), "bootstrap")
        self.assertEqual(dns_server(profile, network_type="ethernet"), "adguard")
        source["dns"]["rules"] = [
            {"query_type": [], "invert": True, "server": "adguard"},
            {"server": "bootstrap"},
        ]
        profile = PROFILE.build_profile(source, networks=NETWORKS)
        self.assertEqual(profile["dns"]["rules"][:-1], source["dns"]["rules"])
        self.assertEqual(dns_server(profile), "bootstrap")

    def test_non_string_dns_server_references_fail_closed(self):
        source = fixture()
        source["dns"]["rules"].append({"query_type": ["A"], "server": 1})
        self.assertRaises(
            PROFILE.ProfileError, PROFILE.build_profile, source, networks=NETWORKS
        )

    def test_advanced_final_server_actions_fail_before_source_mutation(self):
        rules = [
            {"query_type": ["A"], "server": "adguard", "race": True},
            {"query_type": ["A"], "server": "adguard", "speculative": True},
            {
                "query_type": ["A"],
                "server": "adguard",
                "action": "evaluate",
                "tag": "synthetic-response",
            },
        ]
        for rule in rules:
            self.assert_advanced_action_rejected(rule)

    def assert_advanced_action_rejected(self, rule):
        source = fixture()
        source["dns"]["rules"].append(rule)
        before = PROFILE.canonical(source)
        self.assertRaises(
            PROFILE.ProfileError, PROFILE.build_profile, source, networks=NETWORKS
        )
        self.assertEqual(PROFILE.canonical(source), before)


class NetworkMode(unittest.TestCase):
    def test_exact_shared_dual_prefix_predicate_without_ssid_fields(self):
        profile = PROFILE.build_profile(
            fixture(), youtube="warp", github="warp", networks=NETWORKS
        )
        rules = profile["route"]["rules"]
        expected = {"network_type": ["wifi"], "default_interface_address": NETWORKS}
        for rule in [rules[0], *rules[8:11], profile["dns"]["rules"][-1]]:
            self.assertEqual({field: rule[field] for field in expected}, expected)
        self.assertNotIn(b'"wifi_ssid"', PROFILE.canonical(profile))
        self.assertNotIn(b'"wifi_bssid"', PROFILE.canonical(profile))

    def test_both_prefixes_and_wifi_are_required_for_route_dns_and_probe(self):
        cases = [
            (INTERFACE_ADDRESSES, "wifi", True),
            (("192.168.8.246/32", "fd40:ffeb:eb06::1234/128"), "wifi", True),
            (("192.168.9.1/24", INTERFACE_ADDRESSES[1]), "wifi", False),
            ((INTERFACE_ADDRESSES[0], "fd40:ffeb:eb07::1/64"), "wifi", False),
            ((INTERFACE_ADDRESSES[0],), "wifi", False),
            ((INTERFACE_ADDRESSES[1],), "wifi", False),
            ((), "wifi", False),
            (INTERFACE_ADDRESSES, "ethernet", False),
        ]
        for addresses, network_type, expected in cases:
            self.assert_network_match(addresses, network_type, expected)

    def assert_network_match(self, addresses, network_type, expected):
        profile = PROFILE.build_profile(fixture(), networks=NETWORKS)
        traffic = {
            "interface_addresses": addresses,
            "network_type": network_type,
            "ssid": "irrelevant",
        }
        self.assertEqual(matches(profile["dns"]["rules"][-1], **traffic), expected)
        self.assertEqual(
            routed(profile, domain="example.com", **traffic),
            "direct" if expected else "warp",
        )
        self.assertEqual(
            matches(
                profile["route"]["rules"][0],
                address="1.1.1.1",
                inbound=PROFILE.PROBE_TAG,
                **traffic,
            ),
            expected,
        )
        self.assertEqual(
            routed(profile, address="1.1.1.1", inbound=PROFILE.PROBE_TAG, **traffic),
            "direct" if expected else "warp",
        )

    def test_network_mode_preserves_source_and_original_rule_order(self):
        source = fixture()
        original = PROFILE.canonical(source)
        networks = list(NETWORKS)
        profile = PROFILE.build_profile(source, networks=networks)
        self.assertEqual(PROFILE.canonical(source), original)
        self.assertEqual(
            PROFILE.canonical(profile["route"]["rules"][3:-1]),
            PROFILE.canonical(source["route"]["rules"]),
        )
        restored = copy.deepcopy(profile)
        restored["inbounds"].pop()
        restored["dns"]["servers"].pop()
        restored["dns"]["rules"].pop()
        restored["route"]["rules"] = source["route"]["rules"]
        self.assertEqual(PROFILE.canonical(restored), original)
        networks[0] = "10.0.0.0/24"
        self.assertEqual(
            profile["dns"]["rules"][-1]["default_interface_address"], NETWORKS
        )

    def test_network_validation_rejects_noncanonical_or_unsafe_prefixes(self):
        invalid = [
            [],
            NETWORKS[:1],
            [*NETWORKS, "extra"],
            "not-a-list",
            [True, NETWORKS[1]],
            list(reversed(NETWORKS)),
            [NETWORKS[0], NETWORKS[0]],
            ["8.8.8.0/24", NETWORKS[1]],
            ["100.64.0.0/24", NETWORKS[1]],
            ["169.254.0.0/24", NETWORKS[1]],
            ["127.0.0.0/24", NETWORKS[1]],
            ["0.0.0.0/0", NETWORKS[1]],
            ["192.168.8.0/23", NETWORKS[1]],
            ["192.168.8.1/24", NETWORKS[1]],
            ["192.168.8.0/255.255.255.0", NETWORKS[1]],
            ["192.168.8.1", NETWORKS[1]],
            ["192.168.8.0/024", NETWORKS[1]],
            [NETWORKS[0], "2001:db8::/64"],
            [NETWORKS[0], "fe80::/64"],
            [NETWORKS[0], "::/0"],
            [NETWORKS[0], "fd40:ffeb:eb06::/63"],
            [NETWORKS[0], "fd40:ffeb:eb06::/65"],
            [NETWORKS[0], "fd40:ffeb:eb06::1/64"],
            [NETWORKS[0], "FD40:FFEB:EB06::/64"],
            [NETWORKS[0], "fd40:ffeb:eb06:0:0:0:0:0/64"],
        ]
        for networks in invalid:
            self.assert_invalid_networks(networks)

    def assert_invalid_networks(self, networks):
        with self.assertRaises(PROFILE.ProfileError) as error:
            PROFILE.build_profile(fixture(), networks=networks)
        self.assertEqual(str(error.exception), "invalid_networks")

    def test_canonical_rfc1918_and_ula_boundaries_are_supported(self):
        for networks in (
            ["10.0.0.0/24", "fc00::/64"],
            ["172.31.255.240/28", "fdff:ffff:ffff:ffff::/64"],
            NETWORKS,
        ):
            profile = PROFILE.build_profile(fixture(), networks=networks)
            self.assertEqual(
                profile["dns"]["rules"][-1]["default_interface_address"], networks
            )
        self.assertRaises(
            PROFILE.ProfileError,
            PROFILE.build_profile,
            fixture(),
            SSID,
            networks=NETWORKS,
        )
        self.assertRaises(PROFILE.ProfileError, PROFILE.build_profile, fixture())


class Files(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(
            prefix="sfm-gl-test-", dir=os.environ.get("TMPDIR")
        )
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "synthetic-input.json"
        self.original = PROFILE.canonical(fixture())
        self.source.write_bytes(self.original)
        self.output = self.root / "new-profile.json"
        self.binary = self.root / "unused-binary"
        self.enterContext(mock.patch.object(PROFILE, "require_isolation"))
        self.check = self.enterContext(mock.patch.object(PROFILE, "check_config"))
        self.confirm = self.enterContext(
            mock.patch("builtins.input", return_value="CREATE")
        )
        self.enterContext(mock.patch.dict(os.environ, {"TMPDIR": str(self.root)}))

    def create(self):
        return PROFILE.create_profile(
            self.source, self.output, self.binary, SSID, "direct", "direct"
        )

    def test_new_output_is_private_checked_and_source_unchanged(self):
        report = self.create()
        self.assertEqual(
            report,
            {
                "created": True,
                "checked": True,
                "source_unchanged": True,
                "output": str(self.output),
            },
        )
        self.assertEqual(self.source.read_bytes(), self.original)
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o600)
        self.check.assert_called_once()
        self.assertFalse(self.check.call_args.args[1].exists())
        self.assertEqual(set(self.root.iterdir()), {self.source, self.output})
        self.assertNotIn("SYNTHETIC_PRIVATE_SENTINEL", json.dumps(report))

    def test_network_mode_creation_passes_selector_without_changing_publication(self):
        report = PROFILE.create_profile(
            self.source,
            self.output,
            self.binary,
            None,
            "direct",
            "direct",
            networks=NETWORKS,
        )
        self.assertTrue(report["created"])
        self.assertTrue(report["source_unchanged"])
        self.assertEqual(self.source.read_bytes(), self.original)
        profile = json.loads(self.output.read_bytes())
        self.assertEqual(
            profile["dns"]["rules"][-1]["default_interface_address"], NETWORKS
        )
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o600)

    def test_isolation_failure_precedes_any_input_profile_read(self):
        PROFILE.require_isolation.side_effect = PROFILE.ProfileError(
            "sfm_must_be_stopped"
        )
        with mock.patch.object(PROFILE, "read_input") as read:
            self.assertRaises(PROFILE.ProfileError, self.create)
        read.assert_not_called()
        self.check.assert_not_called()

    def test_check_failure_removes_temporary_artifacts_and_never_creates_output(self):
        self.check.side_effect = PROFILE.ProfileError("configuration_check_failed")
        self.assertRaises(PROFILE.ProfileError, self.create)
        self.assertEqual(list(self.root.iterdir()), [self.source])
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_declined_create_does_not_write_or_check(self):
        self.confirm.return_value = "NO"
        self.assertRaises(PROFILE.ProfileError, self.create)
        self.check.assert_not_called()
        self.assertEqual(list(self.root.iterdir()), [self.source])

    def test_existing_output_and_source_output_collision_never_overwrite(self):
        self.output.write_bytes(b"existing")
        self.assertRaises(PROFILE.ProfileError, self.create)
        self.assertEqual(self.output.read_bytes(), b"existing")
        self.assertRaises(
            PROFILE.ProfileError, PROFILE.require_new_output, self.source, self.source
        )
        self.check.assert_not_called()

    def test_symlink_input_output_and_fifo_are_rejected(self):
        linked = self.root / "link"
        linked.symlink_to(self.source)
        self.assertRaises(OSError, PROFILE.read_input, linked)
        self.output.symlink_to(self.root / "missing")
        self.assertRaises(PROFILE.ProfileError, self.create)
        fifo = self.root / "fifo"
        os.mkfifo(fifo)
        self.assertRaises(PROFILE.ProfileError, PROFILE.read_input, fifo)

    def test_publish_uses_exclusive_create_and_cleans_own_failed_file(self):
        with mock.patch.object(PROFILE.os, "fsync", side_effect=OSError("synthetic")):
            self.assertRaises(
                OSError,
                PROFILE.publish,
                self.output,
                b"new",
                self.source,
                self.original,
            )
        self.assertFalse(self.output.exists())
        self.output.write_bytes(b"existing")
        self.assertRaises(
            FileExistsError,
            PROFILE.publish,
            self.output,
            b"new",
            self.source,
            self.original,
        )
        self.assertEqual(self.output.read_bytes(), b"existing")

    def test_source_change_during_check_prevents_publication(self):
        self.check.side_effect = lambda *_: self.source.write_bytes(b"external change")
        self.assertRaises(PROFILE.ProfileError, self.create)
        self.assertFalse(self.output.exists())
        self.assertEqual(self.source.read_bytes(), b"external change")
        self.assertEqual(list(self.root.iterdir()), [self.source])

    def test_source_change_during_publish_removes_only_new_output(self):
        self.assertRaises(
            PROFILE.ProfileError,
            PROFILE.publish,
            self.output,
            b"new",
            self.source,
            b"different",
        )
        self.assertFalse(self.output.exists())
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_bounded_json_duplicate_keys_and_nonfinite_values(self):
        cases = [
            b'{"x":1,"x":2}',
            b'{"x":{"y":1,"y":2}}',
            b'{"x":NaN}',
            b"[]",
            b"\xff",
            b"x" * (PROFILE.PROFILE_LIMIT + 1),
        ]
        for raw in cases:
            self.assertRaises(PROFILE.ProfileError, PROFILE.decode_profile, raw)
        self.source.write_bytes(b"x" * (PROFILE.PROFILE_LIMIT + 1))
        self.assertRaises(PROFILE.ProfileError, PROFILE.read_input, self.source)


class Safety(unittest.TestCase):
    def test_cli_gate_precedes_profile_reads_and_other_operations(self):
        arguments = [
            "--profile",
            "/synthetic/input",
            "--output",
            "/synthetic/output",
            "--binary",
            "/synthetic/binary",
            "--ssid",
            SSID,
        ]
        for user_run, terminal in ((False, True), (True, False), (False, False)):
            self.assert_cli_gate(arguments, user_run, terminal)

    def assert_cli_gate(self, arguments, user_run, terminal):
        output = io.StringIO()
        with (
            mock.patch.object(PROFILE.sys.stdin, "isatty", return_value=terminal),
            mock.patch.object(output, "isatty", return_value=terminal),
            mock.patch.object(PROFILE, "create_profile") as create,
            mock.patch.object(PROFILE.os, "open") as opened,
            redirect_stdout(output),
        ):
            code = PROFILE.main(arguments + (["--user-run"] if user_run else []))
        self.assertEqual(code, 1)
        self.assertEqual(
            json.loads(output.getvalue()),
            {"created": False, "error": "interactive_user_run_required"},
        )
        create.assert_not_called()
        opened.assert_not_called()

    def test_network_cli_guard_precedes_profile_reads(self):
        arguments = [
            "--profile",
            "/synthetic/input",
            "--output",
            "/synthetic/output",
            "--binary",
            "/synthetic/binary",
            "--networks",
            *NETWORKS,
        ]
        for user_run, terminal in ((False, True), (True, False), (False, False)):
            self.assert_cli_gate(arguments, user_run, terminal)

    def test_cli_requires_exactly_one_complete_selector(self):
        for selector in (
            [],
            ["--networks", NETWORKS[0]],
            ["--ssid", SSID, "--networks", *NETWORKS],
            ["--networks", *NETWORKS, "extra"],
        ):
            self.assert_selector_error(selector)

    def assert_selector_error(self, selector):
        arguments = [
            "--profile",
            "/synthetic/input",
            "--output",
            "/synthetic/output",
            "--binary",
            "/synthetic/binary",
            *selector,
        ]
        with (
            mock.patch.object(PROFILE, "create_profile") as create,
            mock.patch.object(PROFILE.os, "open") as opened,
            redirect_stderr(io.StringIO()),
            self.assertRaises(SystemExit) as error,
        ):
            PROFILE.main(arguments)
        self.assertEqual(error.exception.code, 2)
        create.assert_not_called()
        opened.assert_not_called()

    def test_network_cli_propagation_and_invalid_prefixes_fail_before_profile_read(
        self,
    ):
        self.assert_network_cli(NETWORKS, 0)
        self.assert_network_cli(["8.8.8.0/24", NETWORKS[1]], 1)

    def assert_network_cli(self, networks, expected_code):
        output = io.StringIO()
        arguments = [
            "--user-run",
            "--profile",
            "/synthetic/input",
            "--output",
            "/synthetic/output",
            "--binary",
            "/synthetic/binary",
            "--networks",
            *networks,
        ]
        with (
            mock.patch.object(PROFILE.sys.stdin, "isatty", return_value=True),
            mock.patch.object(output, "isatty", return_value=True),
            mock.patch.object(
                PROFILE, "create_profile", return_value={"created": True}
            ) as create,
            mock.patch.object(PROFILE.os, "open") as opened,
            redirect_stdout(output),
        ):
            self.assertEqual(PROFILE.main(arguments), expected_code)
        opened.assert_not_called()
        if expected_code == 0:
            self.assertEqual(create.call_args.args[-3:], (None, "direct", "direct"))
            self.assertEqual(create.call_args.kwargs, {"networks": NETWORKS})
        else:
            create.assert_not_called()
            self.assertEqual(json.loads(output.getvalue())["error"], "invalid_networks")
            self.assertNotIn(networks[0], output.getvalue())

    def test_cli_errors_do_not_disclose_exception_values(self):
        output = io.StringIO()
        arguments = [
            "--user-run",
            "--profile",
            "/synthetic/input",
            "--output",
            "/synthetic/output",
            "--binary",
            "/synthetic/binary",
            "--ssid",
            SSID,
        ]
        with (
            mock.patch.object(PROFILE.sys.stdin, "isatty", return_value=True),
            mock.patch.object(output, "isatty", return_value=True),
            mock.patch.object(
                PROFILE,
                "create_profile",
                side_effect=OSError("SYNTHETIC_PRIVATE_SENTINEL"),
            ),
            redirect_stdout(output),
        ):
            self.assertEqual(PROFILE.main(arguments), 1)
        self.assertNotIn("SYNTHETIC_PRIVATE_SENTINEL", output.getvalue())

    def test_isolation_uses_only_noncredential_status_and_regular_pause_marker(self):
        raw = self.enterContext(
            tempfile.TemporaryDirectory(
                prefix="sfm-gl-status-", dir=os.environ.get("TMPDIR")
            )
        )
        root = Path(raw)
        directory = root / "sfm-warp-maintenance"
        directory.mkdir()
        paused = directory / "paused"
        paused.touch()
        self.enterContext(mock.patch.dict(os.environ, {"XDG_STATE_HOME": raw}))
        self.enterContext(mock.patch.object(PROFILE.sys, "platform", "darwin"))
        run = self.enterContext(mock.patch.object(PROFILE.subprocess, "run"))
        run.return_value = subprocess.CompletedProcess([], 0, b"Connected\n")
        self.assertRaises(PROFILE.ProfileError, PROFILE.require_isolation)
        run.return_value = subprocess.CompletedProcess([], 0, b"Disconnected\n")
        PROFILE.require_isolation()
        self.assertEqual(
            run.call_args.args[0], ["/usr/sbin/scutil", "--nc", "status", "SFM"]
        )
        self.assertEqual(run.call_args.kwargs["env"], PROFILE.CLEAN_ENV)
        paused.unlink()
        self.assertRaises(FileNotFoundError, PROFILE.require_isolation)
        paused.symlink_to(root / "absent")
        self.assertRaises(PROFILE.ProfileError, PROFILE.require_isolation)
        self.assertEqual(run.call_count, 2)

    def test_cli_propagates_explicit_choices_without_reading_any_profile(self):
        output = io.StringIO()
        arguments = [
            "--user-run",
            "--profile",
            "/synthetic/input",
            "--output",
            "/synthetic/output",
            "--binary",
            "/synthetic/binary",
            "--ssid",
            SSID,
            "--youtube",
            "warp",
            "--github",
            "direct",
        ]
        with (
            mock.patch.object(PROFILE.sys.stdin, "isatty", return_value=True),
            mock.patch.object(output, "isatty", return_value=True),
            mock.patch.object(
                PROFILE, "create_profile", return_value={"created": True}
            ) as create,
            redirect_stdout(output),
        ):
            self.assertEqual(PROFILE.main(arguments), 0)
        self.assertEqual(create.call_args.args[-3:], (SSID, "warp", "direct"))

    def test_check_commands_are_version_pinned_silent_and_never_run(self):
        results = [
            subprocess.CompletedProcess([], 0, b"sing-box version 1.14.2\n"),
            subprocess.CompletedProcess([], 0),
        ]
        with mock.patch.object(PROFILE.subprocess, "run", side_effect=results) as run:
            PROFILE.check_config(Path("/synthetic/binary"), Path("/synthetic/profile"))
        self.assertEqual(
            [call.args[0] for call in run.call_args_list],
            [
                ["/synthetic/binary", "version"],
                ["/synthetic/binary", "check", "-c", "/synthetic/profile"],
            ],
        )
        self.assertEqual(run.call_args.kwargs["stdout"], subprocess.DEVNULL)
        self.assertEqual(run.call_args.kwargs["stderr"], subprocess.PIPE)
        self.assertEqual(run.call_args.kwargs["env"], PROFILE.CLEAN_ENV)

    def test_checker_errors_expose_only_fixed_codes(self):
        self.assert_sanitized_checker_error(
            b"SYNTHETIC_PRIVATE_VALUE", "configuration_check_failed"
        )
        self.assert_sanitized_checker_error(
            b"Legacy `strategy` DNS rule action option is deprecated SYNTHETIC_PRIVATE_VALUE",
            "legacy_dns_rule_strategy_requires_migration",
        )

    def assert_sanitized_checker_error(self, details, expected):
        results = [
            subprocess.CompletedProcess([], 0, b"sing-box version 1.14.2\n"),
            subprocess.CompletedProcess([], 1, b"", details),
        ]
        with (
            mock.patch.object(PROFILE.subprocess, "run", side_effect=results),
            self.assertRaises(PROFILE.ProfileError) as error,
        ):
            PROFILE.check_config(Path("/synthetic/binary"), Path("/synthetic/profile"))
        self.assertEqual(str(error.exception), expected)
        self.assertNotIn("SYNTHETIC_PRIVATE_VALUE", str(error.exception))

    def test_wrong_binary_version_prevents_configuration_check(self):
        with mock.patch.object(
            PROFILE.subprocess,
            "run",
            return_value=subprocess.CompletedProcess(
                [], 0, b"sing-box version 1.14.1\n"
            ),
        ) as run:
            self.assertRaises(
                PROFILE.ProfileError,
                PROFILE.check_config,
                Path("/synthetic/binary"),
                Path("/synthetic/profile"),
            )
        self.assertEqual(run.call_count, 1)

    def test_statement_indentation_is_at_most_three_levels(self):
        for path in (SOURCE, Path(__file__)):
            statements = [
                node
                for node in ast.walk(ast.parse(path.read_text()))
                if isinstance(node, ast.stmt)
            ]
            self.assertLessEqual(max(node.col_offset for node in statements), 12)


@unittest.skipUnless(
    BINARY, "set SFM_PROFILE_TEST_BINARY to a verified official 1.14.2 binary"
)
class Binary(unittest.TestCase):
    def test_actual_check_accepts_only_synthetic_loopback_endpoint_profiles(self):
        for youtube, github in (
            ("direct", "direct"),
            ("warp", "warp"),
            ("direct", "warp"),
            ("warp", "direct"),
        ):
            self.check_synthetic(youtube, github)

    def test_actual_check_accepts_network_mode_for_all_routing_choices(self):
        for youtube, github in (
            ("direct", "direct"),
            ("warp", "warp"),
            ("direct", "warp"),
            ("warp", "direct"),
        ):
            self.check_synthetic(youtube, github, networks=NETWORKS)

    def test_actual_check_accepts_preserved_direct_rule_variants(self):
        source = fixture()
        source["route"]["rules"].extend(
            [
                {
                    "domain_suffix": ["youtubei.googleapis.com"],
                    "ip_version": 4,
                    "outbound": "direct",
                },
                {"ip_cidr": ["224.0.0.0/4", "ff00::/8"], "outbound": "direct"},
                {"domain_regex": ["^synthetic[.]example$"], "outbound": "direct"},
            ]
        )
        profile = PROFILE.build_profile(source, networks=NETWORKS)
        with tempfile.TemporaryDirectory(
            prefix="sfm-gl-direct-", dir=os.environ.get("TMPDIR")
        ) as raw:
            path = Path(raw) / "synthetic.json"
            path.write_bytes(PROFILE.canonical(profile))
            PROFILE.check_config(Path(BINARY), path)

    def test_actual_check_failure_never_publishes_output_or_changes_source(self):
        invalid = fixture()
        invalid["synthetic_unknown_field"] = True
        self.assert_checker_rejects_without_publication(invalid)

    def test_actual_check_accepts_preserved_dns_conditions_and_actions(self):
        source = fixture()
        source["dns"]["rules"].extend(
            [
                {"query_type": ["HTTPS"], "action": "reject"},
                {
                    "query_type": ["A"],
                    "server": "adguard",
                    "strategy": "as_is",
                    "timeout": "3s",
                    "rewrite_ttl": 60,
                },
                {
                    "type": "logical",
                    "mode": "or",
                    "rules": [
                        {"domain_suffix": ["example.invalid"]},
                        {"query_type": ["AAAA"]},
                    ],
                    "server": "adguard",
                    "disable_optimistic_cache": True,
                },
                {
                    "domain_regex": ["[.]example$"],
                    "invert": True,
                    "server": "adguard",
                    "client_subnet": "192.0.2.0/24",
                },
                {"query_type": [], "server": "adguard"},
                {"server": "adguard"},
            ]
        )
        profile = PROFILE.build_profile(source, networks=NETWORKS)
        with tempfile.TemporaryDirectory(
            prefix="sfm-gl-dns-", dir=os.environ.get("TMPDIR")
        ) as raw:
            path = Path(raw) / "synthetic.json"
            path.write_bytes(PROFILE.canonical(profile))
            PROFILE.check_config(Path(BINARY), path)

    def test_actual_check_rejects_invalid_preserved_dns_conditions(self):
        invalid = fixture()
        invalid["dns"]["rules"].append({"domain_regex": ["["], "server": "adguard"})
        self.assert_checker_rejects_without_publication(invalid)

    def test_actual_check_rejects_invalid_preserved_direct_conditions(self):
        for field, value in (
            ("domain_regex", ["["]),
            ("synthetic_unknown_condition", True),
        ):
            invalid = fixture()
            invalid["route"]["rules"][-1][field] = value
            self.assert_checker_rejects_without_publication(invalid)

    def test_legacy_dns_strategy_is_reported_without_publication(self):
        source = fixture()
        source["dns"]["rules"].append(
            {"query_type": ["A"], "server": "adguard", "strategy": "ipv4_only"}
        )
        self.assert_checker_rejects_without_publication(
            source, "legacy_dns_rule_strategy_requires_migration"
        )

    def assert_checker_rejects_without_publication(
        self, invalid, expected="configuration_check_failed"
    ):
        raw = self.enterContext(
            tempfile.TemporaryDirectory(
                prefix="sfm-gl-invalid-", dir=os.environ.get("TMPDIR")
            )
        )
        root = Path(raw)
        source, output = root / "synthetic.json", root / "output.json"
        original = PROFILE.canonical(invalid)
        source.write_bytes(original)
        self.enterContext(mock.patch.dict(os.environ, {"TMPDIR": raw}))
        self.enterContext(mock.patch.object(PROFILE, "require_isolation"))
        self.enterContext(mock.patch("builtins.input", return_value="CREATE"))
        with self.assertRaises(PROFILE.ProfileError) as error:
            PROFILE.create_profile(
                source, output, Path(BINARY), SSID, "direct", "direct"
            )
        self.assertEqual(str(error.exception), expected)
        self.assertEqual(source.read_bytes(), original)
        self.assertEqual(list(root.iterdir()), [source])

    def check_synthetic(self, youtube, github, *, networks=None):
        profile = PROFILE.build_profile(
            fixture(),
            SSID if networks is None else None,
            youtube,
            github,
            networks=networks,
        )
        self.assertEqual(profile["endpoints"][0]["peers"][0]["address"], "127.0.0.1")
        with tempfile.TemporaryDirectory(
            prefix="sfm-gl-binary-", dir=os.environ.get("TMPDIR")
        ) as raw:
            path = Path(raw) / "synthetic.json"
            path.write_bytes(PROFILE.canonical(profile))
            path.chmod(0o600)
            PROFILE.check_config(Path(BINARY), path)


if __name__ == "__main__":
    unittest.main()
