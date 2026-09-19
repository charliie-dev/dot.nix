"""User-run, atomic merge of only the shared Bashka hook."""

import argparse
import copy
import json
import os
import shlex
import stat
import sys
import tempfile
from pathlib import Path

HANDLER = "@handler@"
SETTINGS = "@settings@"


class Conflict(Exception):
    pass


def invalid_constant(_value):
    raise Conflict("non-JSON numeric constant")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise Conflict("duplicate JSON keys")
        result[key] = value
    return result


def merge(original, action):
    if not isinstance(original, dict):
        raise Conflict("settings must be a JSON object")
    result = copy.deepcopy(original)
    hooks = result.get("hooks", {})
    if not isinstance(hooks, dict):
        raise Conflict("hooks must be an object")
    expected = {"type": "command", "command": shlex.quote(HANDLER), "timeout": 10}
    matches = own_hooks(hooks, expected)
    if len(matches) > 1:
        raise Conflict("duplicate Bashka hooks")
    if action == "install" and not matches:
        hooks.setdefault("PreToolUse", []).append(
            {"matcher": "Bash", "hooks": [expected]}
        )
        result["hooks"] = hooks
    if action == "remove" and matches:
        group_index, hook_index = matches[0]
        groups = hooks["PreToolUse"]
        del groups[group_index]["hooks"][hook_index]
        if not groups[group_index]["hooks"]:
            del groups[group_index]
        if not groups:
            del hooks["PreToolUse"]
        if not hooks:
            del result["hooks"]
    return result


def own_hooks(hooks, expected):
    matches = []
    for event, groups in hooks.items():
        if not isinstance(groups, list):
            raise Conflict("hook event groups must be arrays")
        for index, group in enumerate(groups):
            check_group(event, index, group, expected, matches)
    return matches


def check_group(event, index, group, expected, matches):
    if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
        raise Conflict("invalid hook group")
    for hook_index, hook in enumerate(group["hooks"]):
        if not isinstance(hook, dict):
            raise Conflict("invalid hook entry")
        command = hook.get("command", "")
        if not isinstance(command, str):
            raise Conflict("invalid hook command")
        if command != expected["command"] and HANDLER not in command:
            continue
        if hook != expected or event != "PreToolUse" or group.get("matcher") != "Bash":
            raise Conflict("conflicting Bashka registration; reconcile it manually")
        matches.append((index, hook_index))


def identity(info):
    return (
        info.st_dev,
        info.st_ino,
        info.st_uid,
        info.st_gid,
        info.st_mode,
        info.st_nlink,
        info.st_size,
        info.st_mtime_ns,
        info.st_ctime_ns,
    )


def check_file(info):
    if (
        not stat.S_ISREG(info.st_mode)
        or info.st_uid != os.getuid()
        or info.st_nlink != 1
    ):
        raise Conflict("settings must be a single-link regular file owned by this user")
    if info.st_mode & 0o022:
        raise Conflict("settings must not be writable by other users")


def snapshot(path):
    try:
        before = path.lstat()
    except FileNotFoundError:
        return None, None
    check_file(before)
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as handle:
        opened = os.fstat(handle.fileno())
        check_file(opened)
        if identity(before) != identity(opened):
            raise Conflict("settings changed while opening")
        data = handle.read()
        if identity(opened) != identity(os.fstat(handle.fileno())):
            raise Conflict("settings changed while reading")
    return opened, data


def parent_info(path):
    parent = path.parent
    info = parent.lstat()
    if (
        not stat.S_ISDIR(info.st_mode)
        or info.st_uid != os.getuid()
        or info.st_mode & 0o022
    ):
        raise Conflict(
            "settings directory must be owned by this user and not writable by others"
        )
    if parent.resolve() != parent:
        raise Conflict("settings directory must not contain symlinks")
    return info


def unchanged(path, parent, before, data):
    current_parent = parent_info(path)
    if (current_parent.st_dev, current_parent.st_ino) != (parent.st_dev, parent.st_ino):
        raise Conflict("settings directory changed")
    current, current_data = snapshot(path)
    if (identity(current) if current else None) != (
        identity(before) if before else None
    ) or current_data != data:
        raise Conflict("concurrent settings modification; no replacement made")


def update(path, action):
    parent = parent_info(path)
    before, data = snapshot(path)
    original = (
        {}
        if data is None
        else json.loads(
            data, object_pairs_hook=unique_object, parse_constant=invalid_constant
        )
    )
    result = merge(original, action)
    if result == original:
        return False
    encoded = (
        json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
    ).encode("utf-8")
    temp_dir = os.environ.get("TMPDIR")
    if not temp_dir or not os.path.isabs(temp_dir):
        raise Conflict("set TMPDIR to an absolute directory on the settings filesystem")
    descriptor, temporary = tempfile.mkstemp(prefix="bashka-settings-", dir=temp_dir)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            if os.fstat(handle.fileno()).st_dev != parent.st_dev:
                raise Conflict(
                    "TMPDIR and settings must share a filesystem for atomic replacement"
                )
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
            if before and os.fstat(handle.fileno()).st_gid != before.st_gid:
                os.fchown(handle.fileno(), before.st_uid, before.st_gid)
            os.fchmod(
                handle.fileno(), stat.S_IMODE(before.st_mode) if before else 0o600
            )
        unchanged(path, parent, before, data)
        if before is None:
            os.link(temporary, path)
        else:
            os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Stop settings editors and cc/gb before merging the shared hook. Never prints settings values."
    )
    parser.add_argument("action", choices=("install", "remove"))
    parser.add_argument(
        "--settings-idle",
        required=True,
        action="store_true",
        help="confirm that no other process is editing settings",
    )
    args = parser.parse_args()
    try:
        changed = update(Path(SETTINGS), args.action)
    except (Conflict, OSError, ValueError, RecursionError) as error:
        # OSError and decoder messages can contain settings content or paths.
        detail = (
            str(error)
            if isinstance(error, Conflict)
            else "settings IO or JSON validation failed"
        )
        print("Bashka registration stopped: " + detail, file=sys.stderr)
        return 1
    print("Bashka hook updated." if changed else "Bashka hook unchanged.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
