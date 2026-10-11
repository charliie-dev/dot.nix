# Amazon Bedrock

Bedrock serves Claude, GPT, and Grok families. This user's Bedrock access runs through a
maintained Home Manager integration (`conf.d/bedrock-api-key`) that both clients share: Claude
Code launches through its launcher and overlay, and Grok Build mints bearer tokens through the
`bedrock-doppler` auth provider. A model change therefore lands in that integration's pins,
overlay, verifier, and IAM contract, not only in a client config.

Read [sources and operation boundaries](bedrock/sources.md) first: it names every maintained
owner and the operator boundary. Every **operator** step there is a handoff for the user to run in
a separate shell; real preflight, staging, AWS commands, activation, and model launches are
operator work.

## Availability

Resolve the official **foundation model ID**, the **inference profile** (regional or `global.`
routing), the service tier, and the client's minimum supported version from current AWS and
client documentation. Availability, agreement offers, and pricing follow
[operator workflow §4](bedrock/operator-workflow.md#4-availability-offers-and-pricing): readiness
requires `AUTHORIZED` and `AVAILABLE` on each applicable status for the queried identity, account,
and region.

## Endpoint facts for the client step

Read the endpoint shape from the existing client entries for the same region before choosing one:

| Family | Grok Build backend | Path on `bedrock-runtime.<region>.amazonaws.com` |
|---|---|---|
| Claude | `messages` (with `anthropic-version` header) | `/anthropic/v1` |
| GPT, Grok | `responses` with `reasoning_summary = "none"` | `/openai/v1` |

The Mantle gateway (`bedrock-mantle.<region>.api.aws`) is a separate endpoint; keep Mantle and
Bedrock Runtime evidence separate. The inference-profile ID (for example a `global.` prefixed ID)
is the wire model string.

## Integration change

Apply the change to the existing integration, keeping each affected caller accounted for through
verification. The action class from the skill's step 1 decides how far these steps go.

1. **Map the change.** Map current and proposed values across the launcher, generated overlay,
   verifier, IAM policy, and every consumer of the old model, including the Grok consumers in
   `grok.py`, `grok_config.py`, and `grok_policy.py`. Track general client settings separately
   from Bedrock-specific configuration. Read the user's model-specific effort and session
   preferences; preserve unrelated settings. Establish the acceptance level: public-source
   preparation, selected live smoke tests, or a coordinated deployment.
2. **Check native-client compatibility.** Check the installed client's platform and the model's
   documented version requirement. Routine upgrades use the installed executable without
   per-version admission reviews. Read [native-client review](bedrock/native-client-review.md)
   only for a concrete compatibility failure or a change in launch platform, configuration
   sources, or security assumptions.
3. **Update public sources and tests.** Edit each value at its maintained owner: launcher model
   pins, overlay IDs and display names, and verifier expected IDs together. Keep legacy models
   other clients need; update diagnostic label coverage independently of strict model matching.
   Extend IAM with the current contract's exact profile/foundation pairs, invocation conditions,
   discovery, and counting resources, preserving the identity/boundary relationship and other
   model permissions. Add tests for aliases, explicit IDs, fallback and override paths, retired
   IDs, retained consumers, and response identity. Run the affected tests and format/type checks;
   for IAM edits also run the repository's duplicate-key/contract tests, CloudFormation lint, and
   pinned Guard rules, and check expanded policy and template sizes against current limits.
4. **Hand off candidate and AWS checks.** Follow [operator workflow](bedrock/operator-workflow.md):
   candidate preflight, baseline comparison, reviewed UPDATE change set, post-update policy
   verification, IAM simulation, and the model-access branch. If the deployed policy already
   covers the model, verify that baseline and skip mutation.
5. **Verify runtime paths.** Read [verification and diagnostics](bedrock/verification-and-diagnostics.md)
   before choosing live commands or interpreting output. The operator runs the maintained
   verifier for the upgraded caller and affected retained consumers; this replaces the generic
   client smoke test for clients launched through the integration.

Each step finishes at its stated checkpoint or pauses at the first failed, unapproved, or
unavailable prerequisite with one precise next step. Keep source changes, candidate build, and
activated state separately identified in the report.
