"""Bounded, side-effect-free classification of visible network-to-shell forms."""

import time

STARTED = time.monotonic()

import json
import shlex
import signal
import sys
from dataclasses import dataclass

PARSER_SITE = "@parserSite@"
ENTRY = "@entry@"
MAX_BYTES = 1024 * 1024
MAX_NODES = 50_000
MAX_DEPTH = 32
MAX_PARSES = 8
PARSER_SECONDS = 2.0
TOTAL_SECONDS = 3.0
SHELLS = {"bash", "sh", "dash", "zsh", "ksh"}
SINKS = SHELLS | {"source", ".", "eval", "bashka"}
FETCHERS = {"curl", "wget"}
# Claude Code sandbox: only $TMPDIR (/tmp/claude-<uid>/...) is writable under /tmp,
# Apple diff cannot open /dev/fd/N, and nothing can write to /dev/fd/N.
TMP_ROOTS = ("/tmp", "/private/tmp")
TMP_ALLOWED = ("/tmp/claude", "/private/tmp/claude")
WRITE_REDIRECTS = {">", ">>", "&>", "&>>", ">|", "<>", ">&"}
TMP_ANY_ARGUMENT = {"mktemp", "mkdir", "touch", "tee"}
TMP_LAST_ARGUMENT = {"cp", "mv", "install", "ln"}
# sandbox.excludedCommands only matches a whole, plain `git <subcommand> ...` call
# (trailing-* prefix patterns); pipes, lists, heredocs and wrappers keep it sandboxed.
GIT_SPLIT = {"push", "fetch", "pull", "ls-remote", "clone"}
GIT_OPTION_OPERANDS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
# Commits and tags must stay signed; a signing failure is reported, never bypassed.
GIT_SIGN_KEYS = {"commit.gpgsign", "tag.gpgsign"}
GIT_FALSE = {"false", "no", "off", "0", ""}
GIT_NO_SIGN_FLAGS = {"--no-gpg-sign", "--no-sign"}
GIT_CONFIG_UNSET = {"--unset", "--unset-all", "unset"}
SIGNING_AGENT = "gui/$(id -u)/org.nix-community.home.ssh-signing-agent"


class Deny(Exception):
    pass


class Budget:
    def __init__(self, started=STARTED):
        self.total_due = started + TOTAL_SECONDS
        self.work_due = None
        self.bytes = 0
        self.nodes = 0
        self.parses = 0

    def check(self):
        now = time.monotonic()
        if now >= self.total_due or (
            self.work_due is not None and now >= self.work_due
        ):
            raise Deny("analysis deadline exceeded")

    def source(self, source, nested):
        self.check()
        self.bytes += len(source)
        self.parses += int(nested)
        if self.bytes > MAX_BYTES or self.parses > MAX_PARSES:
            raise Deny("cumulative source or nested parse limit exceeded")
        if self.work_due is None:
            self.work_due = min(self.total_due, time.monotonic() + PARSER_SECONDS)

    def node(self, depth):
        self.check()
        self.nodes += 1
        if self.nodes > MAX_NODES or depth > MAX_DEPTH:
            raise Deny("AST node or depth limit exceeded")

    def progress(self, _offset, _has_error):
        return time.monotonic() >= min(self.total_due, self.work_due)


@dataclass
class Info:
    network: bool = False
    sink: bool = False
    literal: str | None = None
    static_unknown: bool = False


def static_word(kind, text, children):
    if kind == "raw_string":
        return text[1:-1]
    if kind in {"command_name", "concatenation", "string", "herestring_redirect"}:
        values = [info.literal for _, info in children]
        return "".join(values) if all(v is not None for v in values) else None
    if kind == "string_content":
        # Double quotes remove backslashes only before these shell characters.
        result, index = [], 0
        while index < len(text):
            if (
                text[index] == "\\"
                and index + 1 < len(text)
                and text[index + 1] in '$`"\\\n'
            ):
                index += 1
                if text[index] == "\n":
                    index += 1
                    continue
            result.append(text[index])
            index += 1
        return "".join(result)
    if kind != "word":
        return None
    try:
        parts = shlex.split(text.replace("\\\n", ""), comments=False)
        return parts[0] if len(parts) == 1 else None
    except ValueError:
        return None


