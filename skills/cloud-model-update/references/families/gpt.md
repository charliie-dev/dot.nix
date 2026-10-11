# GPT family

**Clients:** Grok Build only. Claude Code consumes Claude models only; a GPT model requested for
Claude Code ends the run with that finding.

**Protocol:** OpenAI Responses (`api_backend = "responses"`) where the endpoint serves
`/responses`; Chat Completions otherwise. Read the existing entries for the same provider and
endpoint before choosing: they record what this setup's endpoints accept.

**Reasoning summary:** Azure endpoints in this setup accept `reasoning_summary = "concise"`.
Bedrock's OpenAI-compatible paths reject `reasoning.summary`; use `"none"` there.

**Reasoning effort:** effort levels differ per model release (some add `none` or `xhigh`). Take
the supported values from the model's current documentation or deployment metadata, then declare
them as `[[model.<alias>.reasoning_efforts]]` tables with `id`, `value`, `label`, `description`,
and one `default = true`. Copying a sibling model's list establishes nothing.

**Limits:** `context_window` is the input ceiling the endpoint enforces, which can sit below the
model card's figure; prefer a measured value recorded for the same deployment, then the
deployment's metadata, then the documented figure. Set `max_completion_tokens` only when the
deployment caps output below the client default.

**Identity check:** the deployment or inference-profile ID is the wire `model`; confirm the
inference response names the intended model where the API returns one.
