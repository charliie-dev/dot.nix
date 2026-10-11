# Claude Code

**Memory topic:** [claude-code-configuration](~/.config/grok/memory-v2/workspaces/claude-0f786f47/topics/claude-code-configuration.md)
holds configuration intentions and historical regression references.

**Baseline file:** `~/.config/claude/agent-update-baseline.json`. The Bash sandbox cannot write
`~/.config/claude`; update it with the Edit tool (expect an approval prompt).

## Scope

- Configuration directory: `~/.config/claude` (`~/.claude` symlinks to it). The launch command
  goes through Home Manager zsh wrappers such as `cc` and `cct` in
  `~/.config/home-manager/modules/apps/zsh/`; resolve them before naming the effective launch.
- Determine which user, project/local, managed, and explicitly supplied (`--settings`) settings
  apply and their precedence. Distinguish active files from share or backup copies.

## Sources for step 2

Fetch the raw Markdown (both hosts are in the Claude Code sandbox network allowlist):

- [Settings reference](https://code.claude.com/docs/en/settings-reference.md): the per-key
  reference. `settings.md` covers settings files and precedence.
- [Environment variables](https://code.claude.com/docs/en/env-vars.md).
- [CHANGELOG](https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md): one
  `## <version>` section per release, newest first.

## Surfaces to scan in step 3

Configured providers and model pins, hook events and handler fields, sandbox rules, statusline
fields, permission rules, and installed plugins.

## Integration checks for step 4

- **Models and session behavior:** model aliases and overrides, permission mode, compaction,
  memory, and task-tool availability. Check effective behavior rather than assuming a configured
  value wins over every other source.
- **Hooks:** registration, script paths, event input/output, and an isolated exercise of the
  affected event. Syntax checks alone do not prove handoff or other hook output works. Select
  test events without unrelated side effects.
- **Sandbox:** distinguish missing narrow permissions from path handling, cache, network, or tool
  failures. Use non-secret fixtures to test both the intended allowance and the protections that
  must remain; investigate causes before proposing broader access.
- **Statusline:** input-field changes, current directory/worktree selection, refresh behavior,
  and parsing edge cases. Reuse maintained regression tests.
- **Skills/plugins:** discovery, duplicate installations, and changed loading behavior. Preserve
  intentional installation choices; test affected capabilities rather than treating file presence
  as proof of compatibility.

## Validation for step 5

Use supported, configuration-only checks (JSON parsing, the maintained tests under
`~/.config/claude/tests/`) and follow the shared authentication policy when choosing
diagnostics.

`test_statusline.py` and `test_subagent_statusline.py` run inside the Bash sandbox.
`test_permissions.py` runs a nested `claude` against a loopback mock API with secret-named
fixtures (`.env`, `*.pem`, `id_rsa`), so it runs outside the sandbox through the permission gate:
`python3 -B -m unittest test_permissions` from `~/.config/claude/tests`. Inside the sandbox it
reports one skipped test (loopback bind denied); a skip is not a pass.

## Memory for step 6

Update the memory topic with the Edit tool. The Bash sandbox cannot write under
`~/.config/grok` unless it is the working directory, and the Edit tool follows permission rules
instead, so expect an approval prompt there. Edit only files under `topics/`; Grok regenerates
`MEMORY.md`.
