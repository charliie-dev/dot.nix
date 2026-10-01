"""Create a separate GL-XE3000 SFM profile in the user's interactive terminal."""

from __future__ import annotations

import argparse
import copy
import ipaddress
import json
import os
import signal
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

VERSION = "1.14.2"
PROFILE_LIMIT = 2 * 1024 * 1024
PROBE_TAG = "maintenance-probe"
PROBE_PORT = 18082
DNS_TAG = "gl-xe3000-direct-dns"
DNS_ROUTE_ACTION_FIELDS = {
    "action",
    "server",
    "race",
    "speculative",
    "timeout",
    "strategy",
    "disable_cache",
    "disable_optimistic_cache",
    "rewrite_ttl",
    "client_subnet",
    "remove_client_subnet",
}
YOUTUBE_SUFFIXES = (
    "youtube.com",
    "youtu.be",
    "youtube-nocookie.com",
    "googlevideo.com",
    "ytimg.com",
)
YOUTUBE_DOMAINS = ("youtubei.googleapis.com", "youtube.googleapis.com")
GITHUB_SUFFIXES = ("github.com", "githubusercontent.com", "githubassets.com")
PRIVATE_NETWORKS = tuple(
    ipaddress.ip_network(value)
    for value in (
        "10.0.0.0/8",
        "172.16.0.0/12",
        "192.168.0.0/16",
        "127.0.0.0/8",
        "169.254.0.0/16",
        "100.64.0.0/10",
        "::1/128",
        "fc00::/7",
        "fe80::/10",
    )
)
CLEAN_ENV = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"}


class ProfileError(ValueError):
    """A fixed error code without profile values."""


def canonical(value: object) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), allow_nan=False
    ).encode()


def unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ProfileError("duplicate_json_key")
        result[key] = value
    return result


def decode_profile(data: bytes) -> dict:
    if len(data) > PROFILE_LIMIT:
        raise ProfileError("profile_too_large")
    try:
        value = json.loads(data, object_pairs_hook=unique_object)
        canonical(value)
    except (ValueError, UnicodeError, RecursionError):
        raise ProfileError("invalid_profile_json") from None
    if not isinstance(value, dict):
        raise ProfileError("profile_root_invalid")
    return value


def objects(value: object, field: str) -> list[dict]:
    if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
        raise ProfileError(field)
    return value


def strings(value: object) -> list[str]:
    values = [value] if isinstance(value, str) else value
    if not isinstance(values, list) or not values:
        return []
    return values if all(isinstance(item, str) and item for item in values) else []


def wifi_condition(ssid: str | None, *, networks: list[str] | None = None) -> dict:
    if networks is not None:
        return {"network_type": ["wifi"], "default_interface_address": list(networks)}
    return {"wifi_ssid": [ssid], "network_type": ["wifi"]}


def validate_networks(networks: list[str]) -> None:
    if not isinstance(networks, list) or len(networks) != 2:
        raise ProfileError("invalid_networks")
    if not all(isinstance(value, str) for value in networks):
        raise ProfileError("invalid_networks")
    try:
        ipv4 = ipaddress.IPv4Network(networks[0], strict=True)
        ipv6 = ipaddress.IPv6Network(networks[1], strict=True)
    except ValueError:
        raise ProfileError("invalid_networks") from None
    private_v4 = any(
        ipv4.subnet_of(ipaddress.IPv4Network(cidr))
        for cidr in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
    )
    if (
        [str(ipv4), str(ipv6)] != networks
        or not private_v4
        or ipv4.prefixlen < 24
        or ipv6.prefixlen != 64
        or not ipv6.subnet_of(ipaddress.IPv6Network("fc00::/7"))
    ):
        raise ProfileError("invalid_networks")


def validate_options(
    ssid: str | None, youtube: str, github: str, *, networks: list[str] | None = None
) -> None:
    if networks is not None:
        if ssid is not None:
            raise ProfileError("conflicting_network_selectors")
        validate_networks(networks)
    else:
        if not isinstance(ssid, str) or not 1 <= len(ssid.encode()) <= 32:
            raise ProfileError("invalid_ssid")
        if any(ord(char) < 32 or ord(char) == 127 for char in ssid):
            raise ProfileError("invalid_ssid")
    if youtube not in {"direct", "warp"} or github not in {"direct", "warp"}:
        raise ProfileError("invalid_routing_choice")


def validate_tags(profile: dict) -> None:
    tagged = []
    for field in ("inbounds", "outbounds", "endpoints"):
        tagged.extend(objects(profile.get(field, []), field))
    dns = profile.get("dns")
    if not isinstance(dns, dict):
        raise ProfileError("dns")
    tagged.extend(objects(dns.get("servers"), "dns.servers"))
    tags = [item["tag"] for item in tagged if "tag" in item]
    if not all(isinstance(tag, str) and tag for tag in tags):
        raise ProfileError("invalid_tag")
    if len(set(tags)) != len(tags) or {PROBE_TAG, DNS_TAG}.intersection(tags):
        raise ProfileError("tag_collision")
    if any(item.get("listen_port") == PROBE_PORT for item in tagged):
        raise ProfileError("probe_port_collision")


