# Grok family

**Clients:** Grok Build only. Claude Code consumes Claude models only; a Grok model requested for
Claude Code ends the run with that finding.

**Sources:**

- **xAI direct:** Grok Build ships these as built-in models; they need no `[model.*]` entry, only
  sign-in or an `XAI_API_KEY`. An override block changes individual fields of a built-in model.
- **Azure (Foundry):** served through the account's OpenAI-compatible path; this setup reaches it
  through the local gateway with `api_backend = "responses"` and
  `reasoning_summary = "concise"`.
- **Amazon Bedrock:** served on the OpenAI-compatible path (`/openai/v1` on Bedrock Runtime, or
  Mantle) with `api_backend = "responses"` and `reasoning_summary = "none"`.

**Reasoning effort:** whether a Grok release accepts an effort parameter, and which values, varies
by release; take it from xAI's current model documentation or the provider's model card. Declare
`reasoning_efforts` tables only for values the endpoint accepts.

**Limits:** resolve `context_window` per provider: a cloud provider can serve a smaller window
than xAI direct. An entry without it falls back to the client's 200,000-token default.
