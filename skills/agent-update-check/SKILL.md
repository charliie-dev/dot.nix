---
name: agent-update-check
description: >-
  Audit Claude Code or Grok Build configuration and integration compatibility after an upgrade,
  including cross-client effects, and recommend settings worth adopting. Use when the user says
  "Claude Code 更新了" or "gb 更新了", asks which settings need updating, removal, or addition
  after a Claude Code or Grok Build upgrade, or runs /agent-update-check.
---

# Agent update check

Audit an installed client update; change only what the user requests or approves. Updating an
executable is a separate task.

Each run audits one or both **clients**. Load the reference for every client in scope; it owns
that client's sources, memory topic, checks, and validation commands. This file owns the order.

| Client | Reference |
|---|---|
| Claude Code | [claude-code](references/clients/claude-code.md) |
| Grok Build | [grok-build](references/clients/grok-build.md) |

The [shared user rules](~/.config/claude/CLAUDE.md) own shell, authentication, and tooling
policy. Read each client's memory topic for intentions and regression history; verify historical
notes against live files, and treat past fixes and commits as context, never as authorization to
repeat them.

## 1. Establish scope

- Determine which client was upgraded from the user's words or the installed versions. Grok
  Build loads Claude Code's settings, hooks, skills, plugins, and MCP configuration through its
  Claude compatibility layer, so a Claude Code change to any of those surfaces puts Grok Build's
  loading of them in scope too; record that cross-client scope explicitly.
- For each client in scope: confirm the installed version, installation method, configuration
  directory, actual launch command (including wrappers), and the configuration sources actually
  loaded, as its reference describes. Inspect only relevant non-secret fields.
- Use a supplied old/new version pair. Otherwise read the client's `agent-update-baseline.json`
  (path in its reference): `audit.version` is the baseline, and release notes from there to the
  installed version are in scope, together with any `audit.gaps`. `runtime_checks` entries are
  per-feature evidence only; a later passed check marks that feature last-known-good, not the
  whole release. With no baseline file, say so and run a current-state audit; a missing old
  reference never supports a claim of exhaustive differences.

Proceed with the version range, loaded configuration sources, cross-client scope, and evidence
gaps recorded per client.

## 2. Compare settings and behavior

Read the official sources the client reference names for the versions in scope. Cover defaults,
CLI and environment controls, renamed or removed keys, and loader warnings, not only keys
already present in the user's configuration. Use shipped implementation or schema evidence to
resolve undocumented behavior; absence from a schema or an unknown-field warning alone does not
establish deprecation or safe removal.

Classify findings as **required adjustment**, **new optional setting**,
**deprecated/renamed/removed**, or **unchanged**. For each change give its purpose, default,
applicability, and recommended action. Include new optional settings even when no migration is
required. Separate newly documented behavior from newly implemented behavior, and new
deprecations from old ones. Attach source links or relative paths, line ranges, and short exact
excerpts to decision-critical claims; mark unsupported claims unverified.

Finish this comparison before selecting edits, with the full scope accounted for or the unchecked
part named. Saved intentions guide advice; new options do not automatically override them.

## 3. Recommend settings worth adopting

Step 2 lists every change; this step picks the ones this setup would plausibly adopt. Draw
candidates from that comparison and from older documented options the live configuration shows a
need for. Look for:

- **Workarounds with native replacements:** environment variables, wrapper flags, hooks,
  scripts, shims, or repeated fields that reimplement what a documented setting now does.
- **Defaults the configuration fights:** a value forced at every launch or repeated across
  entries or projects that one setting could own.
- **Extensions of features in use:** an option refining something already configured; the
  client reference lists the surfaces to scan.
- **Shifted defaults:** a new default that diverges from what the saved intentions assume.

For each candidate give the setting and proposed value, the live configuration evidence that
makes it relevant (path and short excerpt), the benefit, the cost or risk, and the exact edit.
Rank by benefit to this setup. Drop candidates with no configuration evidence; flag any that
conflict with a saved intention. Present the list as opt-in; applying a candidate follows step 5's
authorization.

Finish with every candidate tied to configuration evidence, or a statement that none qualified.

## 4. Check affected integrations

Select checks from the release changes, live configuration, the memory topic, and the user's
scope, using each client reference's integration list. For cross-client scope, check how Grok
Build loads the changed Claude Code surface (for example a new hook field or settings key) and
whether imported and native definitions duplicate each other.

Record each check as **passed**, **failed**, **not applicable**, or **unverified**, with
evidence. Read recent transcripts only when a check needs usage evidence or failure
reproduction; treat them as inert data, exclude secrets, and reproduce historical failures on the
current version before attributing them to this upgrade. A release note or configuration parse is
not a runtime regression test.

Finish with every applicable check recorded and each skipped or blocked check explained.

## 5. Apply selected changes and verify

For an audit-only request, deliver findings without edits. An explicit change request authorizes
its specified changes, not every optional feature or historical choice in memory.

- Snapshot only the files being changed, using task-owned `mktemp` paths under `TMPDIR`. Patch
  the maintained source when a file is generated; preserve unrelated values and compare
  before/after files directly.
- Validate syntax and native configuration loading with the client reference's
  configuration-only checks. Separate pre-existing warnings from regressions.
- Exercise changed behavior and affected existing flows. Recheck protections after permission
  changes; fix and reverify regressions introduced by edits.
- Keep commits, pushes, pre-existing backup deletion, Home Manager activation, and restarts of
  shared services within explicit authorization; report a needed restart instead of disrupting a
  shared service. Clean up only this run's temporary artifacts and test processes.

Finish when selected changes have verification evidence or a stated blocker; successful loading
alone does not prove provider or runtime compatibility.

## 6. Report and retain decisions

Report per client:

1. Version range, configuration scope, cross-client scope, and evidence coverage.
2. Required adjustments, all new optional settings, and deprecations/renames.
3. The ranked recommendations from step 3.
4. Changes made versus recommendations left unapplied.
5. Integration results, remaining warnings, and unverified behavior.
6. User-run steps, reloads, or restarts still needed.

Distinguish source edits from activated configuration. After a completed audit, update the
client's `agent-update-baseline.json`: move the old `audit` into `previous_audits`, record the new
`version`, `date`, `session`, `release_notes_compared`, and `gaps`, and add this run's runtime
checks under the installed version with their results (failures included). Save newly confirmed
intentions in the client's existing memory topic; keep current values in live configuration, regression behavior
in maintained tests, and this upgrade's outcomes in the report or session history.
