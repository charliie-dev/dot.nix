# SFM / WARP 維護

這組工具保留既有 SFM 設定、私人 AdGuard DNS、YouTube IPv4 分流與 Tailscale 路由。
`watch.py` 只檢查網路並控制 SFM 服務。帳號更新、私人設定檢查及 Cloudflare 對照測試由使用者在獨立終端執行。

## 重連監控

Home Manager 模組：`modules/platform/services/sfm-warp-watch.nix`。

- 每 60 秒檢查 WARP。
- 底層 Internet 可達且連續 3 次失敗，才嘗試重連。
- 每次重連嘗試之間至少間隔 15 分鐘，包含失敗的重連。
- 離線、服務狀態不明、網路切換及睡眠後的檢查會重設失敗計數。
- 網路變更後保留 60 秒緩衝。
- 透過 `scutil --nc stop/start SFM` 重連，使用 SFM 保存的啟動設定。
- 狀態放在 `$XDG_STATE_HOME/sfm-warp-maintenance`，預設為 `~/.local/state/sfm-warp-maintenance`。

```sh
tools="$HOME/.config/home-manager/conf.d/sfm-warp-maintenance"
python3 -IS "$tools/watch.py" status
python3 -IS "$tools/watch.py" probe
python3 -IS "$tools/watch.py" pause
python3 -IS "$tools/watch.py" resume
```

完整套用 Home Manager 模組後，也會提供 `sfm-watch` 命令。

`pause` 同時阻止帳號更新排程開始新的更新。手動停用 VPN 或開始私人設定測試前，先暫停維護。

## 帳號更新：使用者安裝

在自己的互動式終端執行：

```sh
tools="$HOME/.config/home-manager/conf.d/sfm-warp-maintenance"
python3 -IS "$tools/account_update.py" install
```

安裝時會要求輸入 `INSTALL` 確認。預設使用
`~/.config/sfm-warp/wgcf-account.toml`；其他位置可透過 `--account /absolute/path` 指定。

安裝器會下載官方 wgcf 2.3.0 的 Apple Silicon 執行檔，核對固定 SHA-256，存入
`~/.local/share/sfm-warp-maintenance/wgcf-2.3.0`，並安裝
`~/Library/LaunchAgents/local.sfm-warp-account-update.plist`。
既有異版執行檔或不同的同名排程會使安裝停止。
同名排程已載入時，先由使用者執行下方的 `bootout`，再重新安裝，確保載入參數符合設定。

排程首次載入及每 12 小時檢查一次；最近 12 小時已成功、維護暫停或 HTTPS 不通時略過。
實際命令是 `wgcf --config <帳號檔> update`，可能更新 Cloudflare 帳號／裝置資料及本機帳號檔。
每次執行限時 90 秒，輸出全部隱藏，僅保存成功／失敗狀態與時間。
帳號檔中的設定具有優先權，排程會清除 `WGCF_*` 環境覆寫。

`wgcf update` 的範圍是帳號與裝置資料。這裡使用固定的 wgcf 2.3.0；既有 Topgrade 設定保持原樣。
此專用 wgcf 副本的版本由本工具維護，沒有新增程式升級排程。

讀取非機密更新結果：

```sh
python3 -m json.tool "$HOME/.local/state/sfm-warp-maintenance/account-update.json"
```

`updated` 表示命令成功。`update_failed` 或 `update_timeout` 需要使用者在自己的終端進一步處理；帳號、金鑰或原始命令輸出應留在本機。

暫時卸載帳號排程：

```sh
launchctl bootout "gui/$(id -u)/local.sfm-warp-account-update"
```

保留的 plist 會在下次登入時載入。永久停用時，由使用者將上述專用 plist 移出 `~/Library/LaunchAgents/`。

## 手機熱點設定檢查：使用者執行

在自己的互動式終端執行，結果只包含布林值與設定欄位名稱：

```sh
tools="$HOME/.config/home-manager/conf.d/sfm-warp-maintenance"
python3 -IS "$tools/reserved_probe.py" audit \
  --user-run --profile "$HOME/.config/sfm-warp/warp-tun-youtube-v4.json"
```

預期 `auto_detect_interface`、`default_is_warp`、`lan_direct_rule`、
`youtube_ipv4_direct_rule` 與 `https_dns_present` 為 `true`；
`fixed_dial_field_paths` 為空，`tailnet_overlaps_tun_exclusions` 與
`process_route_overrides_present` 為 `false`。

這是設定檢查。`https_dns_present` 只表示有 HTTPS DNS 伺服器，服務的私人裝置辨識仍需原本的 AdGuard 診斷。
切換手機熱點後，SFM 的網域規則維持原樣；自動介面偵測跟隨底層網路。固定介面／來源位址、行動業者對 UDP 的限制及既有連線中斷，仍可能影響切換結果。
SFM 的 Include All Networks 維持關閉。

## reserved 實測

### 本機封包對照

```sh
python3 "$HOME/.config/home-manager/conf.d/sfm-warp-maintenance/reserved_probe.py"
```

工具下載並核對官方 sing-box 1.14.2，使用公開的合成測試值和 loopback UDP 接收器。
`sing-box format -w` 產生 base64 版本，再建立只差 reserved 表示方式的陣列版本。
順序為陣列、base64、base64、陣列，檢查每個真正送出的 WireGuard 握手起始封包。
此模式的 WireGuard 對端限於 `127.0.0.1`，完全使用合成設定。

### Cloudflare 握手對照：使用者執行

這項測試短暫停用系統 SFM，普通網路會使用底層連線。
先關閉官方 WARP 客戶端的連線，並暫停維護：

```sh
tools="$HOME/.config/home-manager/conf.d/sfm-warp-maintenance"
python3 -IS "$tools/watch.py" pause
```

在 SFM 介面停止服務，再於自己的互動式終端執行：

```sh
tools="$HOME/.config/home-manager/conf.d/sfm-warp-maintenance"
python3 -IS "$tools/reserved_probe.py" cloudflare \
  --user-run --profile "$HOME/.config/sfm-warp/warp-tun-youtube-v4.json"
```

工具要求 SFM 已停止、維護已暫停且直接 Internet 可用。
它會持有重連與帳號更新兩個鎖直到測試結束；已有工作執行時會停止，請恢復 SFM 並稍後再試。
它從指定設定複製單一 WARP endpoint 到權限受限的暫存資料夾，以四輪序列測試兩種表示。
每輪只啟動一個 loopback SOCKS proxy；原始私人設定檔保持原樣。
結果僅包含格式、curl 結束碼及是否取得 WARP 回應。程序結束時清除測試程序與暫存設定。

測試完成或中斷後，在 SFM 介面選擇日常設定並重新啟動，再恢復維護：

```sh
tools="$HOME/.config/home-manager/conf.d/sfm-warp-maintenance"
python3 -IS "$tools/watch.py" resume
python3 -IS "$tools/watch.py" probe
```

Cloudflare 的四輪均成功，才能確認該帳號在當時網路上的完整握手對照。
本機封包相同只支持 reserved 位元組的實際傳輸一致。

## 測試

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/lib/sfm_warp_maintenance.py
bats tests/platform/sfm-warp-maintenance.bats tests/platform/sfm-warp-watch.bats
```

指定已核對的官方 1.14.2 執行檔，可額外執行真正 loopback 封包與錯誤位元組的負向對照：

```sh
SFM_TEST_BINARY=/absolute/path/to/sing-box \
  PYTHONDONTWRITEBYTECODE=1 python3 tests/lib/sfm_warp_maintenance.py
```

合成測試會替換帳號命令與私人檔案輸入；它們不執行真正的帳號更新。
