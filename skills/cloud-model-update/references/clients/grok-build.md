# Grok Build client

Resolve Grok home from `$GROK_HOME`, falling back to `~/.grok`, and follow config symlinks. Read
the installed `docs/user-guide/11-custom-models.md` (model fields, backends, credential
resolution, auth providers) and `05-configuration.md`; they describe the installed version and
outrank memory. The [Grok Build memory topic][gb-memory] records this setup's gateway and
regression history.

## Register

Add one `[model.<alias>]` block per model in `config.toml`; quote table keys containing dots
(`[model."bedrock-opus-5.5"]`). Keep nested `reasoning_efforts` and `extra_headers` tables under
the new alias. Preserve `[models].default` unless the user asks to change it.

| Field | Source |
|---|---|
| `model` | The wire ID: Azure deployment name, Bedrock inference-profile ID, or provider model ID |
| `name` | A display name naming provider, model, and region where several regions exist |
| `base_url` | The verified endpoint; reuse a sibling entry's value only when the endpoint is identical |
| `api_backend`, `reasoning_summary`, `extra_headers` | The family reference for this provider |
| Credential | The existing reference for the provider: `env_key` naming the variable, or `auth_provider` naming an `[auth_provider.<id>]` block |
| `context_window`, `max_completion_tokens`, `reasoning_efforts` | The family reference's limits rules |

Bedrock entries authenticate through the Bedrock integration's auth provider; before editing one,
check that integration's Grok consumers named in the Bedrock provider reference, since a staged
configuration step may own those entries.

## Validate loading

```bash
grok inspect --json | jq '.configWarnings'
grok models
```

Compare warnings with the pre-edit run so only new ones count as regressions; confirm the alias
appears in `grok models` without credential output.

## Test the connection

```bash
grok -m "$ALIAS" -p "Reply with OK. Use no tools."
```

One headless request through the configured alias exercises endpoint, backend, credential
provider, and model ID together. Inspect the reply and stop on authentication errors. If the
request retries on connection errors, check that a local gateway the entry points at is running
before diagnosing the model.

[gb-memory]: ~/.config/grok/memory-v2/workspaces/grok-e6c6eade/topics/grok-build.md
