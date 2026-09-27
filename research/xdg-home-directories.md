# Home 根目錄的 XDG 路徑研究

查核日期：2026-09-27。結論以已安裝版本的原始碼、官方文件與安全的本機中繼資料為依據。

## 後續處理項目

- [ ] `~/.doppler`：確認舊目錄的寫入來源與資料用途，再處理搬移或清理；憑證相關操作由使用者在獨立 shell 執行。

使用者已決定保留 `~/.ego-browser` 與其中的 state 資料，Ego 搬移計畫已取消。

使用者已決定保留其他被工具寫死的固定路徑，包括 `.aws/cli`、`.terraform.d`、`.agents`、
`.sigstore`、`.well-known` 與 `.clop-debug-logs`。以下研究作為背景資料，這些項目不列入遷移工作。

## 結論

- `~/.aws/cli`：部分子項目可改路徑；role credential cache 仍使用寫死的 home 路徑。
- `~/.terraform.d`：CLI 設定與 provider cache 可分別搬移；全域目錄、自動憑證檔與 helper 搜尋路徑仍有固定位置。
- `~/.agents`：目前是 Skills 安裝器與多個工具共用的路徑約定，搬移需同步調整安裝與讀取端。
- `~/.doppler`：有正式的目錄覆寫，現有設定已使用；舊目錄目前的寫入者與內容處置仍待確認。
- `~/.ego-browser/state`：SDK 支援覆寫；已驗證在 Node 腳本中設定可跨回合使用，shell export 未傳入 SDK。
- `~/.sigstore`：TFLint 的驗證流程會使用這個預設位置，該流程尚未提供專用的路徑設定。
- `~/.well-known/mcp/clop.json`：Clop 固定寫入的服務探索檔，每次啟動都會更新。
- `~/.clop-debug-logs`：Clop 固定寫入的檔案，現行 writer 沒有路徑或停用設定。

目錄 symlink 可以將實體資料放到 XDG 位置，home 仍會保留同名入口。
完全消除固定入口，需要相關程式提供路徑選項，或調整所有寫入與讀取流程。

刻意保留的例外：`~/.DS_Store`、`~/.zshenv`、`~/.claude` symlink。

## 已完成的 Ruff 與 Bash 變更

- `~/.ruff_cache` 已搬至 `~/.cache/ruff`。
- `~/.bash_history` 已搬至 `~/.local/state/bash/history`。
- 搬移前拒絕既有目標；搬移後確認 inode、大小與權限相同，history 內容未輸出。
- `modules/core.nix:64–66` 新增 `RUFF_CACHE_DIR = "${config.xdg.cacheHome}/ruff";`。
- `modules/apps/bash.nix:3–7` 使用 `enable = true;`、`package = null;` 與
  `historyFile = "${config.xdg.stateHome}/bash/history";`。

Bash history 設定僅交給 Bash。`HISTFILE` 沒有加入全域環境，Zsh 繼續使用自己的 history。
Home Manager 的 Bash 模組會生成 `.bashrc`、`.bash_profile`、`.profile`：
[鎖定版本 `modules/programs/bash.nix:249–289`][hm-bash] 分別宣告
`home.file.".bash_profile"`、`home.file.".profile"` 與 `home.file.".bashrc"`。

### Home Manager 切換後查核

使用者已執行 Home Manager switch。乾淨程序載入已部署的 session variables 後，
Ruff 實際回報 `cache_dir = "/Users/charles/.cache/ruff"`，舊的 `~/.ruff_cache` 保持不存在。

首次切換後，Bash history 資料已在 XDG state 目錄，權限為 `0600`；Bash 設定尚未部署。
當時 `~/.bashrc`、`~/.bash_profile`、`~/.profile` 都不存在，
新增的 `modules/apps/bash.nix` 尚未被 Git 追蹤。該次同一主機的求值結果為：

- Git flake：`sourceIncludesBashModule = false`、`bashEnabled = false`，
  `bashStartupFiles = []`。
- Path flake：`sourceIncludesBashModule = true`、`bashEnabled = true`，會產生三個 Bash 啟動檔。

因此一般 Git flake 的來源略過了新增模組。可用包含新檔案的 path 來源重新部署：

```sh
home-manager switch --flake 'path:/Users/charles/.config/home-manager#charles@24041-LABNB01'
```

模組目前已納入 Git 追蹤，一般 Git flake 會包含它。
完整切換會套用當時工作樹內的其他變更。

### mise Bash completion 建置修正

後續 switch 在 `mise-bash-completion.bash` 建置失敗，錯誤是
`mkdir: cannot create directory '/homeless-shelter': Read-only file system`。

