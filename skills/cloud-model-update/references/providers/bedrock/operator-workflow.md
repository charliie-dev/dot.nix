# Operator workflow

Use the operation boundaries and paths in [sources](sources.md). Prepare small,
ordered handoffs from the current runbook commands. For each handoff, name the
executor, approval needed, expected redacted output, and stop condition. Wait
for that checkpoint before issuing dependent operations.

## 1. Candidate build and preflight

Resolve the Home Manager host/flake selection from the current setup. Record the
candidate build manifest and compare its public launcher, overlay and verifier
paths with the active manifest. Have the operator run the integration runbook's
staging and preflight commands against that candidate.

Check the returned client version, pins, launch arguments, region,
settings/helper conflicts and startup scope. Resolve a conflict at its named
source within approved scope, then repeat the check. Candidate preparation may
precede the IAM update; live testing requires the later applicable gates.

Finish with passing candidate preflight, a matching staging manifest, and the
candidate-versus-active distinction recorded.

## 2. Baseline and reviewed IAM update

Read the infrastructure runbook's current contract and **User-run** commands.
Have the operator confirm the management identity, account, region, stack
status, Outputs, user, boundary, sole policy attachment, public policy/version,
and the other authorization invariants in that contract. Record the baseline for
a before/after comparison. Investigate unexpected state before continuing.

When the public policy changes:

1. Confirm approval to create an UPDATE change set for the reviewed template.
   Compare the current template and expanded policy with the operator baseline;
   account for drift and record the reviewed template fingerprint before
   creation.
2. Review every change. A model-only extension of this stack should modify the
   managed policy's reviewed document/metadata with `Replacement: False`.
   Preserve the existing user, policy ARN, boundary/attachment, retained
   resources and immutable properties. Any other change needs investigation and
   approval.
3. Keep pre-deployment validation enabled. Wait for a terminal change-set
   status, then inspect `describe-events` scoped to the change set or operation.
   Evaluate `VALIDATION_ERROR` events. Ordinary `STACK_EVENT` entries can have
   null validation fields. Require a successfully completed validation query and
   the runbook's passing conditions; FAIL blocks, WARN needs explicit
   acceptance, and unknown or SKIPPED checks remain unverified. An unsupported
   API returns to the operator for CLI-version resolution.
4. Recheck baseline identity/policy state and the change set's reviewed template
   fingerprint. Changed state returns to review. Require a ready, executable
   change set and explicit execution confirmation. Have the operator execute it
   and wait for the stack's terminal result. On failure, inspect events and
   retained-resource state before planning recovery.
5. Recheck the recorded baseline after the update and confirm the intended
   identity and resource relationships remained stable.

Compare the **entire deployed policy** with the reviewed policy expanded for the
confirmed account/region/partition. Use consistent JSON normalization on both
sides, preserve values and duplicates, and show a diff for any mismatch. Record
the canonicalization operation with any fingerprint. A statement count alone is
insufficient evidence for a policy match. Recheck the policy version around the
comparison to detect concurrent updates. Run Access Analyzer validation and
resolve findings under the runbook's criteria.

Finish with matching reviewed/deployed policy, expected post-update identity
state, and successful policy validation. If mutation was unnecessary, establish
the same current-policy evidence through the read-only operator checks.

## 3. IAM simulation

Use the workload user as the simulation source so its identity policy and
boundary both participate. Derive cases from the actual policy; extend the
runbook's matrix for each model addition without freezing this run's case count.

- **Matching profile:** both approved invoke actions must be allowed on each
  approved profile and its foundation resources with the correct profile
  context.
- **Foundation isolation:** invoke with missing or wrong profile context,
  including old/new cross-pairs, must be denied.
- **Metadata and counting:** approved profile discovery and foundation token
  counting must be allowed; counting keeps its independent context requirements.
- **Listing and bearer:** profile listing and the approved long-term bearer type
  must be allowed. Missing/wrong bearer type must be denied.
- **Excluded scope:** unapproved models and administrative actions must be
  denied.
- **Client-specific project:** preserve the default-project correct-model
  positive case and wrong-model/resource/action negative cases.