def shared_tmp(value):
    """A static path under /tmp that is not the sandbox's own $TMPDIR tree."""
    if value is None:
        return False
    path = value.split("=", 1)[-1]
    return any(
        path == root or path.startswith(root + "/") for root in TMP_ROOTS
    ) and not path.startswith(TMP_ALLOWED)


def git_unsigned(operands):
    """How static `git` operands turn commit or tag signing off, if they do."""
    index = 0
    while index < len(operands):
        value = operands[index]
        if value is None or not value.startswith("-"):
            break
        if value == "-c" and index + 1 < len(operands) and operands[index + 1]:
            key, equals, setting = operands[index + 1].partition("=")
            if key.lower() in GIT_SIGN_KEYS and equals and setting.lower() in GIT_FALSE:
                return f"-c {key}={setting}"
        index += 2 if value in GIT_OPTION_OPERANDS else 1
    rest = [w for w in operands[index:] if w is not None]
    if flag := next((w for w in rest[1:] if w in GIT_NO_SIGN_FLAGS), None):
        return flag
    if (
        rest[:1] == ["config"]
        and any(w.lower() in GIT_SIGN_KEYS for w in rest)
        and any(w in GIT_CONFIG_UNSET or w.lower() in GIT_FALSE for w in rest[1:])
    ):
        return "git config turning signing off"
    return None


def git_split_op(operands):
    """The excludedCommands-listed git operation in `git` operands, if static."""
    index = 0
    while index < len(operands):
        value = operands[index]
        if value is None or not value.startswith("-"):
            break
        index += 2 if value in GIT_OPTION_OPERANDS else 1
    if index >= len(operands) or operands[index] is None:
        return None
    sub, rest = operands[index], [w for w in operands[index + 1 :] if w is not None]
    if sub in GIT_SPLIT:
        return sub
    if sub in {"worktree", "remote"} and rest[:1] == [
        {"worktree": "add", "remote": "set-url"}[sub]
    ]:
        return f"{sub} {rest[0]}"
    if sub == "branch" and any(w.startswith("--set-upstream-to") for w in rest):
        return "branch --set-upstream-to"
    if (
        sub == "tag"
        and any(not w.startswith("-") for w in rest)
        and not {"-l", "--list"} & set(rest)
    ):
        return "tag"
    return None


def executable(words):
    """Unwrap only known execution prefixes; unknown dynamic prefixes stay out of scope."""
    index = 0
    while index < len(words):
        value = words[index]
        if value is None:
            return None, index + 1
        name = value.rsplit("/", 1)[-1]
        index += 1
        if name not in {"env", "command", "sudo"}:
            return name, index
        index = prefix_end(name, words, index)
    return None, index


def prefix_end(name, words, index):
    flags = {
        "env": {"-i", "--ignore-environment", "-0", "--null"},
        "command": {"-p"},
        "sudo": {
            "-n",
            "-E",
            "-H",
            "-S",
            "-k",
            "-b",
            "--non-interactive",
            "--preserve-env",
        },
    }
    operands = {
        "env": {"-u", "--unset", "-C", "--chdir"},
        "command": set(),
        "sudo": {
            "-u",
            "--user",
            "-g",
            "--group",
            "-h",
            "--host",
            "-p",
            "--prompt",
            "-C",
            "-T",
            "-D",
            "--chdir",
        },
    }
    while index < len(words):
        value = words[index]
        if value is None:
            return len(words)
        if value == "--":
            return index + 1
        if value in flags[name] or ("=" in value and not value.startswith("-")):
            index += 1
        elif value in operands[name]:
            index += 2
        elif (
            value.startswith("--")
            and value.split("=", 1)[0] in operands[name]
            and "=" in value
        ):
            index += 1
        elif value.startswith("-"):
            return len(words)
        else:
            return index
    return index