[Home Manager `modules/programs/mise.nix:162–172`][hm-mise] 透過
`pkgs.runCommand "mise-bash-completion.bash"`，在建置時呼叫
`completion bash --include-bash-completion-lib`。
本 repository 的 `pkgs.mise` 是 runtime bootstrap：
`modules/runtime/binary-stubs.nix:38–43,70` 使用 `$HOME` 計算安裝及鎖定目錄，
再執行 `mkdir -p "$install_dir" "$lock_dir"`。因此建置程序嘗試寫入不可寫的建置 HOME。

修正保留 Bash 的 mise activation 與 completion：

- `modules/apps/mise.nix:9,155–160` 關閉上游建置期整合，
  由 Bash 啟動時執行 `activate bash` 並載入使用者目錄中的 completion。
- `modules/runtime/binary-stubs.nix:343–358` 增加
  `bash-completion/completions/mise.bash`，與 Zsh completion 一起由 native mise 在執行階段產生。

已先確認新增的真實 `.bashrc` 建置測試與 Bash completion 資產測試失敗，再套用修正。
修正後 XDG 與 runtime bootstrap 共 13 項測試通過；另以安裝版 mise 在隔離 HOME
產生 Bash completion，成功載入並註冊 `complete -F _usage_complete_mise mise`。

使用與失敗時相同的 Git flake 及 `charles@24041-LABNB01.local` 目標，
完整 `activationPackage` 已建置成功。生成的 `.bashrc` 包含 XDG history 與 runtime
mise 整合，依賴圖已排除舊的建置期 completion derivation。實際啟用由使用者再次 switch 完成。

Ruff 0.16.9 的 `ruff config cache-dir` 說明指出，`RUFF_CACHE_DIR` 取代預設 cache 位置；
明確的專案 `cache-dir` 設定仍有更高優先權。

### 根目錄 `.zshrc`

使用者已移除根目錄 `.zshrc`，本次查核確認該路徑不存在。刪除前的判斷依據：

- 刪除前 `../../.zshrc:1–2` 只有 `export PATH="$HOME/.local/bin:$PATH"`。
- `modules/core.nix:47–50` 的 `sessionPath` 已包含 `"${config.home.homeDirectory}/.local/bin"`。
- `modules/apps/zsh/core.nix:21–22` 設定 `dotDir = "${config.xdg.configHome}/zsh";`。
- 實際 `.zshenv` 轉入 XDG 設定後，會設定 `ZDOTDIR=/Users/charles/.config/zsh`。
- 隔離 home 的實測中，根目錄 `.zshrc` 存在與移除兩種情況都載入 XDG `.zshrc`。

切換後的四個 Zsh 啟動檔皆通過語法檢查。已部署的 `../zsh/.zshrc:161–165`
仍設定 `HISTFILE="/Users/charles/.local/state/zsh/history"`。
驗證涵蓋載入路徑、語法與環境設定；完整互動啟動會載入秘密，本輪以乾淨程序檢查環境設定。

重新執行 xdg-ninja 後，七個剩餘命中皆屬固定路徑或刻意保留項目。
工具的三個可遷移計數是 `.Trash`、`.claude` 與 `.zshenv`，均已列為保留。

## AWS CLI：部分支援

查核版本：AWS CLI **2.37.4**，Homebrew 安裝；以空的測試 HOME 執行版本查詢確認。

### Role credential cache

[`awscli/customizations/assumerole.py:4–8,44–49`][aws-cache] 定義並使用：

```python
CACHE_DIR = os.path.expanduser(os.path.join('~', '.aws', 'cli', 'cache'))
assume_role_provider.cache = JSONFileCache(CACHE_DIR)
```

同一段程式也將此 cache 注入 web-identity provider。
SSO role credentials 經由 [`sso/utils.py:35–36`][aws-sso-alias] 的
`CACHE_DIR as AWS_CREDS_CACHE_DIR`，再由
[`sso/__init__.py:38–42`][aws-sso-cache] 傳給 `JSONFileCache(AWS_CREDS_CACHE_DIR)`。

這條路徑的操作是展開 `~`，再拼接 `.aws/cli/cache`；上述常數與呼叫沒有專用路徑覆寫。

[`awscli/botocore/configprovider.py:65–72`][aws-config] 分別將
`AWS_CONFIG_FILE` 與 `AWS_SHARED_CREDENTIALS_FILE` 綁定到設定檔與憑證檔。
現有 `modules/core.nix:128–129` 已將這兩者放到 XDG config；role cache 仍由前述常數決定。

### 可搬移的部分

命令歷史可用 `AWS_CLI_HISTORY_FILE` 指定絕對路徑，例如
`$XDG_STATE_HOME/aws/cli/history.db`。

- [`history/constants.py:15–18`][aws-history-constant]：
  `HISTORY_FILENAME_ENV_VAR = 'AWS_CLI_HISTORY_FILE'`。
