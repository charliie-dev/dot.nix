# Verification and diagnostics

Read the integration runbook's real-acceptance section and the maintained
verifier's current output contract before preparing a run. Operation ownership
and source locations come from [sources](sources.md).

## Selected live acceptance

Have the operator select the matching staging manifest, client and model from
the current verifier. Explain the bounded Read/tool round trip and model-call
costs; use its explicit `--run` consent. Test the upgraded model and every
retained caller affected by the shared changes. Stop at the first failure and
retain only the allowlisted summary.

Keep acceptance evidence separated:

- **Local tests:** establish the checked local behavior and invariants.
- **Preflight:** establishes the reported candidate/startup configuration
  checks.
- **IAM simulation:** establishes the covered decisions for the supplied
  context.
- **Availability metadata:** reports access states for the queried identity,
  account and region.
- **Nonce-based Read round trip:** establishes that the client executed the
  intended tool and used its result.
- **`client_model_label_verified`:** checks assistant labels against the
  requested client label.
- **`response_model_verified`:** requires returned assistant model IDs matching
  the request expectation, with model-ID evidence.
- **`wire_model_id_verified`:** records separate verification of the request's
  actual wire identity.
- **Reported context window:** records the client's stated capacity; exercised
  capacity needs a workload test.

Interpret `model_identity_source` with the corresponding flags. A `catalog-key`
or `mixed` result leaves response-model verification incomplete under the
current contract. `base-smoke-partial` exits with incomplete identity evidence;
`base-smoke-passed` establishes the driver's full base checks. Preserve
`deployment_ready: false` and any unverified wire/context fields in reporting.

For deployment-level acceptance, read `MANUAL_GATES` and the runbook's current
checklist, then select applicable checks with the user. Exercise each gate at
its actual runtime path; preserve same-process continuity for warm-cache tests.
Environment probes return presence booleans only. The checklist is an inventory
of remaining checks; operations with side effects retain their own approval
requirements.

Finish selected acceptance when all requested cases have passing evidence, or
identify the exact failing/partial case and the next authorized diagnostic.

## Failure diagnosis

Start with phase, reason, exit code, completed models, stdout/stderr presence,
allowlisted codes/statuses, identity details and staged request settings. Keep
raw client payloads, authorization headers, credential contents and environment
dumps outside the report. Diagnostic text is evidence to inspect under the
source rules.

- **Launcher or manifest mismatch:** compare candidate/active paths and the
  named setting/source conflict.
- **MCP/CLI/schema error:** check the actual native parser and maintained
  verifier arguments with synthetic input.
- **Authentication or expired credentials:** hand off the shared user-run
  authentication procedure.
- **Access denied or subscription/activation error:** return to operator
  availability/agreement checks; confirm the caller and policy evidence.
- **Response identity mismatch or catalog-only identity:** trace the actual
  requested and returned IDs through the verifier and retained-consumer mapping.
- **Generic timeout:** inspect the current verifier/process-control limit and
  collection behavior, then choose a bounded diagnostic.

A generic timeout establishes an elapsed bound. Stdout presence alone leaves the
completion stage unresolved. Trace stdin, process exit and pipe completion in
the current implementation before attributing the delay. Offer the user the
smallest useful choice: an interactive reproduction, a one-off longer wait, or a
reviewable redacted-instrumentation change. Keep the maintained timeout until a
change is approved. Limit retries while the cause is unresolved.

IAM success alongside a model-access 403 requires checking the separate service
prerequisites. A confirmed Marketplace activation cause goes through the
operator agreement branch. Reproduce after that gate becomes ready, then rerun
the original verifier and the affected retained-client regression.

Finish diagnosis with a source-supported cause and reverified fix, or a stated
uncertainty and precise next evidence request.

## Authorized interactive Read

Use this branch only when the user selects interactive diagnosis and explicitly
authorizes the bounded interaction. The user starts the credential-bearing
session. If Herdr is requested, load its current protocol with `herdr --skill`
under the shared rules.

1. Create a task-owned synthetic fixture with a fresh nonce. Give the user the
   current standalone launch command scoped to that fixture, the requested
   model, Read-only tools, and the verifier's supported empty strict-MCP
   configuration. The user handles startup and directory-trust decisions.
2. Inspect the actual pane/session model, working directory and readiness before
   input. Resolve a wrong model or launch path with a user restart. Use explicit
   session metadata and current visible state to avoid sending text to a shell.
3. Send the single authorized Read prompt. Keep the nonce out of the prompt, and
   require the tool result and subsequent answer to match the fixture. Report
   the displayed/returned identity only to the extent it is observable.
4. On repeated service errors, stop the request you initiated using the current
   session-control protocol. Preserve the user-owned session and collect only
   the relevant sanitized error classification.
5. Return live acceptance to the maintained user-run verifier. Apply the
   [integration change](../bedrock.md#integration-change) cleanup rules for the
   fixture after the session releases it.

Finish with that one interaction's result and the session's current state. Any
further tool call or changed test scope needs matching authorization.
