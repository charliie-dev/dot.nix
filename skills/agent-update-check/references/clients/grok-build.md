# Grok Build

**Memory topic:** [grok-build](~/.config/grok/memory-v2/workspaces/grok-e6c6eade/topics/grok-build.md)
holds personal preferences, integration locations, and known regression targets.

**Baseline file:** `~/.config/grok/agent-update-baseline.json` (inside the Grok home).

## Scope

- Resolve the Grok home from `GROK_HOME`, falling back to `~/.grok` (this setup:
  `~/.config/grok`). Confirm the installed version and the configuration sources actually loaded
  (`grok inspect --json`).
- The baseline comes from the baseline file above. When it is missing and session history shows
  an earlier audit, record that version as an unverified baseline; ask only if an unknown baseline
  blocks the requested comparison.

## Sources for step 2

Read the installed `CHANGELOG.md` and the relevant files under `docs/user-guide/` in the Grok
home, checking which release they describe; `26-config-reference.md` is the key reference.
Obtain the old configuration reference from matching official sources or a complete historical
capture; a conversation summary alone is not a full reference. Resolve documentation/loader
disagreements before recommending deletion. Check actual definitions and provider endpoints when
documentation is insufficient, rather than relying on similar names.

## Surfaces to scan in step 3

Custom models (repeated per-model fields a `[models]` global default or a shared
`[model_providers.<id>]` block could own), auth providers, Claude/Cursor compatibility cells,
hooks, memory, storage, dashboard, and UI settings.

## Integration checks for step 4

- **Custom models:** inspect changed effort and reasoning-summary controls; apply saved
  preferences only where the configured provider and endpoint support them. Keep Mantle and
  Bedrock Runtime evidence separate.
- **Azure streaming and gateway:** when this setup is present, retest the keepalive regression
  recorded in memory. Check native Grok and the gateway path separately so a gateway workaround
  cannot be mistaken for a native fix. Use existing regression fixtures and an isolated test
  instance as needed; follow the shared-service constraints in memory. If live testing is blocked,
  distinguish fixture coverage from unverified provider behavior.
- **Herdr and hooks:** when installed, check whether changed dock/status output affects
  agent-state detection and whether imported versus native hooks duplicate each other. Locate the
  integration's maintained source before proposing an adjustment; inspecting configuration does
  not require controlling live panes.
- **Skills, plugins, and language tooling:** check changed discovery rules, inherited sources,
  duplicate installations, and affected language-server file matching. Use the saved installation
  preference instead of repeating an old removal or reinstalling an already-correct setup.
- **Memory, privacy, storage, and optional features:** explain relevant changes in behavior,
  retention, dependencies, and privacy implications. A memory migration is applicable only if
  legacy data remains and the user selects it; preserve source data and verify the destination
  before any cleanup.

## Validation for step 5

Validate TOML and the current CLI's native configuration loading with `grok inspect --json`;
inspect its actual warning fields and keep secrets out of reports. Use existing authentication
for ordinary authorized tests; login, credential renewal, credential-file access, and
authentication repair remain user-run.