- [`history/__init__.py:50–60`][aws-history-writer]：
  `os.environ.get(HISTORY_FILENAME_ENV_VAR, DEFAULT_HISTORY_FILENAME)`，再建立父目錄及資料庫。
- 同檔 `:77–96`：`scoped_config.get('cli_history') == 'enabled'`，表示錄製需要啟用該功能。

此設定的作用範圍是命令歷史。保留 role／web-identity／SSO role credential cache 功能時，
現行 CLI 仍會存取固定的 home 路徑。既有 `.aws/cli` 的哪些檔案仍在使用，屬於未驗證範圍。

## Terraform：部分支援

已安裝 **1.16.1** 與 **1.14.7**，以直接呼叫安裝檔的版本輸出確認。
本次 repository context 的 mise shim 沒有啟用中的 Terraform 版本。
以下引文使用 1.16.1；研究另比對了 1.14.7 的相同路徑邏輯。

### 全域目錄

[`internal/command/cliconfig/cliconfig.go:98–101`][tf-config-dir] 將 `ConfigDir()`
轉交給 `configDir()`。macOS 使用的
[`config_unix.go:25–43`][tf-home] 先從 `homeDir()` 取得 HOME，再執行：

```go
return filepath.Join(dir, ".terraform.d"), nil
```

該完整函式沒有 XDG 或全域目錄環境變數覆寫。

### 現有設定已處理的部分

- `modules/core.nix:92`：`TF_CLI_CONFIG_FILE = "${config.xdg.configHome}/terraform/terraformrc";`。
- `modules/apps/terraform.nix:7–16`：
  `pluginCacheDir = "${config.xdg.cacheHome}/terraform/plugin-cache";`，
  再將 `plugin_cache_dir = "${pluginCacheDir}";` 寫入 terraformrc。
- 同檔 `:16`：`disable_checkpoint = true;`。

[`cliconfig.go:402–417,438–443`][tf-config-file] 從 `os.Getenv("TF_CLI_CONFIG_FILE")`
選擇主設定檔。設定覆寫後，
[`cliconfig.go:121–138`][tf-config-load] 的 `if CLIConfigFileOverride() == ""`
分支會略過預設目錄內的設定片段。

[`checkpoint.go:26–32,38–60`][tf-checkpoint] 先檢查 `c.DisableCheckpoint` 並返回，
因此現有停用設定可避開 `checkpoint_cache` 與 `checkpoint_signature` 的寫入流程。

### 仍依賴全域目錄的部分

自動憑證檔的目標由
[`cliconfig/credentials.go:29–34`][tf-credentials-path] 組成：

```go
configDir, err := ConfigDir()
return filepath.Join(configDir, "credentials.tfrc.json"), nil
```

`TF_CLI_CONFIG_FILE` 的設定不會改變這個函式的回傳值。
同檔 `:103–107` 還會透過 `ReadHostsInCredentialsFile(credentialsFilePath)`
檢查既有自動憑證檔。憑證查找支援其他來源：
[`credentials.go:120–121,232–247`][tf-credentials-sources] 的 `TF_TOKEN_` 環境變數、
CLI 設定內的 credentials block，以及 credentials helper。
這些機制的設定與驗證由使用者在獨立 shell 進行。

Helper 另有路徑限制：
[`commands.go:507–509`][tf-helper] 呼叫
`FindPlugins("credentials", cliconfig.GlobalPluginDirs())`；
[`cliconfig/plugins.go:19–28`][tf-plugins] 從 `ConfigDir()` 拼接 `plugins`
與 `plugins/<os>_<arch>`。因此改用 helper 仍需處理它的安裝位置。

結論：若只使用已移走的設定與 provider cache，部分傳統目錄內容可能成為歷史殘留；
自動憑證儲存及全域 helper 等功能仍使用固定目錄。
本輪未讀取該目錄內容，也未驗證能否安全刪除現存資料。

## `.agents`：共用安裝與探索路徑

查核 Skills **1.7.0** 的 npm package 與對應來源 commit。

[`src/constants.ts:1–3`][skills-constants] 宣告 `AGENTS_DIR = '.agents'`
與 `SKILLS_SUBDIR = 'skills'`。
[`src/installer.ts:128–131`][skills-root] 的完整組合函式是：

```typescript
const baseDir = global ? homedir() : cwd || process.cwd();
return join(baseDir, AGENTS_DIR, SKILLS_SUBDIR);
```

這是 global 安裝的 canonical payload 位置，該函式沒有 XDG 覆寫。

目前 repository 也明確依賴它：`.mise/tasks/skills/install:8–9,12–20`
使用 `skills add ... --global`，並將 Pi 的 skill 連結到
`"$HOME/.agents/skills/$skill"`。
本機 Claude／Grok 的部分 skills 同樣以 symlink 指向此處。