def validate_source(profile: dict) -> None:
    if not isinstance(profile, dict):
        raise ProfileError("profile_root_invalid")
    validate_tags(profile)
    route = profile.get("route")
    if not isinstance(route, dict):
        raise ProfileError("route")
    if route.get("final") != "warp" or route.get("auto_detect_interface") is not True:
        raise ProfileError("route.default_policy")
    endpoints = objects(profile.get("endpoints"), "endpoints")
    if not any(
        item.get("tag") == "warp" and item.get("type") == "wireguard"
        for item in endpoints
    ):
        raise ProfileError("endpoints.warp")
    outbounds = objects(profile.get("outbounds"), "outbounds")
    if not any(
        item.get("tag") == "direct" and item.get("type") == "direct"
        for item in outbounds
    ):
        raise ProfileError("outbounds.direct")
    if not any(
        item.get("type") == "tun"
        for item in objects(profile.get("inbounds"), "inbounds")
    ):
        raise ProfileError("inbounds.tun")


def private_cidrs(value: object) -> bool:
    values = strings(value)
    if not values:
        return False
    try:
        networks = [ipaddress.ip_network(item, strict=False) for item in values]
    except ValueError:
        return False
    return all(
        any(
            net.version == private.version
            and int(net.network_address) >= int(private.network_address)
            and int(net.broadcast_address) <= int(private.broadcast_address)
            for private in PRIVATE_NETWORKS
        )
        for net in networks
    )


def source_rule_kind(rule: dict, *, preserve_direct: bool = False) -> str:
    if rule.get("type", "default") != "default":
        raise ProfileError("route.rules.type")
    action = rule.get("action", "route")
    if not isinstance(action, str):
        raise ProfileError("route.rules.action")
    if action in {"sniff", "resolve"}:
        return "infrastructure"
    if action == "hijack-dns" and strings(rule.get("protocol")) == ["dns"]:
        return "infrastructure"
    if action != "route" or rule.get("outbound") != "direct":
        raise ProfileError("route.rules.terminal")
    # The official checker validates preserved conditions before publication.
    if preserve_direct:
        return "direct"
    base = {"type", "action", "outbound"}
    private_fields = {"ip_is_private", "ip_cidr"}.intersection(rule)
    private_flag = "ip_is_private" not in rule or rule["ip_is_private"] is True
    cidrs = "ip_cidr" not in rule or private_cidrs(rule["ip_cidr"])
    if private_fields and set(rule) <= base | private_fields and private_flag and cidrs:
        return "private"
    allowed = base | {"ip_version", "domain_suffix", "domain"}
    suffixes, domains = strings(rule.get("domain_suffix")), strings(rule.get("domain"))
    known = set(suffixes) <= set(YOUTUBE_SUFFIXES) and set(domains) <= set(
        YOUTUBE_DOMAINS
    )
    valid_domains = ("domain_suffix" not in rule or bool(suffixes)) and (
        "domain" not in rule or bool(domains)
    )
    if (
        set(rule) <= allowed
        and type(rule.get("ip_version")) is int
        and rule["ip_version"] == 4
        and known
        and valid_domains
        and (suffixes or domains)
    ):
        return "youtube"
    raise ProfileError("route.rules.unsupported")


def split_rules(
    route: dict, *, preserve_direct: bool = False
) -> tuple[list[dict], list[dict]]:
    before, after = [], []
    for rule in objects(route.get("rules", []), "route.rules"):
        kind = source_rule_kind(rule, preserve_direct=preserve_direct)
        if kind == "youtube":
            after.append(rule)
        elif after:
            raise ProfileError("route.rules.order")
        else:
            before.append(rule)
    return before, after


def probe_rules(ssid: str | None, *, networks: list[str] | None = None) -> list[dict]:
    allowed = {
        "inbound": [PROBE_TAG],
        "network": "tcp",
        "ip_cidr": ["1.1.1.1/32"],
        "port": 443,
    }
    return [
        {
            **allowed,
            **wifi_condition(ssid, networks=networks),
            "action": "route",
            "outbound": "direct",
        },
        {**allowed, "action": "route", "outbound": "warp"},
        {
            "inbound": [PROBE_TAG],
            "action": "reject",
            "method": "default",
            "no_drop": True,
        },
    ]


