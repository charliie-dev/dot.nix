---
name: handoff
description: "Hand the current conversation off to another agent session: write a handoff document, then optionally deliver it to an agent in a neighboring Herdr pane (existing session or a newly started Claude Code / Grok Build agent). Use when the user asks to hand off, pass, or transfer the current work, including mid-sentence mentions like \"/handoff to the right herdr pane\"."
argument-hint: "Where the work goes and what the next session focuses on, e.g. \"to right herdr pane with a new cc session\""
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
| A Herdr pane that already runs an agent ("right pane", "the cc session on the right") | Prompt that agent (step 3a). |
| A new session ("new cc session", "another grok session") | Start an agent in a pane, then prompt it (step 3b). |

When the target pane is ambiguous, or more than one agent matches, ask the user instead of guessing.

## 3. Deliver through Herdr

Only when a Herdr destination was requested. First confirm this agent runs inside Herdr:

```bash
test "${HERDR_ENV:-}" = 1
```

If it fails, report the handoff file path and tell the user you are not inside Herdr. If `herdr --skill` output is not already in context, run it and follow it; the installed binary is the authority for command syntax. Parse IDs from JSON responses; never derive them from examples.

The prompt to send is short and points at the file:

```text
Read <absolute handoff path> and continue the work it describes. The user already approved only what the document lists as approved. Reply to the user in <the user's language>.
```

### 3a. Existing agent in a neighboring pane

```bash
herdr pane layout --pane "$HERDR_PANE_ID"
herdr agent list
```

Pick the agent in the requested direction relative to the caller pane. If its state is `blocked` or `working`, tell the user and do not prompt it. Otherwise:

```bash
herdr agent prompt <agent-name-or-pane-id> "<prompt>" --wait --timeout 120000
```

### 3b. New agent

Use the requested kind: `claude` for Claude Code ("cc"), `grok` for Grok Build. Default to the same kind as this agent.

If the requested pane already exists and is an idle shell at its prompt, use it. Otherwise create a sibling pane without stealing focus, splitting toward the requested direction (default: right for a wide pane, down for a tall one):

```bash
herdr pane split --current --direction right --cwd "$PWD" --no-focus
```

Start the agent with a short descriptive name, then prompt it:

```bash
herdr agent start <name> --kind <claude|grok> --pane <new-pane-id>
herdr agent prompt <name> "<prompt>" --wait --timeout 120000
```

## 4. Report

Tell the user the handoff file path, where it was delivered (pane ID and agent name), and whether the receiving agent started working. A timeout or stall does not prove the prompt was lost: read the pane with `herdr agent read` before re-sending anything.