Skills 的 `--copy` 模式能改成每個 agent 各自一份：
[`installer.ts:366–375`][skills-copy] 的 `if (installMode === 'copy')`
會先複製到 `agentDir` 並返回。
選到 universal agent 時，
[`installer.ts:157–160`][skills-universal] 仍使用 `getCanonicalSkillsDir(global, cwd)`。

因此完整搬移需要同步調整安裝命令、Pi 連結、各 agent 的讀取路徑，
並處理 Ego 自動安裝 skill 的行為；[Ego 官方文件][ego-document] 明列其安裝到
`~/.agents/skills` 與 `~/.claude/skills/`。
保留 `.agents` 相容 symlink 是影響較小的實體搬移方法。

## `.ego-browser/state`：保留原位，搬移已取消

目前決策是保留 `~/.ego-browser` 與其中的 state。以下技術研究與搬移方案僅供備查。

查核 Ego lite **0.5.1.13** 的已安裝 SDK，並與公開來源的對應程式碼比對。
這個目錄保存頁面標籤對照資料，SDK 稱為 ledger，用於在不同執行回合恢復頁面標籤。

[`package/ego-browser/src/page-ledger.ts:81–85`][ego-root] 的優先順序為：

```typescript
options.rootDir ||
  process.env.EGO_BROWSER_STATE_DIR ||
  join(homedir(), ".ego-browser", "state");
```

[`src/page-model.ts:790–795`][ego-lazy] 在首次 `taskSpace()` 時才初始化 ledger，
傳入的 options 只有 `browserInstanceId`，因此腳本可在首次呼叫前設定環境變數。

### 實測

1. 在呼叫端 shell 設 `EGO_BROWSER_STATE_DIR`，SDK Node 環境回報 `null`。
2. 在 Node 腳本第一行設定同名 `process.env`，再建立全新的空白測試空間。
3. 指定的 `/tmp` 目錄成功產生 `space-20.json`。
4. 下一次 Node 執行設定相同路徑，成功恢復同一個 `p1` 空白頁。
5. 使用 `task.finish({ keep: [] })` 關閉測試空間。

可使用的腳本前置設定範例：

```javascript
process.env.EGO_BROWSER_STATE_DIR = "/Users/charles/.local/state/ego-browser";
```

該目錄直接容納 `space-N.json`。每個 Node 執行回合都要在首次 `taskSpace()` 前設定。
本輪驗證使用全新測試狀態；既有 ledger 尚未搬移。

### 一次性設定的進一步查核

本機仍是 Ego lite **0.5.1.13**。本輪只讀取程序／環境中繼資料，未開啟既有 state JSON。
目前 `.ego-browser/state` 是 `0700` 的實體目錄，含一個直接項目；
建議目的地 `/Users/charles/.local/state/ego-browser` 尚不存在。

已安裝 CLI 的 `nodejs --help` 列出 `-e`、`--eval`、stdin 與 `--sdk-path`，
沒有列出 env-file 或持久 state-root 選項。
[官方本地 runtime 文件 `docs/local-runtime-development.md:48–50`][ego-local-runtime]
明說：「Every manual invocation needs `--sdk-path`; it is not a persistent setting.」
該選項用於選擇 SDK，還有版本與生命週期相容性要求。

公開 SDK 確實有 `.env` 啟動載入機制：
`src/index.ts:4` 匯入 helpers，`src/helpers.ts:5` 匯入 state；
[`src/state.ts:3–5`][ego-state-init] 在模組載入時執行 `loadEnv();`。
[`src/env.ts:6–19,32–42`][ego-env] 依 SDK 檔案位置及 agent workspace 載入：

```typescript
loadEnvFile(resolve(REPO_ROOT, ".env"));
loadEnvFile(resolve(agentWorkspace(), ".env"));
```

然而，本輪建立了只含測試路徑的暫存 workspace 與 `.env`，
透過呼叫端 `EGO_BROWSER_AGENT_WORKSPACE` 指向它後，已安裝的 CLI 回報：

```json
{ "workspace": null, "stateDir": null }
```

因此這個呼叫端 env-file 方案在目前原生 CLI／已開啟的 app 情境仍未生效。
SDK 的 `.env` 機制與 Ego 主程序的環境轉交是兩個需要分別確認的層次。
[原生 bindings 文件 `docs/native-bindings-api.md:3–9`][ego-native-bindings]
也說明原生能力由已安裝 app 提供，與 SDK Git tag 分開。

另一個唯讀 probe 確認 Node 的父程序是 Ego app，Node 內已有正確的 `XDG_STATE_HOME`，
但 `EGO_BROWSER_STATE_DIR` 為 `null`。前述 ledger constructor 沒有讀取 `XDG_STATE_HOME`。
尚未確認 Ego 主程序會讀取、可由使用者長期管理的 `.env` 位置，
也未驗證在 GUI 啟動環境設定變數、重啟 app 後的繼承行為。
目前已直接驗證成功的機制仍是每回合腳本內的 `process.env` 前置設定。

