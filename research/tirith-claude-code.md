# Tirith without interactive-shell integration

Research date: 2026-08-30

## Recommendation

Use a user-scoped Claude Code `PreToolUse` hook for the `Bash` tool and remove
Tirith's manual Zsh initialization. Keep the Tirith executable installed, but do
not load `tirith init` in interactive shells.

For this Home Manager setup, the preferred implementation is:

1. Remove the manual `tirith init --shell zsh` block from
   `modules/apps/zsh/keybindings.nix`.
2. Keep `programs.tirith.enable = true` and all shell-integration options off.
3. Let Home Manager build an immutable wrapper around Tirith's official hook,
   using absolute Nix-store paths for Python and Tirith.
4. Merge one user-scoped `PreToolUse` entry into the existing mutable Claude
   settings file at `$CLAUDE_CONFIG_DIR/settings.json` without copying that file
   or its secret-bearing `env` values into the Nix store.
5. Explicitly choose warning behavior rather than relying on Tirith's documented
   default.

This gives all local Claude Code launches that use the normal config directory
automatic coverage, including subagents, while ordinary terminal commands are no
longer intercepted. It is preferable to a `claude --settings` wrapper when
Claude Code may also be started by Herdr, another shell, a script, or an IDE.

If every Claude Code session is guaranteed to start through the existing Zsh
`claude` function, a separate Nix-generated file passed with `--settings` is the
simpler alternative. It avoids mutating the existing settings file, but any
launch that bypasses that function also bypasses Tirith.

## Confirmed local state

At the start of this research:

- `modules/apps/tirith.nix` enabled Tirith and explicitly disabled Home
  Manager's built-in Zsh integration.
- `modules/apps/zsh/keybindings.nix` nevertheless initialized Tirith manually
  with `eval "$(tirith init --shell zsh)"`. That block is the integration that
  affects normal interactive shell use.
- Claude Code used `CLAUDE_CONFIG_DIR=~/.config/claude`, while `~/.claude` was a
  symlink to that directory.
- The user Claude settings already contained `SessionStart` and `PreCompact`
  hooks, but no `PreToolUse` hook.
- The installed versions were Claude Code 2.1.250 and Tirith 0.3.3.
- The pinned Home Manager Tirith module only manages the package, policy file,
  allowlist, and Bash/Fish/Zsh initialization. It has no Claude Code option.

## Why `PreToolUse` is the right boundary

Tirith documents two Claude Code integrations:

- The `PreToolUse` hook automatically receives each `Bash` tool call before
  execution and can deny it.
- The optional Model Context Protocol (MCP) server only exposes tools that the
  model may call deliberately; it does not automatically intercept Bash.

Claude Code passes hook input as JSON on standard input. A `PreToolUse` hook can
match exactly `Bash`, inspect `tool_input.command`, and return
`hookSpecificOutput.permissionDecision = "deny"`. Claude Code documents that a
hook deny is always honored, including when the permission mode is
`bypassPermissions`. User-settings hooks also run for Bash calls made by
subagents.

The official Tirith adapter invokes:

```text
tirith check --json --non-interactive --shell posix -- <command>
```

It maps Tirith's block result to Claude's structured deny response. Missing
Tirith, malformed input, unexpected exits, and the adapter's internal timeout
are fail-closed unless `TIRITH_FAIL_OPEN=1` is set.

On this host, direct checks took about 48 ms median and 76 ms at the 95th
percentile over 20 safe-command runs. That cost moves from every interactive
shell submission to Claude Code Bash calls only.

## Why the automatic setup command is not suitable here

`tirith setup claude-code` is useful for conventional layouts, but should not be
run directly against this home directory:

1. User scope is hard-coded to `~/.claude`, rather than honoring
   `CLAUDE_CONFIG_DIR`.
2. Tirith rejects the existing `~/.claude` symlink for safety. The observed
   `--scope user --dry-run` therefore failed before writing anything.
3. Claude setup unconditionally calls Tirith's shell-profile installer. The
   observed project-scoped dry run said it would append a Tirith hook to
   `~/.zshrc`, which conflicts with the goal of removing shell integration.
4. Generated hook scripts must be refreshed after Tirith upgrades. Calling setup
   imperatively from Home Manager activation would create competing ownership of
   Claude settings and shell files.

A declarative integration should reuse the hook asset shipped in the exact
`config.programs.tirith.package.src` revision and invoke the corresponding
binary by absolute path. This avoids maintaining a forked hook and prevents a
repository-controlled `PATH` from substituting another executable.

## Important version and policy issue

The active Home Manager generation installs Tirith 0.3.3. Its generated
`~/.config/tirith/policy.yaml` is a symlink into the Nix store. Tirith 0.3.3
rejects that final symlink as `NotRegularFile`, so the configured
`severity_overrides` and `allowlist_rules` are currently not loaded.

A local check confirmed this: Tirith emitted the warning and reported either no
policy path or the built-in fail-closed policy. Upstream issue 195 says support
for trusted Home Manager-style user-policy symlinks was added in Tirith 0.4.0.
The latest upstream release is 0.4.0, but nixpkgs `master` still packaged 0.3.3
on the research date.