def gl_rules(
    ssid: str | None, youtube: str, github: str, *, networks: list[str] | None = None
) -> list[dict]:
    rules = []
    condition = wifi_condition(ssid, networks=networks)
    if youtube == "warp":
        rules.append(
            {
                **condition,
                "domain_suffix": list(YOUTUBE_SUFFIXES),
                "domain": list(YOUTUBE_DOMAINS),
                "action": "route",
                "outbound": "warp",
            }
        )
    if github == "warp":
        rules.append(
            {
                **condition,
                "domain_suffix": list(GITHUB_SUFFIXES),
                "action": "route",
                "outbound": "warp",
            }
        )
    rules.append({**condition, "action": "route", "outbound": "direct"})
    return rules


def direct_dns_override(rule: dict, final_tag: str, condition: dict) -> dict | None:
    if "server" in rule and not isinstance(rule["server"], str):
        raise ProfileError("dns.rules.server")
    if rule.get("server") != final_tag:
        return None
    if rule.get("action", "route") != "route":
        raise ProfileError("dns.rules.final_server_action")
    if rule.get("race") or rule.get("speculative"):
        raise ProfileError("dns.rules.final_server_control")
    action = {
        key: copy.deepcopy(value)
        for key, value in rule.items()
        if key in DNS_ROUTE_ACTION_FIELDS
    }
    action.update(action="route", server=DNS_TAG)
    predicate = {
        key: copy.deepcopy(value)
        for key, value in rule.items()
        if key not in DNS_ROUTE_ACTION_FIELDS
    }
    default_rule = predicate.get("type", "default") in ("", "default")
    if default_rule:
        # Empty matcher lists add no condition in the native default-rule matcher.
        predicate = {key: value for key, value in predicate.items() if value != []}
    if default_rule and not (set(predicate) - {"type", "invert"}):
        if predicate.get("invert", False):
            return None
        return {**copy.deepcopy(condition), **action}
    # Nested DNS rules contain conditions only; action options stay on the wrapper.
    return {
        "type": "logical",
        "mode": "and",
        "rules": [copy.deepcopy(condition), predicate],
        **action,
    }


def add_dns_policy(
    profile: dict, ssid: str | None, *, networks: list[str] | None = None
) -> None:
    dns = profile["dns"]
    servers = objects(dns.get("servers"), "dns.servers")
    if not isinstance(dns.get("final"), str) or not dns["final"]:
        raise ProfileError("dns.final")
    candidates = [server for server in servers if server.get("tag") == dns["final"]]
    if len(candidates) != 1:
        raise ProfileError("dns.final")
    final = candidates[0]
    server = final.get("server")
    if final.get("type") != "https" or not isinstance(server, str) or not server:
        raise ProfileError("dns.final.https")
    if "detour" in final and final["detour"] != "warp":
        raise ProfileError("dns.final.detour")
    rules = objects(dns.get("rules", []), "dns.rules")
    condition = wifi_condition(ssid, networks=networks)
    preserved_rules = []
    for rule in rules:
        override = direct_dns_override(rule, dns["final"], condition)
        if override is not None:
            preserved_rules.append(override)
        preserved_rules.append(rule)
    direct = copy.deepcopy(final)
    direct["tag"] = DNS_TAG
    direct.pop("detour", None)
    dns["servers"] = [*servers, direct]
    dns["rules"] = [
        *preserved_rules,
        {**condition, "action": "route", "server": DNS_TAG},
    ]


def build_profile(
    source: dict,
    ssid: str | None = None,
    youtube: str = "direct",
    github: str = "direct",
    *,
    networks: list[str] | None = None,
) -> dict:
    validate_options(ssid, youtube, github, networks=networks)
    validate_source(source)
    profile = copy.deepcopy(source)
    before, after = split_rules(
        profile["route"], preserve_direct=youtube == "direct" and github == "direct"
    )
    profile["route"]["rules"] = [
        *probe_rules(ssid, networks=networks),
        *before,
        *gl_rules(ssid, youtube, github, networks=networks),
        *after,
    ]
    profile["inbounds"].append(
        {
            "type": "socks",
            "tag": PROBE_TAG,
            "listen": "127.0.0.1",
            "listen_port": PROBE_PORT,
        }
    )
    add_dns_policy(profile, ssid, networks=networks)
    return profile


def read_input(path: Path) -> bytes:
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > PROFILE_LIMIT:
            raise ProfileError("unsafe_input")
        data = source.read(PROFILE_LIMIT + 1)
    if len(data) > PROFILE_LIMIT:
        raise ProfileError("profile_too_large")
    return data


def require_new_output(source: Path, output: Path) -> None:
    if source.resolve() == output.resolve():
        raise ProfileError("source_output_collision")
    if output.exists() or output.is_symlink():
        raise ProfileError("output_exists")
    if not output.parent.is_dir():
        raise ProfileError("output_parent_missing")