### 可行方案與遷移條件

如果要完全移除 HOME 下的 ledger 寫入，需要統一所有呼叫端的設定。
一個保留 Ego 隨附 SDK 的候選方案是受管理的啟動器，在送入 `nodejs` 的腳本前加入路徑設定。
這個啟動器尚未實作或測試，至少須涵蓋 `-e`、`--eval`、heredoc／pipe、引號與退出碼；
互動 REPL 需要獨立驗證。所有手動、agent、GUI 呼叫端都要使用同一入口。

若接受 HOME 保留相容入口，目錄 symlink 是維護成本較低的實體搬移方式。
SDK 的 IO 以 root 加上子檔名進行讀寫，實作見
[`src/page-ledger.ts:462–478`][ego-ledger-io]。
HOME 下仍會有 `.ego-browser` 或其 `state` 入口。
本輪只研究此方案，未建立任何實際 symlink。

遷移時應先暫停 agent 寫入、保留完整私有備份、拒絕覆寫既有目的地，
並維持每個呼叫端使用同一份 ledger。備份應放在 active root 外，
因為同檔 `:430–456` 會清理過期且屬於其他 browser instance 的 ledger。

另外，單為搬移而重啟 Ego 會增加頁面標籤失效的風險：
[`src/page-ledger.ts:49–54`][ego-instance] 使用 `browser-host:${parentPid}`
作為 instance id；
[同檔 `:383–389`][ego-ledger-read] 在既有與目前 id 不符時回傳 `emptyLedger(...)`。
若要測試 GUI 啟動環境的永久設定，應先結束目前瀏覽器任務，並把它視為未驗證候選。

回復時也要一併處理資料：新位置一旦收到寫入，原來的備份就已落後。
應先暫停寫入、保留兩份資料，再切回確定為最新的整組 ledger；
逐檔合併或單改入口可能遺失標籤更新。所有實際資料搬移留待另行授權。

## `.doppler`：現有覆寫有效，舊目錄用途待確認

一般 shell 使用 Homebrew Doppler **3.76.6**；已部署的 `doppler-run` 使用 Nix Doppler **3.76.5**。
兩個版本的 `pkg/cmd/root.go`、`pkg/configuration/config.go`、`pkg/utils/util.go`
已直接比較，內容完全相同。3.76.6 的來源封存檔 SHA-256 也與 Homebrew formula 一致。

[`pkg/cmd/root.go:113–125`][doppler-flags] 先讀取
`os.Getenv("DOPPLER_CONFIG_DIR")`，再套用明確的 `--config-dir`。
`--no-read-env` 會停用環境變數讀取。
同檔 `:42–45` 的順序為 `loadFlags(cmd)`、`configuration.Setup()`。

[`pkg/configuration/config.go:61–75`][doppler-dirs] 的 `SetConfigDir(dir)` 同時設定：

```go
UserConfigDir = dir
UserFallbackDir = filepath.Join(dir, "fallback")
UserMetadataDir = UserFallbackDir
UserConfigFile = filepath.Join(UserConfigDir, configFileName)
```

因此它具有完整的主要設定目錄覆寫功能。

現有 repository 保留三個不同的使用情境：

- Shell：`modules/core.nix:93` 的 `${config.xdg.configHome}/doppler`。
- Wrapper：`modules/secrets/doppler.nix:15,386` 的
  `dopplerRunConfigDir = "${config.xdg.cacheHome}/doppler-run";`，
  並設定 `final["DOPPLER_CONFIG_DIR"] = RUN_CONFIG_DIR`。
- GUI：`modules/platform/services/brew-env.nix:26,43–55` 的
  `dopplerGuiConfigDir = "${config.xdg.cacheHome}/doppler-gui";`，
  經條件檢查後使用 `launchctl setenv DOPPLER_CONFIG_DIR`。

這些隔離目錄各有用途，應保持分離。

### 本機進一步查核

本輪已確認三個實際入口：

- Shell 的 `DOPPLER_CONFIG_DIR` 是 `/Users/charles/.config/doppler`。
- `launchctl getenv DOPPLER_CONFIG_DIR` 回傳 `/Users/charles/.cache/doppler-gui`。
- 已部署的 `doppler-run.py` 設定
  `RUN_CONFIG_DIR = "/Users/charles/.cache/doppler-run"`，
  並把它傳給 `--config-dir` 與目標程序的 `DOPPLER_CONFIG_DIR`。
  對應來源為 `modules/secrets/doppler.nix:15,102,325–330,386`。

四個目錄的權限均為 `0700`。舊的 `~/.doppler` 是實體目錄且非空，
目錄 mtime 為 `2026-09-25 20:29:25 UTC`；GUI 專用目錄目前為空。
這些是目錄中繼資料，未讀取設定、憑證或快取內容。
目錄 mtime 也不足以判斷檔案是否仍在使用。