def shell_code(arguments):
    index = 0
    command_mode = False
    short_options = False
    while index < len(arguments):
        value = arguments[index].literal
        if arguments[index].static_unknown:
            raise Deny("unsupported static quoting in shell options or code")
        if value in {"--", "-", "+"}:
            index += 1
            break
        if value is None or not value.startswith(("-", "+")):
            break
        if value.startswith("--"):
            if short_options:
                raise Deny("unsupported long shell option after short options")
            index += shell_long_option_size(value)
            continue
        flags = value[1:]
        if not set(flags) <= set("abcefhiklmnoprstuvxBCEHDOPT"):
            raise Deny("unsupported shell option while locating command text")
        short_options = True
        # Bash keeps scanning options after either -c or +c.
        command_mode |= "c" in flags
        index += 1 + sum(flag in {"o", "O"} for flag in flags)
    return arguments[index] if command_mode and index < len(arguments) else Info()


def shell_long_option_size(value):
    if value in {"--rcfile", "--init-file"}:
        return 2
    if value in {
        "--debugger",
        "--dump-po-strings",
        "--dump-strings",
        "--help",
        "--login",
        "--noediting",
        "--noprofile",
        "--norc",
        "--posix",
        "--pretty-print",
        "--restricted",
        "--verbose",
        "--version",
    }:
        return 1
    raise Deny("unsupported long shell option while locating command text")


class Classifier:
    def __init__(self, parser, budget):
        self.parser = parser
        self.budget = budget
        self.sandbox_issues = []
        self.git_ops = []
        self.nesting = 0

    def sandbox_issue(self, issue):
        if issue not in self.sandbox_issues:
            self.sandbox_issues.append(issue)

    def check_git(self, root):
        """Listed git operations must be the whole command to match excludedCommands."""
        if not self.git_ops:
            return
        standalone = False
        if len(self.git_ops) == 1 and len(root.named_children) == 1:
            node, _, nesting, plain = self.git_ops[0]
            body = statement = root.named_children[0]
            if statement.type == "redirected_statement":
                body = statement.child_by_field_name("body")
                if any(
                    child.type != "file_redirect"
                    for child in statement.named_children
                    if child != body
                ):
                    body = None
            standalone = nesting == 0 and plain and body == node
        if not standalone:
            for _, op, _, _ in self.git_ops:
                self.sandbox_issue(f"git {op} inside a compound or wrapped command")

    def parse(self, source, nested=False):
        self.budget.source(source, nested)

        def read(offset, _point):
            self.budget.check()
            return source[offset : offset + 4096]

        tree = self.parser.parse(read, progress_callback=self.budget.progress)
        self.budget.check()
        if tree is None or tree.root_node.has_error:
            raise Deny("shell syntax could not be parsed completely")
        info = self.visit(tree.root_node, source, 0)
        if not nested:
            self.check_git(tree.root_node)
        return info

    def visit(self, node, source, depth):
        self.budget.node(depth)
        children = [
            (child, self.visit(child, source, depth + 1)) for child in node.children
        ]
        named = [(child, info) for child, info in children if child.is_named]
        text = source[node.start_byte : node.end_byte].decode("utf-8")
        info = Info(
            network=any(i.network for _, i in named),
            static_unknown=node.type == "ansi_c_string"
            or any(i.static_unknown for _, i in named),
        )
        info.literal = static_word(node.type, text, named)
        if node.type == "process_substitution" and text.startswith(">("):
            self.sandbox_issue("output process substitution >(...)")
        if node.type == "file_redirect":
            operator = next((c.type for c in node.children if not c.is_named), None)
            if operator in WRITE_REDIRECTS and any(
                shared_tmp(i.literal) for c, i in named if c.type != "file_descriptor"
            ):
                self.sandbox_issue("a redirect that writes under /tmp")
        if node.type == "command":
            return self.command(node, named, info)
        if node.type == "pipeline":
            self.pipeline(named)
        if node.type == "redirected_statement":
            self.redirected(named, source)
        if node.type not in {
            "command_substitution",
            "process_substitution",
            "string",
            "concatenation",
        }:
            info.sink = any(i.sink for _, i in named)
        return info

    def command(self, node, children, info):
        fields = {
            child.id: node.field_name_for_child(i)
            for i, child in enumerate(node.children)
        }
        arguments = [
            value
            for child, value in children
            if fields[child.id] in {"name", "argument"}
        ]
        words = [value.literal for value in arguments]
        name, offset = executable(words)
        if name is None and info.static_unknown:
            raise Deny("unsupported static quoting in an executable name or prefix")
        info.sink = name in SINKS
        if info.sink and info.network:
            raise Deny("downloaded content is passed directly to a shell or raw Bashka")
        if name in SHELLS:
            code = shell_code(arguments[offset:])
            if code.static_unknown:
                raise Deny("unsupported static quoting in shell code")
            info.network |= self.nested(code.literal).network
        if name == "eval" and info.static_unknown:
            raise Deny("unsupported static quoting in eval code")
        if name == "eval" and all(word is not None for word in words[offset:]):
            code_words = words[offset:]
            if code_words[:1] == ["--"]:
                code_words = code_words[1:]
            info.network |= self.nested(" ".join(code_words)).network
        if info.sink:
            self.stdin(children)
        info.network |= name in FETCHERS
        operands = words[offset:]
        if name == "diff" and any(
            child.type == "process_substitution"
            for child, _ in children
            if fields[child.id] == "argument"
        ):
            self.sandbox_issue("diff with <(...) operands")
        if (name in TMP_ANY_ARGUMENT and any(map(shared_tmp, operands))) or (
            name in TMP_LAST_ARGUMENT and operands and shared_tmp(operands[-1])
        ):
            self.sandbox_issue(f"{name} writing under /tmp")
        unsigned = git_unsigned(operands) if name == "git" else None
        if unsigned is not None:
            self.sandbox_issue(f"signing disabled with {unsigned}")
        op = git_split_op(operands) if name == "git" else None
        if op is not None:
            plain = offset == 1 and words[0] == "git"
            self.git_ops.append((node, op, self.nesting, plain))
        return info

    def nested(self, text):
        if text is None:
            return Info()
        self.nesting += 1
        try:
            return self.parse(text.encode("utf-8"), nested=True)
        finally:
            self.nesting -= 1

    @staticmethod
    def pipeline(children):
        network = False
        for _, info in children:
            if network and info.sink:
                raise Deny("a visible network pipeline feeds a shell or raw Bashka")
            network |= info.network

    def stdin(self, children):
        for child, info in children:
            if child.type not in {
                "herestring_redirect",
                "heredoc_redirect",
                "file_redirect",
            }:
                continue
            if info.network:
                raise Deny("downloaded content is redirected into a shell")
            if child.type == "herestring_redirect":
                if info.static_unknown:
                    raise Deny("unsupported static quoting in shell stdin")
                self.nested(info.literal)

    def redirected(self, children, source):
        sink = any(
            info.sink for child, info in children if child.type != "heredoc_redirect"
        )
        for node, info in children:
            if node.type == "heredoc_redirect":
                if (sink or info.sink) and info.network:
                    raise Deny("downloaded content is inserted into shell stdin")
                self.heredoc(node, source, sink or info.sink)
            elif sink and node.type == "file_redirect" and info.network:
                raise Deny("downloaded content is redirected into a shell")

    def heredoc(self, node, source, sink):
        if not sink:
            return
        body = next(
            (child for child in node.named_children if child.type == "heredoc_body"),
            None,
        )
        if body is not None:
            self.nested(source[body.start_byte : body.end_byte].decode("utf-8"))