def require_isolation() -> None:
    if sys.platform != "darwin":
        raise ProfileError("darwin_required")
    root = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    directory = root / "sfm-warp-maintenance"
    if not root.is_absolute() or directory.is_symlink():
        raise ProfileError("maintenance_state_invalid")
    if not stat.S_ISREG((directory / "paused").lstat().st_mode):
        raise ProfileError("watcher_must_be_paused")
    result = subprocess.run(
        ["/usr/sbin/scutil", "--nc", "status", "SFM"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        timeout=5,
        env=CLEAN_ENV,
        check=False,
    )
    if result.returncode or result.stdout.splitlines()[:1] != [b"Disconnected"]:
        raise ProfileError("sfm_must_be_stopped")


def check_config(binary: Path, path: Path) -> None:
    version = subprocess.run(
        [str(binary), "version"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        timeout=5,
        env=CLEAN_ENV,
        check=False,
    )
    if version.returncode or version.stdout.splitlines()[:1] != [
        f"sing-box version {VERSION}".encode()
    ]:
        raise ProfileError("binary_version_mismatch")
    result = subprocess.run(
        [str(binary), "check", "-c", str(path)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        timeout=20,
        env=CLEAN_ENV,
        check=False,
    )
    if result.returncode:
        details = (result.stderr or b"")[:8192]
        if b"Legacy `strategy` DNS rule action option is deprecated" in details:
            raise ProfileError("legacy_dns_rule_strategy_requires_migration")
        raise ProfileError("configuration_check_failed")


def unlink_owned(path: Path, identity: tuple[int, int]) -> None:
    try:
        info = path.lstat()
        if (info.st_dev, info.st_ino) == identity:
            path.unlink()
    except FileNotFoundError:
        pass


def publish(output: Path, data: bytes, source: Path, original: bytes) -> None:
    fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    info = os.fstat(fd)
    complete = False
    try:
        with os.fdopen(fd, "wb") as destination:
            os.fchmod(destination.fileno(), 0o600)
            destination.write(data)
            destination.flush()
            os.fsync(destination.fileno())
        if read_input(source) != original:
            raise ProfileError("source_changed")
        complete = True
    finally:
        if not complete:
            unlink_owned(output, (info.st_dev, info.st_ino))


def create_profile(
    source: Path,
    output: Path,
    binary: Path,
    ssid: str | None,
    youtube: str,
    github: str,
    *,
    networks: list[str] | None = None,
) -> dict:
    require_new_output(source, output)
    require_isolation()
    original = read_input(source)
    profile = build_profile(
        decode_profile(original), ssid, youtube, github, networks=networks
    )
    if input("Type CREATE to create the separate profile: ") != "CREATE":
        raise ProfileError("creation_cancelled")
    data = canonical(profile) + b"\n"
    with tempfile.TemporaryDirectory(
        prefix="sfm-gl-profile-", dir=os.environ.get("TMPDIR")
    ) as raw:
        temporary = Path(raw) / "profile.json"
        publish(temporary, data, source, original)
        check_config(binary, temporary)
    require_isolation()
    if read_input(source) != original:
        raise ProfileError("source_changed")
    publish(output, data, source, original)
    return {
        "created": True,
        "checked": True,
        "source_unchanged": True,
        "output": str(output),
    }


def main(arguments: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user-run", action="store_true")
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--binary",
        type=Path,
        required=True,
        help="previously verified official sing-box 1.14.2 binary",
    )
    selector = parser.add_mutually_exclusive_group(required=True)
    selector.add_argument("--ssid")
    selector.add_argument("--networks", nargs=2, metavar=("IPV4_CIDR", "IPV6_CIDR"))
    parser.add_argument("--youtube", choices=("direct", "warp"), default="direct")
    parser.add_argument("--github", choices=("direct", "warp"), default="direct")
    args = parser.parse_args(arguments)
    try:
        if not args.user_run or not sys.stdin.isatty() or not sys.stdout.isatty():
            raise ProfileError("interactive_user_run_required")
        validate_options(args.ssid, args.youtube, args.github, networks=args.networks)
        result = create_profile(
            args.profile.expanduser().absolute(),
            args.output.expanduser().absolute(),
            args.binary.expanduser().absolute(),
            args.ssid,
            args.youtube,
            args.github,
            networks=args.networks,
        )
    except ProfileError as error:
        result = {"created": False, "error": str(error)}
    except (
        OSError,
        ValueError,
        TypeError,
        KeyError,
        RecursionError,
        subprocess.SubprocessError,
        EOFError,
        KeyboardInterrupt,
    ):
        result = {"created": False, "error": "profile_creation_failed"}
    print(json.dumps(result, sort_keys=True))
    return 0 if result["created"] else 1


def interrupted(_signal: int, _frame: object) -> None:
    raise ProfileError("interrupted")


if __name__ == "__main__":
    for interrupt in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(interrupt, interrupted)
    raise SystemExit(main())