主要資料路徑會跟隨設定根目錄：

- [`pkg/cmd/run.go:613–635`][doppler-fallback] 以
  `filepath.Join(configuration.UserFallbackDir, fallbackFileName)` 建立 fallback 路徑。
- [`pkg/controllers/fallback.go:60–67`][doppler-metadata] 以
  `filepath.Join(configuration.UserMetadataDir, fileName)` 建立 metadata 路徑。
- [`pkg/tui/common/logging.go:61–63`][doppler-log] 以
  `filepath.Join(configuration.UserConfigDir, "tui.log")` 建立除錯日誌路徑。

因此現有三個入口的路徑設定已就緒。仍可能使用舊目錄的情況包括：
呼叫端缺少環境變數、使用 `--no-read-env` 且未指定目錄，或明確指定舊路徑。
[`pkg/cmd/root.go:113–125`][doppler-flags] 也保留獨立的舊 `--configuration` 檔案覆寫。
目前尚未建立任何特定程序是舊目錄寫入者的證據。

使用者後續提供的六行 `fs_usage` 紀錄（08:09:29）只有 `getattrlist` 與 `fsgetpath`，
程序為 Finder 與 `com.apple.appkit.xpc.openAndSave`。
這些事件顯示目錄屬性及路徑查詢，未記錄建立、資料寫入或重新命名。
因此它們可確認中繼資料存取，仍不足以判定 Doppler 的寫入來源或舊目錄可以刪除。

### 建議處理方式

保留三個已部署的 XDG 目錄與權限邊界，先查明舊資料用途。
舊目錄若含獨有設定或仍需保留的憑證，由使用者在獨立 shell 建立私有備份並核對；
資料處置完成後再移除舊入口。將舊設定整批合併到 agent／GUI 隔離目錄會改變其權限範圍。

若要追查重建或寫入來源，使用者可在自己的 shell 執行以下路徑／程序觀察：

```sh
sudo fs_usage -w -f filesys |
  rg --line-buffered '/Users/charles/\.doppler(/|[[:space:]])'
```

在正常使用相關工具時觀察，完成後按 Ctrl-C。只需回傳命中的程序名稱與路徑；
設定檔、token 與快取內容保留在使用者本機。
本輪完成了設定與來源研究，舊目錄的資料處置及歷史寫入者仍需使用者確認。

## `.sigstore`：TFLint 的實作限制

查核 TFLint **0.64.0**，其已安裝 binary metadata 與
[`go.mod:25`][tflint-dependency] 都指向 `sigstore-go v1.2.2`。

[`plugin/install.go:132–141`][tflint-call] 的 attestation 驗證分支會呼叫
`VerifyAttestations`。其
[`plugin/signature.go:12–15,82–88`][tflint-tuf] 實際引用
`github.com/sigstore/sigstore-go/pkg/tuf`，並執行：

```go
client, err := tuf.New(tuf.DefaultOptions())
```

此版本函式庫的
[`pkg/tuf/options.go:130–148`][sigstore-default] 使用 `os.UserHomeDir()`，再設定：

```go
opts.CachePath = filepath.Join(home, ".sigstore", "root")
```

函式庫有 [`options.go:100–104`][sigstore-override] 的 `WithCachePath(path)`，
TFLint 上述呼叫使用預設 options。該完整預設函式沒有 `TUF_ROOT` 或 XDG lookup。
因此在這條已追蹤的驗證流程中，設定 `TUF_ROOT` 無法改變 cache 位置。

本機名稱結構與此實作相符：
[`client.go:38–50,130–137,200–210`][sigstore-layout] 以 cache root 加上移除 URL scheme
後的 repository host，形成 `tuf-repo-cdn.sigstore.dev` 目錄與同名 `.json`。
這證明 TFLint 是能產生此結構的已安裝程式；實際歷史寫入者仍未確定。

適合的上游修改是讓 TFLint 暴露 `WithCachePath` 或採用 XDG cache。
搬移方案應維持既有簽章驗證功能。

## Clop 的兩個固定路徑

查核 Clop **3.4.3**，本機 app 版本及 binary 路徑字串與公開 tag 相符。

### `.well-known/mcp/clop.json`

本機安全中繼資料觀察只看到 `.well-known/mcp/clop.json` 這條路徑。
[`Clop/MCPInstaller.swift:137–145`][clop-card-path] 使用
`FileManager.default.homeDirectoryForCurrentUser`，接上
`.appendingPathComponent(".well-known/mcp/clop.json")`。