Before enabling the Claude hook, choose one of these:

- Preferably pin Tirith 0.4.0 or newer and test the actual Home Manager symlink.
- Temporarily materialize the user policy as a regular mode-0600 file during
  activation instead of using `xdg.configFile` for that file.

Using `TIRITH_POLICY_ROOT` with a generated store directory also bypasses the
symlink problem, but it has higher policy-discovery priority and can suppress
project policy discovery. It is therefore not the preferred workaround.

## Warning behavior must be explicit

Tirith's v0.4.0 Claude guide says warnings are denied by default, but both the
v0.3.3 and v0.4.0 shipped hook scripts default
`TIRITH_HOOK_WARN_ACTION` to `allow`. The implementation should set the value
explicitly:

- `allow`: block Tirith block findings, but let warning findings proceed with
  context. This is the lower-friction choice.
- `deny`: block both warnings and block findings. This is stricter, especially
  useful with `cc --dangerously-skip-permissions`, but may interrupt more work.

`TIRITH_FAIL_OPEN` should remain unset so adapter failures deny the Bash call.

## Options compared

- **User `PreToolUse` hook:** Covers all local sessions using the normal Claude
  config, including subagents. It has the best coverage and is independent of
  shell startup, but needs a careful, secret-safe merge into mutable
  `settings.json`.
- **`--settings` from the existing `claude` function:** Covers only sessions
  started through that function. It is fully declarative, easy to roll back,
  and does not touch existing settings. Direct binary, GUI, IDE, scripts, and
  other-shell launches can bypass it.
- **Project `.claude/settings.json`:** Easy and shareable, but protects only one
  repository and depends on project trust.
- **MCP only:** Adds explicit scan tools, but is advisory and does not gate
  built-in Bash calls.
- **Claude plugin:** Bundles the hook and support files, but adds lifecycle and
  supply-chain complexity without a clear benefit here.
- **Tirith shell integration:** Protects human input and paste in interactive
  shells, but causes the daily-shell behavior this change is intended to remove
  and does not reliably cover non-interactive agent execution.

## Security boundaries

- A Claude hook is a pre-execution command-string gate, not a runtime sandbox.
  It cannot fully analyze behavior hidden in an existing script, an interpreter,
  or another tool with process-execution ability.
- Keep Claude sandboxing, minimum credentials, and operating-system permissions;
  Tirith is an additional control, not the sole boundary.
- A user-level hook can still be disabled by the same user through alternate
  settings, safe mode, or a different config directory. Organization-enforced
  managed settings are required if the user account itself is considered
  adversarial.
- Hook subprocesses inherit Claude's environment. A wrapper should remove
  credentials that Tirith does not need and must never copy the existing
  secret-bearing Claude settings into a Nix derivation or build log.
- Avoid project-scoped installation as a workaround for trust. The current `cc`
  function marks the working directory trusted before launching dangerous mode;
  untrusted repository hooks are a separate risk that should not be expanded.

## Verification required for implementation

1. Start a fresh Zsh and confirm Tirith widgets and `tirith init` are absent.
2. Confirm a normal terminal command is not scanned.
3. Confirm safe Claude `Bash` calls proceed.
4. Confirm a harmless test string shaped like a blocked command is denied before
   execution in normal, headless, `cc`, and subagent flows.
5. Confirm policy overrides are actually loaded and no `NotRegularFile` warning
   remains.
6. Simulate missing Tirith, malformed input, and an internal timeout; each must
   produce an explicit Claude deny unless fail-open was deliberately selected.
7. Confirm existing `SessionStart` and `PreCompact` hooks still run.
8. If using a `--settings` overlay, verify every real Claude Code launch path
   goes through the wrapper.

## Primary sources

- Tirith Claude integration guide at release 0.4.0:
  <https://github.com/sheeki03/tirith/blob/37dfb0f4372496f5c7336d7dad9c165dd92524a1/mcp/clients/claude-code.md>
- Tirith Claude setup implementation, including hard-coded scope paths and shell
  profile installation:
  <https://github.com/sheeki03/tirith/blob/37dfb0f4372496f5c7336d7dad9c165dd92524a1/crates/tirith/src/cli/setup/tools.rs#L403-L496>
- Tirith v0.4.0 hook implementation:
  <https://github.com/sheeki03/tirith/blob/37dfb0f4372496f5c7336d7dad9c165dd92524a1/crates/tirith/assets/hooks/tirith-check.py>
- Tirith limitation statement for shell hooks, agent hooks, and MCP:
  <https://github.com/sheeki03/tirith/blob/37dfb0f4372496f5c7336d7dad9c165dd92524a1/README.md#known-limitations>
- Tirith issue 195, Home Manager policy symlink support fixed in 0.4.0:
  <https://github.com/sheeki03/tirith/issues/195>
- Claude Code hook reference:
  <https://code.claude.com/docs/en/hooks>
- Claude Code settings scopes, precedence, and `--settings` behavior:
  <https://code.claude.com/docs/en/settings>
- Pinned Home Manager Tirith module at revision
  `99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11`:
  <https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/programs/tirith.nix>
