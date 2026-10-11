---
name: cloud-model-update
description: >-
  Add, upgrade, or check a cloud-hosted model (GPT, Claude, or Grok family on Azure, Amazon
  Bedrock, or Google Vertex AI) and register it in Claude Code or Grok Build with a live
  connection test. Use for 新增／升級模型, checking whether a model is deployable or available
  in a region, wiring a new model ID into CC or GB config, or /cloud-model-update.
---

# Cloud model update

Take one model from a provider catalog to a working client entry. Each run touches three axes:
the **provider** (where inference runs), the **family** (the model's protocol and controls), and
the **client** (what consumes it). Load exactly one reference per axis; the workflow below owns
the order.

| Axis | Reference |
|---|---|
| Provider | [Azure](references/providers/azure.md), [Amazon Bedrock](references/providers/bedrock.md), [Google Vertex AI](references/providers/vertex.md) |
| Family | [GPT](references/families/gpt.md), [Claude](references/families/claude.md), [Grok](references/families/grok.md) |
| Client | [Claude Code](references/clients/claude-code.md), [Grok Build](references/clients/grok-build.md) |

## Operation boundaries

The [shared user rules](~/.config/claude/CLAUDE.md) own shell, authentication, and tooling policy.
Ordinary resource reads and inference use existing authentication. Login, token
retrieval/refresh, credential generation or rotation, and reading or editing credential files or
auth caches are user-run: stop the dependent step and hand over exact commands with the known
non-secret context. Reference credentials by environment-variable name or provider hook; keep
secret values out of tool output, config diffs, and this skill.

Cloud mutations (deployments, capacity, agreements, IAM) need the user's authorization for that
exact target. Creating a change and executing it are separate checkpoints.

## 1. Resolve the request

Classify it into one action class:

- **Availability check:** ends after step 2.
- **Audit / proposal only:** step 3 names the provisioning needed without running it, step 4
  outputs the intended diff without applying it, and step 5 runs only when the user approves a
  test.
- **Register an already-provisioned model:** skips step 3.
- **Provision and register:** runs every step.

An upgrade that replaces a model other callers still use is a replacement; account for every
consumer of the old ID.

Resolve provider, account/project/subscription, region, family, exact catalog model ID and
version, target client, and the alias users will select. Keep three identifiers distinct: the
catalog model ID, the deployment or inference-profile ID sent on the wire, and the client alias.
Use the user's existing configuration to pick candidates; ask only for choices that remain
ambiguous.

Check the family/client pairing in the family reference before going further: a pairing the
client cannot consume ends the run with that finding.

Finish with every axis resolved, the action class recorded, and the approval scope stated.

## 2. Check availability

Follow the provider reference's availability section against current official documentation and
CLI output. Report what the evidence supports: catalog visibility, region, quota/capacity, access
or agreement state. Mark each unavailable check unverified. An availability check reports here
and stops.

Finish with each availability dimension marked available, unavailable, or unverified, with its
evidence.

## 3. Provision access, when authorized

Follow the provider reference's provisioning section. Reuse an exact existing deployment or
grant; anything that changes an existing resource needs explicit replacement authorization. Wait
for a terminal provisioning state and re-read it independently of the create response. On
failure, keep existing working configuration and report the provider error.

Finish with the provisioned resource in a terminal success state and verified against the
intended model, version, and capacity, or with the blocking error reported.

## 4. Register in the client

Follow the client reference, using the family reference for protocol, reasoning, and limits.
Read the destination before editing; reuse an identical alias on reruns and ask about collisions
that would replace a different model. Make a targeted edit at the maintained source (generated
files are patched at their generator), preserving unrelated settings, comments, and permissions.

Similar model names do not establish identical capabilities: resolve context window, output
limit, and reasoning controls from current metadata or documentation. When a limit stays
unresolved, use the client's documented conservative default and say so.

Finish with every edited file parsed and the client reference's agent-checkable loading check
passed; checks that need an interactive session go to the user.

## 5. Test the connection

Run one bounded, low-output request through the configured client alias on the same endpoint,
backend, and credential path users will take, using the client reference's test command. Stop on
authentication errors under the boundaries above; an HTTP 401 or 403 leaves inference unverified.

Keep three results separate: provisioning success, configuration loading, and inference success.
Model-list visibility proves loading only.

Finish with a passed inference test showing the response, or the exact failing layer and its
error class.

## 6. Report

Report the provider resource (model, version, region, SKU/capacity or profile), config path and
alias, the three results from step 5, the command to select the model, and any user-run step
still needed. Support decision-critical claims with a source link or a relative path, line
range, and short excerpt. Clean up only this run's scratch files; preserve deployed resources.