def invalid_constant(_value):
    raise Deny("non-JSON numeric constant")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise Deny("duplicate JSON fields")
        result[key] = value
    return result


def field(payload, snake, camel, default=None):
    if snake in payload and camel in payload and payload[snake] != payload[camel]:
        raise Deny("conflicting hook fields")
    return payload.get(snake, payload.get(camel, default))


def command_input(payload):
    if not isinstance(payload, dict):
        raise Deny("hook payload must be an object")
    event = payload.get("hook_event_name", "PreToolUse")
    camel_event = payload.get("hookEventName", "pre_tool_use")
    if event != "PreToolUse" or camel_event not in {"pre_tool_use", "PreToolUse"}:
        raise Deny("unexpected hook event")
    names = [payload[key] for key in ("tool_name", "toolName") if key in payload]
    canonical = ["Bash" if name == "run_terminal_command" else name for name in names]
    if not canonical or any(name != canonical[0] for name in canonical):
        raise Deny("missing or conflicting tool names")
    name = canonical[0]
    tool_input = field(payload, "tool_input", "toolInput")
    truncated = field(payload, "tool_input_truncated", "toolInputTruncated", False)
    if truncated is not False:
        raise Deny("truncated or invalid tool input")
    if name not in {"Bash", "run_terminal_command"}:
        if not isinstance(name, str):
            raise Deny("missing tool name")
        return None
    if not isinstance(tool_input, dict) or not isinstance(
        tool_input.get("command"), str
    ):
        raise Deny("shell command must be a complete string")
    command = tool_input["command"]
    if "\0" in command:
        raise Deny("shell command contains NUL")
    return command.encode("utf-8")