Inspect `ResourceSpecificResults` for multi-resource requests. Check the exact
requested action/resource coverage, each decision, and boundary detail; reject
missing, duplicate or extra results. Require
`AllowedByPermissionsBoundary: true` for allowed cases. Define expected
`MissingContextValues` per case: deliberately omitted keys may appear in
negative cases; unexpected missing context blocks acceptance. Deduplicate the
context-key inventory before constructing cases.

If a custom result parser is needed, first test synthetic nested results,
missing resources, denied boundary, duplicate decisions and omitted context.
Prefer the current maintained command path whenever it covers the required
cases.

Finish with every expected decision accounted for and zero unexpected allows or
coverage gaps. Keep actual bearer access and model capability for live
acceptance.

## 4. Availability, offers and pricing

Use the official APIs linked in the source map to prepare operator commands for
the selected **foundation model ID**. Collect only the model identifier and
`agreementAvailability`, `entitlementAvailability`, `authorizationStatus`, and
`regionAvailability` from `get-foundation-model-availability`. Record the
queried identity/account/region. This establishes availability for that query
context; runtime-key identity still requires separate evidence.

Readiness requires `AUTHORIZED` authorization and `AVAILABLE` for each
applicable availability status. When ready, return to live verification unless a
cost review is requested. For an in-flight or uncertain agreement request, use
[status reconciliation](#status-reconciliation). Investigate other unavailable
or error states with the operator before choosing a remedy.

When a new agreement is required, have the operator use
`list-foundation-model-agreement-offers`. Keep `offerToken` and signed URL query
strings local. Request a safe projection of offer metadata, terms, dimensions,
currency, units and prices. If offers link to pricing documents, have the
operator fetch those locally and return the relevant safe projection. Parse
responses as data and reject ambiguous offer selection. Handle API pagination
when supplied.

For cost analysis:

- Group by offer first, then by model, routing geography, service tier, context
  band and billing dimension. Many rate rows can belong to one agreement offer.
- Compare the supported request mode and like-for-like units. Separate input,
  output, cache reads and cache writes, including their durations. Identify
  batch or other conditional discounts as separate eligibility cases.
- Verify billing units against official documentation. Use decimal arithmetic:
  `display_rate = Decimal(price) * target_token_unit / source_token_unit`. Cite
  price operands, unit conversion, date, currency and source. Present only the
  relevant comparison and mark unknown dimensions unverified.
- Check the configured route and `ANTHROPIC_BEDROCK_SERVICE_TIER` independently.
  Recommend Global only when current matching rates and the user's routing/data
  constraints support it. The source region alone gives no data-residency
  promise.

Finish a cost review with an understandable comparison and a routing choice
supported by current evidence. When a new agreement is required, identify the
specific offer and continue to step 5. A pricing-only request ends with the
comparison.

## 5. Agreement creation and status reconciliation

For a new required agreement, ask for explicit acceptance of the selected
offer's legal terms and fees for the confirmed account/model. Routing or price
preference is a separate decision. Model enablement belongs to an appropriately
authorized management identity; keep the workload policy within its inference
contract.

After acceptance, prepare the operator's `create-foundation-model-agreement`
request from the current API schema. Select the exact reviewed offer locally,
write `modelId` and `offerToken` to a private temporary request JSON, and pass
its path through `--cli-input-json`. Keep token values out of argv, chat and
logs. Use the shared temporary-file rules and remove that request after use.

### Status reconciliation

An accepted create response can precede readiness. For `PENDING` or an uncertain
create result, provide bounded operator polling of availability with a deadline
and terminal-error handling. Recheck status before considering another mutation.
Stop at an error, expired deadline, or required authentication handoff.

Finish when the step 4 readiness conditions hold, then return to the requested
live verification.

## 6. Coordinated cutover, when requested

Read the integration runbook's formal cutover and recovery sections. Match the
required acceptance gates to the requested deployment. Present their evidence
and any remaining gaps before asking to publish or activate.

Have the operator record the previous generation, coordinate affected sessions,
and use the runbook's configuration-hash checks and paired generation/policy
procedure. Confirm the active manifest and newly started clients use the
intended build. Scope rollback and any credential lifecycle operations
separately according to their runbooks and approval requirements.

Finish with confirmed active state and the requested post-cutover checks, or a
clearly reported blocker with the preserved recovery reference.