[`ClopApp.swift:570–576`][clop-card-startup] 在啟動時無條件呼叫
`MCPInstaller.writeServerCard()`。
[`MCPInstaller.swift:220–227`][clop-card-write] 每次迭代兩個目標：
`supportDirectory.appendingPathComponent("mcp.json")` 與 `cardURL`，建立父目錄並寫入。
因此關閉 MCP 功能仍會保留這個探索檔的寫入行為。

writer 明確呼叫 `resolvedConfigURL`；
[`Clop/JSONCEditor.swift:396–411`][clop-symlinks] 追蹤父目錄與檔案 symlink。
這提供相容的實體搬移途徑，home 仍會有 `.well-known` 入口。

### `.clop-debug-logs`

這是單一檔案。
[`Clop/ClopApp.swift:72–89`][clop-log] 的完整函式設定：

```swift
let path = (NSHomeDirectory() as NSString).appendingPathComponent(".clop-debug-logs")
```

接著用 `FileHandle(forWritingAtPath: path)` 追加，或用
`FileManager.default.createFile(atPath: path, ...)` 建立檔案。
函式內沒有路徑設定、環境變數或停用開關。
[`ClopApp.swift:444–462`][clop-log-caller] 的一般啟動與 license-state observer 都會呼叫它。
單次移除後，下一次適用的寫入仍可重建檔案；完整消除入口需要 Clop 提供設定或修改 writer。

## 驗證與限制

- `tests/apps/xdg-paths.bats` 四項通過：路徑求值、真實 Bashrc 建置、隔離 Bash history 與 Ruff cache。
- 與 `tests/runtime/upstream-binaries.bats` 合併執行共 13 項通過，包含完整 generation 建置。
- Nixfmt、XDG 測試的 ShellCheck、工作樹 whitespace check 通過。
  Runtime 測試的 ShellCheck info 提示與修改前一致：SC2030、SC2031、SC2329。
- 已使用使用者的 Git flake 與 `.local` 主機目標，成功建置完整 `activationPackage`。
- 重跑 xdg-ninja 後，Ruff cache 與 Bash history 兩個舊路徑已不再命中。
- Ego 測試只使用新建的空白頁與暫存狀態，測試空間已關閉。
- 憑證、認證快取、私人 browser state 與 Clop log 內容均未讀取。
- AWS、Terraform、Doppler 的認證資料確認、搬移與登入驗證，依使用者規則由使用者在獨立 shell 執行。

