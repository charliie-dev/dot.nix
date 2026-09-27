# Bedrock API key 與 Doppler

這份整合統一由既有的 `enableSecrets` 控制。所有 `enableSecrets = true` 的主機都部署
Bedrock profiles、程式、非秘密設定與 Claude 分流；停用 secrets 的主機保持停用。
Bedrock key 按使用者決定**不設定到期日**，存於 Doppler
`dot-nix / dev_personal / AWS_BEARER_TOKEN_BEDROCK`。

Grok 由 named provider 按需讀取 key；300 秒是重新讀取的快取時間。
Claude 在每次啟動時取得 key；既有程序持有啟動時的值。日常推論不使用 AWS 管理登入。

Grok launcher 與驗收器會在 client 啟動前額外移除
`INPUT_AWS_BEARER_TOKEN_BEDROCK`、`OPENAI_API_KEY`、`XAI_API_KEY` 與
`GROK_CODE_XAI_API_KEY`，避免 hook／MCP 繼承呼叫端的這些認證變數。
空值也會移除；`TYPESAFE_API_KEY` 保留既有放行行為。

## 操作界線

- Agent 可做公開程式、非秘密設定、build、純假資料測試及去敏結果核對。
- 以下登入、preflight、key 上傳／確認、staging、真實模型測試、設定遷移及 activation，
  由使用者在**自己的另一個 shell** 執行。
- API key 只留在 Doppler、受控 pipe 及程序記憶體。不要把值貼進聊天、argv、`.env`、
  Nix、settings 或日誌，也不要直接執行 `bedrock-api-key` 查看它的 stdout。
- 需要先恢復 `aws-secrets-manager` skill 指引，或明確批准計畫中的 Doppler 限縮例外，
  再開始秘密操作。這不授權 agent 代辦認證。
- 本機使用者、client、設定、plugins/hooks/MCP、proxy/TLS 都在信任範圍內。
  此方案沒有每請求的目的地綁定保證。無到期日的 key 依賴主動撤銷。

AWS user／policy／boundary 與手動部署步驟位於
`/Users/charles/Work/aws/infra/README.md`。部署前仍須完成該文件的 CloudFormation
schema、policy simulation 與 change-set 審查；離線契約測試不能替代 AWS 端驗證。

## 公開程式檢查

```sh
mise --cd /Users/charles/.config/home-manager run fmt
mise --cd /Users/charles/.config/home-manager run ci
```

CI 使用明確的 Mac／Linux fixtures，檢查兩個 Bats suites 的執行數及 skips，
並對非 NVIDIA 主機驗證套件、設定檔與分流是否一致依賴 `enableSecrets`。
所有 Python fixtures 都使用假 key、假 binaries／runner 或純訊息解析。
測試不取得真實 Doppler／AWS 秘密；Codex 的既有 sandbox 回歸使用隔離的 HOME。

## 1. Build 與 staging

以下各段在同一個使用者 shell 執行。先完成 AWS 文件中的 IAM 部署與權限核對，
並確認寫入者與 runtime 的 Doppler 讀取身分屬於同一 workplace／project／config。

```sh
umask 077
HM=/Users/charles/.config/home-manager
manifest_package=$(nix build --no-link --print-out-paths --impure --expr "
  let f = builtins.getFlake \"git+file://$HM\";
      packages = f.homeConfigurations.\"charles@24041-LABNB01\".config.home.packages;
  in builtins.head (builtins.filter
    (p: (p.name or \"\") == \"bedrock-build-manifest\") packages)")
manifest=$("$manifest_package/bin/bedrock-build-manifest")
grok_config=$(jq -r .grok_config "$manifest")
claude_launcher=$(jq -r .claude_launcher "$manifest")
key_admin=$(jq -r .key_admin "$manifest")
verify=$(jq -r .verify "$manifest")
stage=$(mktemp -d "${TMPDIR:-/tmp}/bedrock-stage.XXXXXX")
"$grok_config" stage "$stage"
"$claude_launcher" --bedrock-preflight
```

`stage` 只建立白名單模型、嚴格 shell policy 與指向 build output 的 provider。
`stage` 與 `publish` 會把 `model.bedrock-grok.reasoning_summary` 設為 `"none"`，
讓 Grok 省略 Bedrock 拒絕的 `reasoning.summary` 請求欄位。受控 Grok launcher 與
驗收器在啟動前要求這個值；缺少或不同值會停止。舊設定仍可供檢視、staging 與遷移。
正式 Grok config 保持原樣直到使用者執行 `publish`。Claude preflight 會讀取真實設定，
stdout 僅包含白名單 metadata。
遇到衝突先處理指定來源，再重新檢查；保持其他 provider 的秘密與設定分開管理。

