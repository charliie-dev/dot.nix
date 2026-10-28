---
name: handoff
description: "Hand the current conversation off to another agent session: write a handoff document, then optionally deliver it to an agent in a neighboring Rex pane (Herdr as fallback), either an existing session or a newly started Claude Code / Grok Build agent. Use when the user asks to hand off, pass, or transfer the current work, including mid-sentence mentions like \"/handoff to the right pane\"."
argument-hint: "Where the work goes and what the next session focuses on, e.g. \"to right pane with a new cc session\""
---

# Handoff

Hand the current work to a fresh agent so it can continue without this conversation's context.

## 1. Write the handoff document

Save it under the OS temporary directory (`$TMPDIR`, else `/tmp`), never inside the workspace. Use `mktemp` so the path is unique, and quote the absolute path it returns everywhere afterwards.

The document contains:

- **Goal and current state**: what the work is for, what is done, what is in progress, what is blocked.
- **Next steps**: ordered, concrete, with exact commands where they matter.
- **Decisions and constraints**: what the user already decided or approved, and what still needs the user. The next agent must not treat anything outside the approved scope as authorized.
- **References**: paths, URLs, branches, PRs, issues, specs and commits. Reference existing artifacts by path or URL instead of copying their content.
- **Suggested skills**: which skills the next agent should load, by name.

If the user passed arguments, treat them as the destination and focus of the next session and tailor the document to that.

Redact secrets and personal data: API keys, tokens, passwords, credential file contents, and personally identifiable information.

## 2. Pick the destination

Read the destination from the user's request:

| Request | Delivery |
|---|---|
| No destination, or "just write it" | Stop after step 1 and report the file path. |
| A pane that already runs an agent ("right pane", "the cc session on the right") | Prompt that agent (step 3a). |
| A new session ("new cc session", "another grok session") | Start an agent in a pane, then prompt it (step 3b). |

When the target pane is ambiguous, or more than one agent matches, ask the user instead of guessing.

## 3. Deliver

Only when a pane destination was requested. Deliver through Rex when `REX_SESSION` is set and `rex whoami --json` succeeds. Otherwise, inside Herdr, follow [references/herdr.md](references/herdr.md). With neither, report the handoff file path and tell the user no multiplexer is available.

The prompt to send is short and points at the file:

```text
Read <absolute handoff path> and continue the work it describes. The user already approved only what the document lists as approved. Reply to the user in <the user's language>.
```

`scripts/rex-prompt.lua` in this skill's directory delivers it: the script resolves the pane, refuses an agent that is `working` or `blocked`, types the prompt, and watches the agent's program status until the agent starts. Run it with `rex do` and read the JSON it prints:

| Argument | Meaning |
|---|---|
| `direction=left\|right\|up\|down` | The pane sharing that edge with this one. |
| `block=<id>` | A pane named by the user, found with `rex block ls -s "$REX_SESSION" --json`. |
| `text=<prompt>` | The prompt above. |
| `launch=<command>` | Start an agent in a shell pane first: `claude` for Claude Code ("cc"), `grok` for Grok Build. Default to the same kind as this agent. |

### 3a. Existing agent in a neighboring pane

```bash
rex do "<skill dir>/scripts/rex-prompt.lua" -s "$REX_SESSION" -b "$REX_BLOCK" --json \
  direction=right text="<prompt>"
```

### 3b. New agent

If the requested pane already exists and is an idle shell at its prompt, pass it with `direction=` or `block=`. Otherwise create a sibling pane without stealing focus, splitting toward the requested direction (default: right for a wide pane, down for a tall one), and use `.block_ids[0]` from its JSON:

```bash
rex split -s "$REX_SESSION" -b "$REX_BLOCK" --split=right -c "$PWD" --focus=false --label <name> --json
rex do "<skill dir>/scripts/rex-prompt.lua" -s "$REX_SESSION" -b "$REX_BLOCK" --json \
  block=<new-block-id> launch=<claude|grok> text="<prompt>"
```

The agent starts by being typed into the pane's shell (`launch=`), which runs the shell functions that wrap `claude` and `grok` with their credentials. The bare binary that `rex split -- grok` runs skips them and fails to authenticate.

## 4. Report

Tell the user the handoff file path, where it was delivered (pane ID, label and agent app), and whether the receiving agent started working:

- `ok: true` with `state: working`: started and still running. `done` or `idle`: it already finished its first turn.
- `ok: false`: `reason` says why. Nothing was sent when the pane was missing, ambiguous, held no agent, or the agent was busy.

On `blocked`, `error`, or a stall, read the pane before re-sending anything; an unconfirmed start does not prove the prompt was lost:

```bash
rex capture -s "$REX_SESSION" -b <block> --trim --unwrap | tail -n 40
```
