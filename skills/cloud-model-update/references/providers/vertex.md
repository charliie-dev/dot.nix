# Google Vertex AI (Google Cloud's Agent Platform)

Vertex serves Claude as a partner model and other publishers' models through Model Garden. Which
families and versions a project can call varies by publisher, region, multi-region (`us`, `eu`),
and the `global` endpoint; resolve it from Model Garden and current Google documentation on every
run, never from a model name. Claude Code's docs still label this provider "Google Vertex AI" in
its login wizard.

Read the project and region the user already uses from existing configuration first
(`ANTHROPIC_VERTEX_PROJECT_ID` and `CLOUD_ML_REGION`; the Claude Code client reference names their
source). Pass `--project` explicitly to `gcloud` commands and verify their shape with
`gcloud <group> --help`.

## gcloud in this setup

- **Run `gcloud` outside the Bash sandbox.** Inside it, `gcloud` fails at import with
  `PermissionError`: its bundled `requests` loads certifi's `cacert.pem`, which the sandbox's
  `**/*.pem` read deny blocks (`lib/third_party/requests/adapters.py`,
  `load_verify_locations(DEFAULT_CA_BUNDLE_PATH)`, gcloud 588.0.0). Read-only queries are ordinary
  reads; request the unsandboxed run through the permission gate.
- **Close stdin.** Run every `gcloud` command with `</dev/null`. A missing API or component makes
  `gcloud` prompt to enable or install it; with stdin closed the prompt ends the command instead of
  changing anything. `--quiet` accepts the prompt's default, which installs components, so keep
  it off.
- **Two identities.** The `gcloud` CLI account (its own credential store) and the client's
  Application Default Credentials (`GOOGLE_APPLICATION_CREDENTIALS`), which inference uses, are
  separate. A CLI reauthentication prompt leaves inference auth undecided; the skill's step 5
  inference test decides it. A query that must run as the client's identity reads the ADC
  credential file, which is user-run under the shared rules: hand the user the full command with
  `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE="$GOOGLE_APPLICATION_CREDENTIALS"` set for it and read
  back only the redacted result. That variable is the hidden `auth/credential_file_override`
  property: Google's public `gcloud config set` reference omits it (unverified in docs); the
  installed gcloud 588.0.0 source defines it (`lib/googlecloudsdk/core/properties.py:1544`) and
  loads it in place of the active account (`lib/googlecloudsdk/core/credentials/store.py:956`).

## Availability

- The Agent Platform API must be enabled for the project (`gcloud services list --enabled
  --project "$PROJECT"` shows `aiplatform.googleapis.com`).
- Model access is granted per publisher model in Model Garden: enabling a Claude model accepts its
  terms once per project and needs `roles/consumerprocurement.entitlementManager`
  ([partner models][partner]). A catalog listing (`gcloud ai model-garden models list`) shows the
  model whether or not it is enabled, and no documented API reports the enablement state. Use
  these signals, strongest first:
  1. A successful step 5 inference through the client.
  2. The model's console card without an **Enable** button (user check).
  3. The [count-tokens endpoint][count-tokens], documented as free ("There is no cost for using
     the `count-tokens` endpoint"): `POST https://aiplatform.googleapis.com/v1/projects/$PROJECT/locations/global/publishers/anthropic/models/count-tokens:rawPredict`
     with body `{"model": "<model id without @version>", "messages": [...]}` (regions `global`,
     `us`, `eu`, `asia-southeast1`). It needs a Google OAuth access token, so the user runs it;
     whether it rejects a model that is not enabled is unverified.

  The Cloud Commerce Consumer Procurement API lists Marketplace orders per billing account, but
  Google's docs do not tie Model Garden enablement to those orders; treat it as unverified.
  Record the model's supported locations and whether it supports the `global` endpoint.
- Invocation needs `aiplatform.endpoints.predict` (`roles/aiplatform.user` carries it).
- Quota is per model and region. Read it through the Cloud Quotas API before reporting
  deployability, filtering the output for the model and region:
  `gcloud quotas info list --service=aiplatform.googleapis.com --project="$PROJECT"`. The command
  is GA in the installed gcloud 588.0.0 (`lib/surface/quotas/info/list.py`) and documented as
  [`gcloud beta quotas info list`](https://cloud.google.com/sdk/gcloud/reference/beta/quotas/info/list).
  It needs `cloudquotas.googleapis.com` enabled on the project (the call fails without it).
  `dp-vertex-ai` has it enabled since 2026-10-11. Enabling it on another project is a cloud change
  that needs the user's authorization; the API itself is [free of charge][quotas-pricing].

  Quotas are keyed by a `base_model` dimension. Older Claude versions have their own entry (for
  example `anthropic-claude-haiku-4-5`); newer ones may appear only under the family entry (for
  example `anthropic-claude-haiku`). When the target version has no entry of its own, report the
  family entry's limits and label the mapping inferred. The command returns limits only: report
  current usage as unverified.

Mark any dimension you cannot read with the user's existing credentials unverified rather than
inferring it from a successful catalog listing.

## Provisioning

Partner models such as Claude are serverless: enabling access in Model Garden is the provisioning
step, and it is an operator action in the console or through the publisher's request flow. Models
that need a dedicated endpoint deployment require explicit authorization for the deployment,
machine type, and cost. Re-read the resulting state before registering a client.

## Endpoint facts for the client step

- **Claude Code + Claude:** native support through `CLAUDE_CODE_USE_VERTEX`; the client reference
  covers it. Model IDs are Vertex IDs (some carry an `@date` suffix).
- **Grok Build:** its backends speak OpenAI Chat Completions, OpenAI Responses, or Anthropic
  Messages against a `base_url`. Confirm from current Google documentation that the target model
  is served on an endpoint matching one of those shapes (Vertex's OpenAI-compatible endpoint
  covers some publishers). Claude on Vertex is invoked per model through publisher `rawPredict`
  paths; if no endpoint matches a Grok Build backend, report the pairing unsupported, or propose a
  gateway as a separate change needing approval.
- Vertex authenticates with short-lived Google OAuth access tokens from Application Default
  Credentials. A Grok Build `auth_provider` command can mint them per request; configuring it is
  a config edit, while creating or repairing ADC is user-run.

[partner]: https://docs.cloud.google.com/vertex-ai/generative-ai/docs/partner-models/use-partner-models
[count-tokens]: https://docs.cloud.google.com/vertex-ai/generative-ai/docs/partner-models/claude/count-tokens
[quotas-pricing]: https://cloud.google.com/quotas/pricing