目前 Claude launcher 接受已核對的 **2.1.282 與 2.1.283 macOS ARM64 native builds**，
依 `claude.py` 中的完整 SHA-256 清單核對實際執行檔。
`enableSecrets` 控制程式部署；Linux 的 Claude 執行仍會被既有平台檢查拒絕，須另做相容性審查。
更新 client 後需重新核對來源／測試並更新 reviewed digest。
2.1.283 的來源核對與限制記錄於本文末尾。
它支援 standalone CLI 與既有普通 linked worktree；建立新 worktree、remote／host-managed
session、SDK stream-input 等會改變有效來源的入口會停止，須另做相容性審查。
GUI／IDE 只有採同樣受支援的 standalone 呼叫方式時才能使用此 launcher。

`--client-data-url` 與 `CLAUDE_CODE_CLIENT_DATA_URL` 會指定額外的簽章設定來源，
launcher 在 preflight 階段拒絕這些入口。管理端的 `deniedModels` 與
`availableModelsMatch` 也會停止啟動，避免模型限制改變已核對的選擇結果；須由管理者
協調既有政策與固定模型。這兩個欄位在一般 user／project settings 中依原生語意忽略。

`ANTHROPIC_BEDROCK_SERVICE_TIER` 可由 shell 或 Claude settings 設定，支援
`default`、`priority`、`flex`、`reserved`；空值依 client 預設處理。
Launcher 保留既有選值，overlay 不替使用者指定 tier。服務等級可能影響優先順序與費率。

## 2. 使用者建立並上傳 key

在 IAM console 的專用 user 建立 Amazon Bedrock API key，選 **Never expires**。
記錄 user ARN、credential ID 與建立日期，確認沒有 `ExpirationDate`，並檢查 boundary／attachments。

上傳器使用使用者自己的 Doppler login 或隱藏輸入的既有 user token。
它要求既有私人 `HOME/.doppler` 目錄及設定檔，並固定 root scope。
必要時由使用者先完成登入與本機設定：

```sh
doppler --config-dir "$HOME/.doppler" --scope / login
doppler --config-dir "$HOME/.doppler" configure flags disable analytics
```

確認目錄及設定檔由自己擁有、沒有其他使用者存取權；有非預期 symlink／權限時先調查。
程式不會初始化、修復或刷新這些認證。完整設定或 audit log／diff 都可能包含秘密，
不要將原始輸出交給 agent。

```sh
"$key_admin" upload
```

按提示確認來源、排他寫入窗口、歷史回復來源、此次單 key 覆寫與 key 無到期日；
完整 key 經隱藏輸入及 stdin 傳給 Doppler。請貼入 key 原值；JSON envelope、陣列與
帶 JSON 引號的值會被拒絕，避免被 Grok 當成 provider 協定資料。完成後清除一次性剪貼簿。

上傳結果可能為已提交、未提交或未知。非零退出、斷線或 timeout 可能發生於遠端已寫入之後。
未知時保留 A／B 的有效狀態，停止切換；使用下列只輸出去敏結果的確認工具核對：

```sh
"$key_admin" confirm
```

提供候選 A 或 B，以及**該次寫入事件 ID**。工具只讀取最近 20 筆 bounded history；
無法定位、值／事件不一致、後續變更或權限不足時會停止。
`may_revoke_keys` 始終為 false；這份結果不能證明所有 client 已完成遷移。

## 3. 使用者真實驗收

先檢查並關閉測試不需要的自訂 plugins／hooks，保持模型工具權限為唯讀。
基礎 driver 對 Grok 四個模型、Claude 四個模型各送一個提示，模型可能再進行多次呼叫；
主流程上限為每個提示四 turns，按正常模型費率計費。執行 `--run` 代表確認這些測試。
Claude 測試使用 `--strict-mcp-config` 搭配 `--mcp-config '{"mcpServers":{}}'`，
指定符合原生 schema 的空設定，並保留 `Read` 工具限定及 MCP 工具拒絕規則。

```sh
"$verify" "$stage/manifest.json" --run
```

也可分開執行：

```sh
"$verify" "$stage/manifest.json" --client grok --run
"$verify" "$stage/manifest.json" --client claude --run
```