[hm-bash]: https://github.com/nix-community/home-manager/blob/d2a22a3659a6ae99847ea9176114f6957b8ac62e/modules/programs/bash.nix#L249-L289
[hm-mise]: https://github.com/nix-community/home-manager/blob/d2a22a3659a6ae99847ea9176114f6957b8ac62e/modules/programs/mise.nix#L162-L172
[aws-cache]: https://github.com/aws/aws-cli/blob/2.37.4/awscli/customizations/assumerole.py#L4-L49
[aws-sso-alias]: https://github.com/aws/aws-cli/blob/2.37.4/awscli/customizations/sso/utils.py#L35-L36
[aws-sso-cache]: https://github.com/aws/aws-cli/blob/2.37.4/awscli/customizations/sso/__init__.py#L38-L42
[aws-config]: https://github.com/aws/aws-cli/blob/2.37.4/awscli/botocore/configprovider.py#L65-L72
[aws-history-constant]: https://github.com/aws/aws-cli/blob/2.37.4/awscli/customizations/history/constants.py#L15-L18
[aws-history-writer]: https://github.com/aws/aws-cli/blob/2.37.4/awscli/customizations/history/__init__.py#L50-L96
[tf-config-dir]: https://github.com/hashicorp/terraform/blob/v1.16.1/internal/command/cliconfig/cliconfig.go#L98-L101
[tf-home]: https://github.com/hashicorp/terraform/blob/v1.16.1/internal/command/cliconfig/config_unix.go#L25-L43
[tf-config-file]: https://github.com/hashicorp/terraform/blob/v1.16.1/internal/command/cliconfig/cliconfig.go#L402-L443
[tf-config-load]: https://github.com/hashicorp/terraform/blob/v1.16.1/internal/command/cliconfig/cliconfig.go#L121-L138
[tf-checkpoint]: https://github.com/hashicorp/terraform/blob/v1.16.1/checkpoint.go#L26-L60
[tf-credentials-path]: https://github.com/hashicorp/terraform/blob/v1.16.1/internal/command/cliconfig/credentials.go#L29-L107
[tf-credentials-sources]: https://github.com/hashicorp/terraform/blob/v1.16.1/internal/command/cliconfig/credentials.go#L120-L247
[tf-helper]: https://github.com/hashicorp/terraform/blob/v1.16.1/commands.go#L507-L509
[tf-plugins]: https://github.com/hashicorp/terraform/blob/v1.16.1/internal/command/cliconfig/plugins.go#L19-L28
[skills-constants]: https://github.com/vercel-labs/skills/blob/7407f3893ad4dceab546ac002c3ef806e4000c73/src/constants.ts#L1-L3
[skills-root]: https://github.com/vercel-labs/skills/blob/7407f3893ad4dceab546ac002c3ef806e4000c73/src/installer.ts#L128-L131
[skills-copy]: https://github.com/vercel-labs/skills/blob/7407f3893ad4dceab546ac002c3ef806e4000c73/src/installer.ts#L366-L375
[skills-universal]: https://github.com/vercel-labs/skills/blob/7407f3893ad4dceab546ac002c3ef806e4000c73/src/installer.ts#L157-L160
[ego-document]: https://lite.ego.app/document/
[ego-root]: https://github.com/citrolabs/ego-lite/blob/dca7003349c5f7132189ba00547cbbd7ff8e597e/package/ego-browser/src/page-ledger.ts#L81-L85
[ego-lazy]: https://github.com/citrolabs/ego-lite/blob/dca7003349c5f7132189ba00547cbbd7ff8e597e/package/ego-browser/src/page-model.ts#L790-L795
[ego-local-runtime]: https://github.com/citrolabs/ego-lite/blob/dca7003349c5f7132189ba00547cbbd7ff8e597e/docs/local-runtime-development.md#L34-L50
[ego-state-init]: https://github.com/citrolabs/ego-lite/blob/dca7003349c5f7132189ba00547cbbd7ff8e597e/package/ego-browser/src/state.ts#L1-L5
[ego-env]: https://github.com/citrolabs/ego-lite/blob/dca7003349c5f7132189ba00547cbbd7ff8e597e/package/ego-browser/src/env.ts#L1-L42
[ego-native-bindings]: https://github.com/citrolabs/ego-lite/blob/dca7003349c5f7132189ba00547cbbd7ff8e597e/docs/native-bindings-api.md#L3-L9
[ego-ledger-io]: https://github.com/citrolabs/ego-lite/blob/dca7003349c5f7132189ba00547cbbd7ff8e597e/package/ego-browser/src/page-ledger.ts#L430-L478
[ego-instance]: https://github.com/citrolabs/ego-lite/blob/dca7003349c5f7132189ba00547cbbd7ff8e597e/package/ego-browser/src/page-ledger.ts#L49-L54
[ego-ledger-read]: https://github.com/citrolabs/ego-lite/blob/dca7003349c5f7132189ba00547cbbd7ff8e597e/package/ego-browser/src/page-ledger.ts#L364-L390
[doppler-flags]: https://github.com/DopplerHQ/cli/blob/3.76.6/pkg/cmd/root.go#L42-L125
[doppler-dirs]: https://github.com/DopplerHQ/cli/blob/3.76.6/pkg/configuration/config.go#L61-L75
[doppler-fallback]: https://github.com/DopplerHQ/cli/blob/3.76.6/pkg/cmd/run.go#L613-L635
[doppler-metadata]: https://github.com/DopplerHQ/cli/blob/3.76.6/pkg/controllers/fallback.go#L60-L67
[doppler-log]: https://github.com/DopplerHQ/cli/blob/3.76.6/pkg/tui/common/logging.go#L61-L63
[tflint-dependency]: https://github.com/terraform-linters/tflint/blob/v0.64.0/go.mod#L25
[tflint-call]: https://github.com/terraform-linters/tflint/blob/v0.64.0/plugin/install.go#L132-L141
[tflint-tuf]: https://github.com/terraform-linters/tflint/blob/v0.64.0/plugin/signature.go#L12-L88
[sigstore-default]: https://github.com/sigstore/sigstore-go/blob/v1.2.2/pkg/tuf/options.go#L130-L148
[sigstore-override]: https://github.com/sigstore/sigstore-go/blob/v1.2.2/pkg/tuf/options.go#L100-L104
[sigstore-layout]: https://github.com/sigstore/sigstore-go/blob/v1.2.2/pkg/tuf/client.go#L38-L210
[clop-card-path]: https://github.com/FuzzyIdeas/Clop/blob/v3.4.3/Clop/MCPInstaller.swift#L137-L145
[clop-card-startup]: https://github.com/FuzzyIdeas/Clop/blob/v3.4.3/Clop/ClopApp.swift#L570-L576
[clop-card-write]: https://github.com/FuzzyIdeas/Clop/blob/v3.4.3/Clop/MCPInstaller.swift#L220-L227
[clop-symlinks]: https://github.com/FuzzyIdeas/Clop/blob/v3.4.3/Clop/JSONCEditor.swift#L396-L411
[clop-log]: https://github.com/FuzzyIdeas/Clop/blob/v3.4.3/Clop/ClopApp.swift#L72-L89
[clop-log-caller]: https://github.com/FuzzyIdeas/Clop/blob/v3.4.3/Clop/ClopApp.swift#L444-L462
