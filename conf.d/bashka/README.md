# Bashka hooks for Claude Code and Grok Build

This integration denies supported, visible network-to-shell installer calls. It
never downloads, executes an installer, returns an `allow`, or rewrites tool input
from the hook. A denied call must be explicitly retried through
`~/.config/bashka/agent-run`, under the agent's existing permissions and sandbox.

The runner uses Bashka's normal `--non-interactive` mode with a fixed store policy:
GREEN and NEUTRAL can proceed; RED, StrongGate, Critical, and errors stop. It does
not use `--check` to authorize execution. Bashka 0.12.0 uses exit 1 for both
NEUTRAL checks and errors. The tests use check codes only to verify the categories
of harmless fixtures, never to choose an execution path.

## Supported boundary

- `curl`/`wget` pipelines into Bash, sh, dash, zsh, ksh, source, `.`, eval, or raw
  Bashka, including intermediate stages, newlines, absolute executables, and known
  `env`, `command`, and `sudo` prefixes.
- Download substitutions used as shell arguments, command strings, process
  substitutions, here-strings, or here-document stdin.
- Static shell `-c` strings, static eval strings, and shell here-document code.
- Raw Bashka consumers are denied too: callers must use the fixed runner rather
  than choose their own Bashka options or config.

Nonmatches produce no output. Malformed JSON, conflicting aliases, truncated
input, syntax errors, and controlled resource failures produce a valid deny.
ANSI-C quoting in executable names and static shell/eval code is rejected rather
than decoded; ordinary ANSI-C-quoted arguments to commands such as printf pass.
Claude snake_case and Grok camelCase fields are supported together, including
`PreToolUse`/`pre_tool_use` and `Bash`/`run_terminal_command` equivalents.

This is not a shell interpreter or a general sandbox. Classification is
conservative for visible connections and does not prove whether every connected
stage actually consumes its input. Files downloaded and executed later (even in
one tool call), aliases, dynamic executable variables, dynamic eval strings,
unknown wrapper options such as `env -S`, other programming languages, and other
execution tools are outside the boundary. Nonexecuting quoted text, comments,
ordinary package commands, and standalone downloads pass unchanged.

Bashka checks and executes the same top-level source through its native Bash
runner. This does not guarantee the provenance of later downloads. Scripts
requiring sh/zsh/source-specific semantics must not be silently changed to Bash.
There is no credential isolation, and ordinary installer environment remains
available. The installed Bashka binary and Nix store dependencies are trusted;
this does not defend against a malicious process running as the same user.

## Startup and limits

All three executables start directly with Nix Python `-IS`, without a Bash
bootstrap. The parser site is explicit; the working directory, Python environment
search paths, user site, and site customization do not control imports. The runner
clears inherited Bash startup controls, exported Bash functions, `BASHFLAGS_*`,
and loader injection variables; it pins the native Bash search to Nix Bash first.
Installer arguments follow two literal `--` arguments, yielding native
`bash -s -- <installer arguments>`.

Budgets are shared across nested parses: 1 MiB JSON, 1 MiB cumulative UTF-8 source,
50,000 AST nodes, depth 32, eight nested parses, two seconds of parser/AST work,
and three seconds total including stdin. Registration sets a ten-second host
timeout. Tree-sitter 0.25.2 needs a callable source and a two-argument
`progress_callback(offset, has_error)`; parsing bytes ignores progress callbacks.
Original UTF-8 slices, not `node.text`, supply node content.

Host startup failures, crashes, external timeouts, extreme scheduling pauses, or
other hooks rewriting input afterward can bypass this guard. These platforms can
fail open; this integration does not claim platform-level fail-closed behavior.

## User-run deployment

Do not run activation or registration from an agent. Stop cc/gb and all settings
editors first. On the current Darwin host, build/activate from the path flake so
new local source files are included:

```sh
home-manager switch --flake 'path:/Users/charles/.config/home-manager#charles@24041-LABNB01'
"$HOME/.config/bashka/register-hooks" install --settings-idle
```

The installed binary must already exist at
`~/.local/share/mise/installs/github-dmtr-kovalenko-bashka/latest/bashka`.
Missing binaries fail without invoking mise, a credential helper, or a fallback
shell. The agent does not install or refresh that binary.

The helper targets the configured XDG Claude `settings.json`, not an environment
selected alternative. It preserves unrelated JSON values and hook order, retains
file mode/group, rejects unexpected links/owners/conflicts, and atomically replaces
from a restricted temporary file under `$TMPDIR`. `$TMPDIR` must be absolute and
on the same filesystem. It checks for concurrent changes before replacement, but
the last-check/replace window requires exclusive writers; `--settings-idle` is an
explicit acknowledgment, not a filesystem compare-and-swap guarantee. Existing
ACLs and extended attributes are not copied; review them before deployment if used.

Only one Claude `PreToolUse`/`Bash` group is added. Grok's enabled Claude
compatibility supplies the same hook; do not register a second Grok hook.
SessionStart/PreCompact groups and Herdr indices are not reordered. Restart cc/gb
and verify one loaded hook in each, a bare installer denial, and the expected
fixed-entry allow/deny behavior. Check project/plugin hooks for later rewrites.
Live loading is a separate user-run acceptance check.

Remove only this hook before removing its managed executables:

```sh
"$HOME/.config/bashka/register-hooks" remove --settings-idle
```

## Isolated regression suite

`/opt/homebrew/bin/bats tests/apps/bashka-hooks.bats` builds synthetic-root entries
under a task-owned `mktemp` directory. No live settings are used. Native fixtures
require the verified Bashka 0.12.0 binary with SHA256
`b4a23d4361212ae582a5b1502b4d7a5d785658a9bf3142b02a8481f638fb2c9f`.
Downloads in severity fixtures are in constant-false branches and never run.
The suite fails rather than skipping a missing native binary. Other platforms
need a separately verified native fixture path and hash before running this suite.