定位問題時可指定單一模型，降低重複請求：

```sh
"$verify" "$stage/manifest.json" --client grok --model bedrock-grok --run
```

失敗摘要會回報固定的 phase／reason、模型 alias、exit code 及已完成模型。
`diagnostics.codes` 與 HTTP status 是從 client 訊息辨識的線索，仍須依實際階段判讀。
`mcp-configuration` 表示辨識到 MCP 設定解析錯誤；`claude-launcher` 表示辨識到
Claude launcher 的錯誤前綴。`key-helper` 也涵蓋 Claude bootstrap 與 key 格式錯誤。
這些欄位僅輸出固定分類；原始錯誤文字與設定值留在短暫的記憶體 buffer。
`diagnostics.parameters` 只列出訊息中可辨識的白名單參數名稱；巢狀工具或輸入欄位
會歸為白名單父欄位，其他名稱省略。Grok 失敗時另回報 `staged_request_settings`，
包含啟動前 staging 的 `reasoning_summary`，以及模型／全域的 `stream_tool_calls`。
設定只回報白名單值、`unset` 或 `other`；這些值描述 staging 檔案，實際 wire 請求仍待確認。
模型不符時的 `diagnostics.model_identity` 回報白名單化的預期／實際模型標籤與值型別，
其他名稱顯示為 `unrecognized`。Grok 可回報本次請求的白名單設定鍵；driver 只接受
該鍵與既有的 model ID 形式，沿用單一 `[1m]` 顯示後綴正規化。其他設定鍵、錯誤 ID
與未知模型仍須拒絕。Claude 路徑繼續要求可核對的 model ID。
Stream 驗收失敗也會保留實際 stdout／stderr 接收資訊；此時 `returncode: 0` 表示 client
程序成功返回，後續內容驗收另有結果。
原始訊息、headers、key 與模型內容不會回印；讀取中的短暫 buffer 只留在記憶體。

Driver 在受控臨時目錄產生未寫入提示的 nonce，要求真實 Read → tool result → 後續回答，
並核對 assistant frame 的模型識別。相對工具路徑以 client 的 fixture 工作目錄解析，
所有路徑都須指向同一個 fixture。它將 raw client 輸出保留在記憶體，只印去敏摘要。
回應 model ID 與 request 的 wire model ID 分開看；輸出的 context windows 也只代表 client 回報值。

完整工具往返後，`client_model_label_verified: true` 表示每個 assistant frame 的標籤
都符合本次請求。只有全部回報可核對的 model ID 時，`response_model_verified` 才為 true。
設定鍵回報會標為 `model_identity_source: "catalog-key"`；混合回報為 `"mixed"`，兩者的
`response_model_verified` 與 `wire_model_id_verified` 都保持 false。此資訊無法排除
client 內部仍沿用相同標籤的 fallback，實際模型／provider 證據仍需補齊。

第一個未完成回應模型 ID 核對的案例會停止後續模型，回報 `base-smoke-partial`，exit code 2。
`base-smoke-passed` 使用 exit code 0；兩種結果都保留 `deployment_ready: false`。
正式切換前須補齊：

- 原生 Claude discovery／GetInferenceProfile／counting，區分正常能力限制與認證錯誤。
- Fable／Opus 實際 1M context budget、request model ID 已移除 `[1m]`。
- Explore／Plan、Haiku、必要插件、fallback 及背景路徑。
- Shell／hook／MCP-stdio 的 key、bootstrap、其他 provider key 缺席布林結果。
- Grok 同程序 warm cache／重新讀取、模型切換及 helper-only cold cache 行為。
- 新舊 key 輪替、舊 key 停用、所有既有 sessions／IDE 的遷移。
- Azure／原 Claude provider、`cc` trust／DNT，以及 generation／policy 回復。

原生 Claude 選單、背景路徑與 cache 等項目需要互動式驗收；不要以新程序的 smoke 成功代替。
秘密隔離探針只能輸出存在布林，不能 dump env 或 Authorization headers。

要獨立確認 AWS CLI 的 bearer metadata API，可在使用者 shell 以空 AWS config 執行：

