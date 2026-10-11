# Claude family

**Clients:** both.

- **Claude Code** consumes Claude natively through Amazon Bedrock (Invoke API or Mantle),
  Google Vertex AI, Microsoft Foundry, Claude Platform on AWS, or an LLM gateway. The client
  reference covers the provider switches and pins.
- **Grok Build** consumes Claude through the Anthropic Messages backend
  (`api_backend = "messages"`) with an `anthropic-version` header in `extra_headers`, on any
  endpoint that serves `/v1/messages` (Bedrock Runtime's `/anthropic/v1` path in this setup).

**Model IDs:** each provider has its own ID form: Bedrock inference-profile IDs with a routing
prefix (`global.`, `us.`, `eu.`, `apac.`), Mantle IDs with an `anthropic.` prefix and no version
suffix, Vertex IDs (some with an `@date` suffix), and Foundry deployment names. Resolve the ID
from the provider catalog and [Claude's models overview](https://platform.claude.com/docs/en/about-claude/models/overview);
never derive one provider's ID from another's.

**Limits and controls:** read context window, output limit, and effort support from
[Claude Code model configuration](https://code.claude.com/docs/en/model-config) and the model
overview.

From Claude Code 2.1.287, Fable models, Sonnet 5 and later, and Opus 4.7 and later run with a 1M
context window by default on Bedrock (Invoke API and Mantle), Vertex, and Foundry, with no `[1m]`
suffix. Opus 4.6 and Sonnet 4.6 reach 1M through their `[1m]` variant. On Foundry the default
applies only when Claude Code can match the deployment name to a model (name the deployment with
the model ID or map it in `modelOverrides`). Source: [Bedrock: 1M token context window][bedrock-1m];
the Vertex and Foundry setup pages carry the same section.

Grok Build's existing Claude entries set `max_completion_tokens`; keep that pattern and resolve
the value for the new model.

**Client minimum version:** a new Claude model can require a minimum Claude Code version.
Compare it with the installed version before pinning the model there.

[bedrock-1m]: https://code.claude.com/docs/en/amazon-bedrock#1m-token-context-window
