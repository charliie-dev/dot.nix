# Deliver through Herdr

Use this path only when `REX_SESSION` is unset and this agent runs inside Herdr:

```bash
test "${HERDR_ENV:-}" = 1
```

If `herdr --skill` output is not already in context, run it and follow it; the installed binary is the authority for command syntax. Parse IDs from JSON responses; never derive them from examples.

## Existing agent in a neighboring pane

```bash
herdr pane layout --pane "$HERDR_PANE_ID"
herdr agent list
```

Pick the agent in the requested direction relative to the caller pane. If its state is `blocked` or `working`, tell the user and do not prompt it. Otherwise:

```bash
herdr agent prompt <agent-name-or-pane-id> "<prompt>" --wait --timeout 120000
```

## New agent

If the requested pane already exists and is an idle shell at its prompt, use it. Otherwise create a sibling pane without stealing focus, splitting toward the requested direction (default: right for a wide pane, down for a tall one):

```bash
herdr pane split --current --direction right --cwd "$PWD" --no-focus
```

Start the agent with a short descriptive name, then prompt it:

```bash
herdr agent start <name> --kind <claude|grok> --pane <new-pane-id>
herdr agent prompt <name> "<prompt>" --wait --timeout 120000
```

## Checking a stalled delivery

A timeout or stall does not prove the prompt was lost: read the pane with `herdr agent read` before re-sending anything.
