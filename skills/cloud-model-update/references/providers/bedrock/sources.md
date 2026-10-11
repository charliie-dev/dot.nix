# Sources and operation boundaries

## Operation boundaries

Read the [shared user rules][rules], the integration runbook's **操作界線**, and
the infrastructure runbook's **User-run** sections before choosing tools. These
sources own the authentication, secret-handling, and execution rules. Apply them
to helpers, delegated work, and terminal-control tools as well.

Agent work covers public source/configuration edits, builds, synthetic tests,
and redacted-result review. Real preflight, staging, AWS commands, activation,
and model launches are operator handoffs. Authentication or credential errors
return to the shared user-run procedure. Keep each shared mutation within
explicit approval; creating a change set and executing it are separate
checkpoints.

A separately authorized synthetic Read may be driven in a user-started session;
follow [authorized interactive Read][interactive]. This permission covers only
the named interaction. Key creation, rotation, revocation, and recovery remain
separately scoped operations in the existing runbooks.

## Local sources

These are starting locations for this user's existing setup. Expand `~`, resolve
actual paths and overrides, and open the named files before searching nearby.
Confirm a moved source with the user using non-secret path information.

- **Shared user rules:** [CLAUDE.md][rules] owns shell, authentication, tooling,
  browser and Herdr rules.
- **Claude configuration root:** `~/.config/claude`. Read relevant public fields
  in `settings.json`; read `tests/test_permissions.py` when permissions are
  involved.
- **Home Manager root:** `~/.config/home-manager`. Read
  `conf.d/bedrock-api-key/README.md` for operation boundaries, build/staging,
  acceptance, cutover and native review records.
- **AWS repository root:** `~/Work/aws`. Read `infra/README.md` for current
  management context, IAM contract, validation and deployment commands;
  `mise.toml` owns pinned tooling.
- **Active public build manifest:**
  `~/.config/bedrock-api-key/build-manifest.json` holds public executable and
  overlay paths for comparison with the candidate build.
- **General Claude upgrade audit:** load the `agent-update-check` skill when the
  native update also requires a broader settings or integration audit.

Within the Home Manager root, use these maintained owners:

- `conf.d/bedrock-api-key/claude.py`: `MODEL_PINS`, executable resolution,
  effective-source and helper guards.
- `conf.d/bedrock-api-key/runtime.nix`: generated Claude overlay, model display
  names, runtime and manifest definitions.
- `conf.d/bedrock-api-key/verify.py`: `CLAUDE_MODELS`, `GROK_MODELS`,
  `KNOWN_MODEL_LABELS`, result schema and manual gates.
- `conf.d/bedrock-api-key/process_control.py`: process/pipe timeout and capture
  behavior when diagnosing failures.
- `conf.d/bedrock-api-key/grok.py`, plus `grok_config.py` and `grok_policy.py`
  in that directory: retained Grok consumers, staged configuration and shell
  policy.
- `tests/lib/bedrock_claude.py`, `tests/lib/bedrock_verify.py`, and
  `tests/secrets/bedrock-api-key.bats`: maintained synthetic regressions; follow
  their imports for additional affected tests.
- `modules/apps/zsh/functions.nix`: shell launch routing and environment
  preservation.
- `modules/apps/mise.nix`: installed language-tooling source of truth.

Within the AWS repository, `infra/bedrock-api-key.yaml` owns the deployed
contract and `infra/tests/bedrock_api_key_test.rb` owns its local assertions and
limited intrinsic expansion. Derive model pairs, actions, resource counts,
account, region, stack, and immutable properties from the current files and
operator baseline. The test expander supports the template's local contract;
AWS-side checks remain a separate gate.

Read only selected public manifest fields such as `claude_launcher`,
`claude_overlay`, `claude_script`, `grok_config`, and `verify`. Resolve
candidate paths from that build's manifest. Preserve the distinction between a
candidate, the active manifest, and the executable actually used in a session.

## External evidence

Use current official documentation for the target release and region:

- [Claude model configuration](https://code.claude.com/docs/en/model-config) for
  version requirements, model controls and effort; follow current release notes.
- [Bedrock model access](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html),
  the target model's official model card, and
  [Bedrock pricing](https://aws.amazon.com/bedrock/pricing/).
- Bedrock API contracts:
  [GetFoundationModelAvailability](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_GetFoundationModelAvailability.html),
  [ListFoundationModelAgreementOffers](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_ListFoundationModelAgreementOffers.html),
  [CreateFoundationModelAgreement](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_CreateFoundationModelAgreement.html).
- [IAM EvaluationResult](https://docs.aws.amazon.com/IAM/latest/APIReference/API_EvaluationResult.html)
  for per-resource simulation output. Use the infrastructure runbook's linked
  service-authorization and CloudFormation validation references for its
  contract.

Keep offer IDs, price snapshots, policy versions and test counts in the current
review evidence. Refresh them from their owners on each run.

[rules]: ~/.config/claude/CLAUDE.md
[interactive]: verification-and-diagnostics.md#authorized-interactive-read
