# Azure (Azure OpenAI / Microsoft Foundry)

Azure hosts GPT models through Azure OpenAI and other families (Grok, Claude) through Microsoft
Foundry deployments on the same Cognitive Services account. The catalog's `model.format` field
(for example `OpenAI`, `xAI`, `Anthropic`) names the publisher; read it from the catalog rather
than inferring it from the model name.

Pass `--subscription` explicitly to every command. Verify command shapes with `az <group> --help`
and current Microsoft documentation before running them. The shell variables below stand for the
resolved non-secret target values.

## Locate the target

Resolve subscription, resource group, account, and region from the user's existing configuration
first: a client entry's endpoint (or the local gateway it points at) names the account. Follow
proxy or gateway references to their actual definitions; the [Grok Build memory topic][gb-memory]
records this setup's gateway and its known regressions. When several accounts fit, ask.

## Availability

```bash
az cognitiveservices account list-models \
  --subscription "$SUBSCRIPTION" -g "$GROUP" -n "$ACCOUNT"
az cognitiveservices account deployment list \
  --subscription "$SUBSCRIPTION" -g "$GROUP" -n "$ACCOUNT"
az cognitiveservices usage list \
  --subscription "$SUBSCRIPTION" -l "$REGION"
az rest --method get --url \
  "https://management.azure.com/subscriptions/$SUBSCRIPTION/providers/Microsoft.CognitiveServices/modelCapacities?api-version=2024-10-01&modelFormat=$FORMAT&modelName=$MODEL&modelVersion=$VERSION"
```

Filter output to the target model/version, SKU, region, and quota names; URL-encode query values.
Match the catalog SKU's `usageName` to the usage record. Remaining quota is
`limit - currentValue`; check `availableCapacity` separately. Respect the reported quota scope and
the capacity minimum, maximum, and step. Convert units to tokens/minute only when the usage label
or model rate metadata establishes that conversion.

A catalog listing establishes visibility. Report deployability only as far as SKU availability,
quota, and capacity support it; creation can still fail on permissions, access restrictions, or
shifting capacity.

## Provisioning

Re-read any existing deployment with the chosen name. An exact match (model, version, SKU,
capacity) is reusable. A difference needs explicit update authorization; an add request takes a
distinct name. For resizing, count the current allocation against the requested increase within
its quota scope.

```bash
az cognitiveservices account deployment create \
  --subscription "$SUBSCRIPTION" -g "$GROUP" -n "$ACCOUNT" \
  --deployment-name "$DEPLOYMENT" \
  --model-format "$FORMAT" --model-name "$MODEL" --model-version "$VERSION" \
  --sku-name "$SKU" --sku-capacity "$CAPACITY"
az cognitiveservices account deployment show \
  --subscription "$SUBSCRIPTION" -g "$GROUP" -n "$ACCOUNT" \
  --deployment-name "$DEPLOYMENT" \
  --query '{name:name,model:properties.model,sku:sku,state:properties.provisioningState}'
```

Wait for `Succeeded` and verify the returned model, version, SKU, and capacity. Monitor
long-running operations through a terminal state with bounded polling. Rollback or deletion
follows the user's authorization.

## Endpoint facts for the client step

- The **deployment name** is the model string sent in inference requests.
- A local gateway that maps deployment names explicitly must gain the new mapping before a client
  test can pass; inspect that mapping and get approval for any gateway change.
- For Claude on Foundry consumed by Claude Code, the client reference covers the
  `ANTHROPIC_FOUNDRY_*` path.

[gb-memory]: ~/.config/grok/memory-v2/workspaces/grok-e6c6eade/topics/grok-build.md
