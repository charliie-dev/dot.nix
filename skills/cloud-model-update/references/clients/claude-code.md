# Claude Code client

Claude Code consumes Claude-family models only. Read the provider's current setup page before
editing: [Amazon Bedrock](https://code.claude.com/docs/en/amazon-bedrock),
[Google Vertex AI](https://code.claude.com/docs/en/google-vertex-ai),
[Microsoft Foundry](https://code.claude.com/docs/en/microsoft-foundry), and
[model configuration](https://code.claude.com/docs/en/model-config) for pins, `modelOverrides`,
`availableModels`, and context-window rules. The [Claude Code memory topic][cc-memory] records
this user's configuration intentions.

## Find the maintained source

Provider routes are **launch paths** in Home Manager (paths below are relative to
`~/.config/home-manager/`). The `env` block of `~/.config/claude/settings.json` is the
first-party default path: every session loads it, and its values overwrite the same variables
exported by the shell ([how `env` interacts with your shell][env-shell]). Provider switches
therefore live in the launch paths, so each route changes only the sessions started through it:

- **Selection:** `cct` (alias in `modules/apps/zsh/aliases.nix`) runs `claude-code-toggle` in
  `modules/apps/zsh/functions.nix`, which exports exactly one `CLAUDE_CODE_USE_*` switch in the
  current shell (`team` exports none). The `claude` function there, which `cc` calls, sends
  Bedrock sessions to the `claude-bedrock` launcher.
- **Bedrock:** the `bedrock-api-key` integration's launcher passes a `--settings` overlay that
  owns the Bedrock pins; change it through the
  [Bedrock integration change](../providers/bedrock.md#integration-change).
- **Vertex:** Claude Code reads `ANTHROPIC_VERTEX_PROJECT_ID` and `CLOUD_ML_REGION` from the
  user settings `env`, so every route shares them. `modules/core.nix` exports the same two values
  as session variables for pi's Vertex extension only; change both places together so they stay
  equal.

Add a new provider route as a launch path in those sources: a `claude-code-toggle` backend, plus
a launcher that passes its own `--settings` overlay when the route needs its own pins (command-line
settings take precedence over user settings).

Before changing a pin, list the routes that share it. `ANTHROPIC_DEFAULT_*` in user settings `env`
apply to first-party sessions and to every route without an overlay of its own (Vertex and
Foundry today). A pin that must differ for one provider belongs in that route's overlay.

## Register

| Provider | Switch (set by the launch path) | Pin |
|---|---|---|
| Bedrock (Invoke API) | `CLAUDE_CODE_USE_BEDROCK=1`, region from `AWS_REGION` | Inference-profile IDs |
| Bedrock (Mantle) | `CLAUDE_CODE_USE_MANTLE=1` | `anthropic.`-prefixed Mantle IDs; list them in `availableModels` to surface them in `/model` |
| Vertex | `CLAUDE_CODE_USE_VERTEX=1`, `ANTHROPIC_VERTEX_PROJECT_ID`, `CLOUD_ML_REGION` | Vertex IDs; a `VERTEX_REGION_CLAUDE_*` override for models off the `global` endpoint |
| Foundry | `CLAUDE_CODE_USE_FOUNDRY=1`, `ANTHROPIC_FOUNDRY_RESOURCE` | Deployment names |

Pin aliases with `ANTHROPIC_DEFAULT_{FABLE,OPUS,SONNET,HAIKU}_MODEL` (and the matching `_NAME`
display variables this setup uses). Use `modelOverrides` to map several versions of one tier to
distinct profiles or deployments, or to tell Claude Code which model a non-standard deployment
name serves. Credentials stay in their existing mechanism (credential chain, bearer token
variable, ADC, Entra ID); reference them by name.

## Validate loading and test the connection

Parse each edited JSON file or overlay with `jq`. Then run one headless request through the
route's launch path: the switch its `claude-code-toggle` backend exports (for example
`CLAUDE_CODE_USE_VERTEX=1`) or its launcher. Bedrock routes use the integration's verifier
instead.

```bash
CLAUDE_CODE_USE_VERTEX=1 claude -p --model "$MODEL" --max-budget-usd 0.05 --output-format json \
  "Reply with OK. Use no tools." | jq '{is_error, result, models: (.modelUsage | keys)}'
```

- Run it outside the Bash sandbox: the nested `claude` writes its configuration directory.
  Request the unsandboxed run through the permission gate.
- It is a full session, so this setup's SessionStart and Stop hooks fire; expect their side
  effects.

The test passes when `is_error` is `false`, `result` is the reply, and `modelUsage` has an entry
for the intended model ID. Compare IDs after stripping a `[1m]` suffix: a Vertex run of
`claude-haiku-5-5` on 2.1.296 keyed `modelUsage` by the bare ID, and other providers' key format
is not yet observed. A different main model in `modelUsage` with the intended ID absent, or
a startup model-check fallback notice on stderr, means the pinned model is not invocable: record
the run as failed. The user checks the interactive views (`/status`, the `/model` picker)
themselves.

[cc-memory]: ~/.config/grok/memory-v2/workspaces/claude-0f786f47/topics/claude-code-configuration.md
[env-shell]: https://code.claude.com/docs/en/settings-reference#how-env-values-interact-with-your-shell