def alarm(_signum, _frame):
    raise Deny("handler deadline exceeded")


def emit_deny(reason):
    emit(
        f"Bashka guard: {reason}. The original command was not approved or rewritten. "
        f"Only for an authorized Bash-compatible installation, explicitly retry the download piped to {shlex.quote(ENTRY)} "
        "with installer arguments only. This entry EXECUTES allowed scripts; it is not a read-only checker. "
        "For read-only analysis, download without execution and inspect/check the saved content instead. "
        "GREEN/NEUTRAL may proceed; RED, stronger gates, and errors stop. "
        "Do not silently replace sh/zsh/source-specific semantics; ask the user if needed."
    )


def emit_sandbox_deny(issues):
    fixes = []
    signing = [issue for issue in issues if issue.startswith("signing disabled")]
    git = [issue for issue in issues if issue.startswith("git ")]
    if len(signing) + len(git) < len(issues):
        fixes.append(
            'Create temporary files with mktemp "$TMPDIR/name.XXXXXX" (never a fixed /tmp '
            "path), and materialize each <(...) or >(...) stream as one of those files before "
            "diff or tee use it. Input <(...) to other tools is fine."
        )
    if signing:
        fixes.append(
            "Never turn commit or tag signing off (--no-gpg-sign, --no-sign, "
            "-c commit.gpgsign=false, -c tag.gpgsign=false or git config). If signing fails, "
            "stop and tell the user; the signing agent restarts with "
            f"`launchctl kickstart -k {SIGNING_AGENT}`."
        )
    if git:
        fixes.append(
            "Run each git push, fetch, pull, ls-remote, clone, worktree add, remote set-url, "
            "branch --set-upstream-to or tag-creating command as its own tool call: one plain "
            "`git <subcommand> ...` (leading env assignments and file redirects such as 2>&1 "
            "are fine) with no pipes, &&, ;, subshells, heredocs, comments or wrappers, so it "
            "matches sandbox.excludedCommands and runs outside the sandbox. A `git -C <path>` "
            "form never matches excludedCommands; if that single command fails on sandbox "
            "limits, rerun just it with dangerouslyDisableSandbox: true."
        )
    emit(
        f"Policy guard: {'; '.join(issues)}. The original command was not run. "
        f"{' '.join(fixes)} This applies with or without the sandbox."
    )


def emit(message):
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": message,
                }
            }
        )
    )


def main():
    budget = Budget()
    signal.signal(signal.SIGALRM, alarm)
    signal.setitimer(
        signal.ITIMER_REAL, max(0.001, budget.total_due - time.monotonic())
    )
    reason = None
    issues = []
    try:
        raw = sys.stdin.buffer.read(MAX_BYTES + 1)
        budget.check()
        if len(raw) > MAX_BYTES:
            raise Deny("hook JSON exceeds 1 MiB")
        payload = json.loads(
            raw, object_pairs_hook=unique_object, parse_constant=invalid_constant
        )
        command = command_input(payload)
        if command is not None:
            sys.path.append(PARSER_SITE)
            import tree_sitter_bash
            from tree_sitter import Language, Parser

            classifier = Classifier(
                Parser(Language(tree_sitter_bash.language())), budget
            )
            classifier.parse(command)
            issues = classifier.sandbox_issues
        budget.check()
    except Deny as error:
        reason = str(error)
    except (
        ValueError,
        TypeError,
        KeyError,
        RecursionError,
        MemoryError,
        ImportError,
        OSError,
        RuntimeError,
        OverflowError,
        AttributeError,
        SystemError,
    ):
        reason = "invalid input or analysis failure"
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
    if reason is not None:
        emit_deny(reason)
    elif issues:
        emit_sandbox_deny(issues)
    return 0


if __name__ == "__main__":
    sys.exit(main())