```sh
doppler_run=$(jq -r .doppler_run "$manifest")
empty_config=$(jq -r .empty_aws_config "$manifest")
empty_credentials=$(jq -r .empty_aws_credentials "$manifest")
env -i HOME="$HOME" PATH="$PATH" \
  AWS_CONFIG_FILE="$empty_config" \
  AWS_SHARED_CREDENTIALS_FILE="$empty_credentials" \
  AWS_EC2_METADATA_DISABLED=true \
  "$doppler_run" bedrock-claude -- aws bedrock get-inference-profile \
  --region ap-northeast-1 \
  --inference-profile-identifier global.anthropic.claude-opus-5-5 \
  --query '{id:inferenceProfileId,status:status}' --output json --no-cli-pager
```

這只驗證 CLI 的那條路徑；原生 Claude 的 API 行為仍須另行核對。

## 4. 協調式正式切換

所有必要 gates 完成後，存檔並關閉受影響 client。先記錄 `home-manager generations`
顯示的目前 generation 路徑，供失敗時回復。排除同時修改 Grok config 的其他程式。

```sh
home-manager generations
review=$("$grok_config" check)
expected_hash=$(printf '%s' "$review" | jq -r .sha256)
"$grok_config" publish --expected-sha256 "$expected_hash"
home-manager switch --flake "$HM#charles@24041-LABNB01"
```

Publisher 更新四個 provider 引用、新 provider table、有序 shell policy，並將
`model.bedrock-grok.reasoning_summary` 設為 `"none"`；保留其他內容與
mode／owner／ACL／xattrs。`disable` 保留當時的 reasoning summary 設定。
Hash 不符或 metadata 不能保留時停止。
每個 `enableSecrets = true` 的主機都須協調更新 Grok policy，讓 exclude 清單包含
`AWS_BEARER_TOKEN_BEDROCK`。新舊 runner 的 exact-policy 清單必須與 generation 配對；
維護窗口內不要啟動 client。

新 shell 的使用方式：

```sh
grok-bedrock
cct bedrock
claude
claude-bedrock --model 'fable[1m]'
claude-bedrock --model 'opus[1m]'
claude-bedrock --model sonnet
```

原 `grok` 仍经 Azure launcher，可選四個 Bedrock aliases。
`grok-bedrock` 的 Azure fork／其他 provider 輔助功能仍有各自的認證需求。

## 輪替與回復

Key 無到期日；需要輪替時先確認 A 的回復來源，再建立 B。
發布 B 可能影響 Grok 下一次 refresh；Claude 在重啟後取得 B。
由使用者安排存檔／重啟、確認每個目標程序已使用 B，才依 AWS 文件停用 A。

B 有問題且 A 仍有效時，使用者從正確的單 key history 取得 A，核對 B 的寫入事件後執行：

```sh
"$key_admin" restore
```

它只 set `AWS_BEARER_TOKEN_BEDROCK`，保留其他 secrets。
排他寫入窗口是操作前提；前後比對沒有提供 API 未支援的 compare-and-swap。
未知結果、無法確認的並行編輯或 history 問題都會停止。

本機回復到舊 generation 前，先停用四個 Bedrock aliases，還原對應的舊 policy 清單：

```sh
review=$("$grok_config" check)
expected_hash=$(printf '%s' "$review" | jq -r .sha256)
"$grok_config" disable --expected-sha256 "$expected_hash"
```

之後由使用者切回原 Claude provider、關閉 Bedrock shell／IDE，再執行記錄的上一代
`/nix/store/...-home-manager-generation/activate`。所有受影響 client 在配對恢復完成後才重開。
`disable` 使用直接失敗的 provider，回復流程不會重新啟用舊 AWS token helper。

本機回復與更新 Doppler 都不會撤銷 AWS key。停用／永久刪除 key 及 IAM 資源另行確認。
全部 staged clients 結束後，清理這次由 `mktemp` 建立的 staging 目錄。

## Claude 2.1.283 來源核對

已核對 [官方 release manifest][release-283] 的
`platforms["darwin-arm64"].checksum`、本機公開執行檔及解包來源，SHA-256 為：

```text
d8cb1e5c79684cc12a8bfc813e3a2073406921b6245744b3009be3ab5651d21e
```

以下模組路徑相對於原生檔案 `__BUN` 內的 `/$bunfs/root/`，行號對應解包後僅做
Prettier 排版的 JavaScript。審查以已核對的 2.1.282 為比較基準。

