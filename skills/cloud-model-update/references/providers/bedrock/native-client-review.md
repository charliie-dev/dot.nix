# Native-client review

Use the source map's launcher and integration record to investigate a concrete
compatibility failure or a change to execution scope and security assumptions.
The [integration change](../bedrock.md#integration-change) workflow defines when
this branch applies.

## 1. Identify the affected client behavior

Record the resolved executable, platform and version for the investigation.
Confirm the target model's documented minimum client version and provider
support. Generic model-ID pass-through establishes string handling only;
compatibility also requires the documented model support and relevant runtime
paths below.

For a source extraction, record the extraction method, virtual module paths,
byte-span checks and formatting tool/options used for cited line numbers. Keep
reproducible extraction notes and short excerpts in the integration record.

Finish with a defined comparison baseline. If the old source is unavailable,
limit conclusions to the current build's checked paths.

## 2. Trace the security and model paths

Follow imports and aliases to actual definitions and call sites. Check the paths
affected by the update; justify any item already covered by a matching unchanged
approval.

- **Inference authentication:** bearer selection through request construction,
  helper/provider-chain and SigV4 behavior, and startup helper guards.
- **Discovery and counting:** metadata-client authentication,
  GetInferenceProfile backing-model derivation, and the resulting CountTokens
  input.
- **Model resolution:** alias and explicit-ID resolution, managed pins,
  fallback/overrides, context-suffix normalization and final request
  construction.
- **Effective sources:** relevant schema/CLI changes, settings precedence,
  environment, managed restrictions, signed client data, host/SDK/remote and
  worktree entry points.
- **Subprocesses:** credential scrubbing at Bash, command-hook, MCP-stdio and
  LSP call sites; MCP environment-reference and fallback expansion; DNT
  preservation.
- **Client behavior:** target model metadata, effective effort, supported
  context selection and the launch modes used by this integration.

Keep startup source/helper guards and empty AWS configuration intact. Evaluate
new sources or routes before expanding support. The existing approval's trusted
host, plugin, explicit child-environment, shell-startup, same-user process/file,
and proxy/TLS assumptions must stay explicit. Record per-request destination or
model binding only when corresponding evidence establishes it.

Finish with source evidence for every approval-critical conclusion. Mark
unresolved dependencies unverified.

## 3. Exercise the real boundary with synthetic tests

Reuse maintained tests. Use isolated HOME/configuration directories, fake
values, and controlled local responses for configuration-only native exercises.

- Run the integration change's model/consumer regressions and exercise source
  guards changed by this review.
- Bind extracted-function tests to the verified source and include negative
  controls. Cover both recognizable and opaque fake credentials, unset/empty
  variables, and MCP default-value expansion for affected scrub paths.
- Exercise native parsing for changed CLI/settings contracts. Use the supported
  empty MCP configuration shape from the maintained verifier.
- For permission claims, exercise the native CLI's normal permission/tool loop.
  Direct MCP tool execution establishes only that invocation path. Use ordinary
  readable controls and sensitive-name fixtures in both the primary directory
  and an added sibling directory; verify the current documented rule scope.

Distinguish source-bound tests, native CLI tests, and real service behavior in
the results. A release schema or metadata value supports its own limited claim.

Finish with passing positive/negative checks and explicit remaining live gates.

## 4. Verify the change and retain the evidence

For implementation, have an independent read-only reviewer check
security-sensitive changes against the cited source and tests. Recheck their
cited spans and resolve findings.

Update affected launcher behavior, rejection-message expectations and the
integration record together. Record the change scope, test method and remaining
limitations. Remove task-owned raw extracts after retaining the evidence needed
to reproduce the investigation.

Finish with applicable local regressions passing and unresolved behavior clearly
identified.