- **推論認證**：`chunk-hzevqd7x.js:22738–22789` 從 bearer 建立 `Wt`，且
  `an = !Wt && !We && !Zt ? await QK() : null`；其他 credential resolvers 也受
  `!Wt && !We` 限制。`chunk-1jfzd350.js:492–502,571–586` 把 key 傳入
  `authToken: r`，僅在 `if (!this.skipAuth && !this.authToken)` 時做 SigV4。
  啟動時的 AWS helpers 另受 launcher 的 `AUTH_HELPERS` 禁止條件約束。
- **Discovery／counting 認證**：`chunk-1vt3h958.js:649–737` 以
  `if (!r && !a.AWS_BEARER_TOKEN_BEDROCK)` 限制顯式 credentials；
  `chunk-5qj86qz3.js:4098–4111` 選擇 `return ["httpBearerAuth"]`，
  `chunk-71c57f0c.js:107–155,328–336` 解析 bearer identity 並設定 Authorization。
- **模型識別**：`chunk-fqtthcxr.js:61–63` 的
  `return e.replace(/\[(1|2)m\]/gi, "");` 由 `uD` 呼叫。
  `chunk-1vt3h958.js:15103–15108` 對具體 Bedrock ID 提早回傳，
  `chunk-wyjbafrm.js:98154–98175` 使用 `model: uD(h.model)`；
  `chunk-1jfzd350.js:549–565` 以 `let u = n.model` 建立 invoke 路徑。
  CountTokens 的 backing model 由 GetInferenceProfile 回應導出：
  `chunk-1vt3h958.js:759–795` 讀取 `models?.[0]?.modelArn`。實際服務回應仍待驗收。
- **新增來源與政策**：`chunk-cpf7rt77.js:5414–5426` 呼叫 signed-client-data
  loader，再解析初始模型；`chunk-9kx8dy2e.js:190–205` 先以
  `if (Ie() !== "firstParty")` 拒絕第三方 provider。
  `chunk-18sktzq8.js:8091–8100` 將 `availableModelsMatch`／`deniedModels` 限於
  managed settings；`chunk-fr7r2xfj.js:1005–1013` 的 `if (c && !Vr(c))`
  分支可能替換模型。對應入口現由 launcher 停止，交由使用者或管理者協調。
- **子程序環境**：`chunk-8mkwx7mn.js:1045–1060,1427` 將 bearer 與其 `INPUT_`
  形式列入清單；`chunk-hkrvpm2b.js:785–795,1057–1070` 在 scrub 啟用時執行
  `delete x[p]`。`hs()` 的呼叫點包括 shell 與 command hooks
  （`chunk-wyjbafrm.js:41880–41897,105880–105966`）、MCP-stdio
  （`chunk-w61ke47p.js:3087–3110`、`chunk-gg4jhzsm.js:2869–2891`）及 LSP
  （`chunk-wthhr3tb.js:3491–3497`）。
  MCP 的 `_yn → Aj` 預設環境展開另經
  `chunk-wyjbafrm.js:12235–12265` 的 `(B9e().length > 0 && I4n(e))`，再執行
  `let ze = He ? "" : Ne`；名稱判斷見 `chunk-hkrvpm2b.js:895–898` 及
  `chunk-8mkwx7mn.js:1467–1512,1832–1835,1861–1881`。這項結論依賴啟動時明確
  設定 `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`。

- **CLI 空 MCP 設定**：`chunk-cpf7rt77.js:4257,4625–4685` 將 `mcpConfig` 交給
  `Not`，錯誤時呼叫 `nn`；`chunk-yzbw3nz3.js:14–20` 以 `console.error` 與
  `process.exit(1)` 結束。`chunk-wyjbafrm.js:25559–25587` 實際執行
  `u({ mcpServers: fe(o(), ae()) }).safeParse(n)`。已在隔離 VM 使用同一份 Zod 與
  抽出的 `Not` 重現：`{}` 產生 `mcpServers` 致命錯誤，`{"mcpServers":{}}` 通過。
  驗收器的 CLI 參數已採用通過的格式，並測試固定錯誤分類與秘密字串缺席。

隔離的純函式測試涵蓋四個模型 alias、四個直接 pin 與 `[1m]` 正規化；MCP 展開另以
可辨識及無特殊格式的假 bearer 比較兩版本。這些檢查支援可信任主機上的啟動相容性。
函式型 hooks、任意 plugin／runtime 修改、同使用者檔案與程序存取仍屬信任界線；
真實 discovery／counting、模型請求、context budget 與互動流程依第 3 節另行驗收。

[release-283]: https://downloads.claude.ai/claude-code-releases/2.1.283/manifest.json
