# Agenix → sops-nix + Doppler 遷移計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 將 secrets 管理從 agenix 遷移到 sops-nix（系統層）+ Doppler（應用層），並加入 `enableSecrets` flag 讓新機器可以先不處理 secrets。同時將 host 定義改為資料驅動，搭配 mise task 自動化新增伺服器流程。

**Architecture:** 系統層 secrets（SSH keys、git config）用 sops-nix 管理，加密後放 repo。應用層 secrets（API keys、tokens）改由 Doppler 管理，deploy 時透過 activation script 拉取。Doppler 的 Service Token 本身由 sops-nix 管理，形成 bootstrap chain。新增 **per-host** `enableSecrets` flag（default `true`），讓新機器首次部署可跳過所有 secrets 處理，不影響其他 host。Secret-dependent config（git signing、ssh identity、zsh env）集中在 `core.nix` 的 `mkMerge` 中條件化，sub-imports（git.nix、ssh.nix、zsh.nix）不需要知道 `enableSecrets`。Host 定義抽成 `hosts.nix` 資料驅動，新增伺服器只需加一筆 entry + 跑 `mise run add-host`。

**Tech Stack:** sops-nix, Doppler CLI (`doppler`), age encryption, Nix/home-manager, mise tasks

---

## File Structure

### 新增
- `conf.d/sops/secrets.yaml` — sops 加密的系統層 secrets（取代 11 個 `.age` 檔）
- `.sops.yaml` — sops creation rules（定義誰能解密）
- `modules/sops.nix` — sops-nix secret 宣告（取代 `modules/agenix.nix`）
- `modules/doppler.nix` — Doppler activation script
- `hosts.nix` — 資料驅動的 host 定義（取代 flake.nix 中的手動 homeConfigurations）

### 修改
- `flake.nix` — 替換 agenix input 為 sops-nix，改用 `hosts.nix` 動態生成 homeConfigurations
- `modules/core.nix` — 改用 sops.nix，加入 doppler.nix，用 `mkMerge` + `mkIf enableSecrets` 集中管理所有 secret-dependent config（sops、doppler、git signing、ssh identity、zsh env、ssh activation）
- `modules/apps/git.nix` — **僅移除** `config.age.secrets.*` 引用（signing config 移到 `core.nix` mkMerge）
- `modules/apps/ssh.nix` — **僅移除** `config.age.secrets.*` 引用（identity config 移到 `core.nix` mkMerge）
- `modules/apps/zsh.nix` — **僅移除** `exportSecret` helper 和相關 envExtra（Doppler env 載入移到 `core.nix` mkMerge）；保留非 secret 的 env vars（`AWS_DEFAULT_OUTPUT`、`AWS_DATA_PATH`）
- `modules/hosts/*.nix` — 移除 agenix overlay/module，加入 sops-nix module（注意：sops-nix 沒有 overlay，只需移除 agenix overlay），傳入 per-host `enableSecrets`
- `mise.toml` — 新增 `add-host` 和 `get-remote-age-pubkey` tasks

### 刪除（最後清理）
- `secrets.nix` — agenix 專用格式，sops 不需要
- `modules/agenix.nix` — 被 `modules/sops.nix` 取代
- `modules/overlays/agenix-wrapper.nix` — agenix CLI wrapper，不再需要
- `conf.d/ages/*.age` — 全部 11 個檔案，secrets 已遷移到 `secrets.yaml`

---

## Secret 分類

### 系統層（sops-nix 管理，放 repo）
| Secret | 原 `.age` 檔 | 理由 |
|---|---|---|
| `ssh_ed25519` | `ssh_ed25519.age` | SSH 私鑰，離線也要能用 |
| `ssh_ed25519_pub` | `ssh_ed25519_pub.age` | SSH 公鑰 |
| `host_configuration` | `host_configuration.age` | SSH host config |
| `allowed_signers` | `allowed_signers.age` | Git signing |

### 應用層（Doppler 管理，不放 repo）
| Secret | 原 `.age` 檔 | 理由 |
|---|---|---|
| `azure_openai_api_endpoint` | `azure_openai_api_endpoint.age` | API config，可能頻繁更新 |
| `azure_openai_api_key` | `azure_openai_api_key.age` | API key |
| `azure_openai_api_version` | `azure_openai_api_version.age` | API version |
| `aws_region` | `aws_region.age` | AWS config |
| `aws_access_key_id` | `aws_access_key_id.age` | AWS credential |
| `aws_secret_access_key` | `aws_secret_access_key.age` | AWS credential |
| `d2_token` | `d2_token.age` | D2 Studio token |

### Bootstrap（sops-nix 管理）
| Secret | 說明 |
|---|---|
| `doppler_token` | Doppler Service Token，用來拉應用層 secrets |

---

## Task 1: 安裝 sops CLI 並建立 `.sops.yaml`

**Files:**
- Create: `~/.config/home-manager/.sops.yaml`

- [ ] **Step 1: 安裝 sops CLI**

```bash
nix profile install nixpkgs#sops
# 或如果你用 brew
brew install sops
```

驗證：
```bash
sops --version
# Expected: sops X.Y.Z
```

- [ ] **Step 2: 建立 `.sops.yaml` creation rules**

```yaml
# .sops.yaml
creation_rules:
  - path_regex: conf\.d/sops/secrets\.yaml$
    age: >-
      age1cc2n5xttywv2t86xmtpkg0fptgfkjflvqxzcrwavmpfjmkfrhsuskdh65q,
      age1c0rk88eall59su5x4vfqrqtqskkdd3qnj5eyd93ve8wa6jmcx3dsmkzdx2,
      age1pzwzf6lqjsjgpys0jlwfc957xewhclfr7hxg5wftky0q4cunwsequqyysa,
      age1hwpy5jpkm6kyvr2apppq5scceu5ypsqa8unptmrzry3pu37swygqcc7ca6,
      age1ma2h46jzrp3ux5gx6ad9l5yap7t60pl2jw0jevd9d6yn7k407yws3ws9sx,
      age10yxsamlz7rtc2lq4g5wtjdhktrycz4hlsyj7hrv86lrqaasumprsaskk0r,
      age1adjpe4mz7sqpq4xcsz9kpss4a5pa906aysk9ldjhc4a35ut5ycrs5f4hmd,
      age1mg3w0fvrcxn5hxea5wljdqshel3l2lykv9l62ux2nfnyt3ck4yzq6jq4v3,
      age19tmhkq52a077pnrhu6svd05vm45wuffxfmkmgzdczgl03f3z5uusde3myg,
      age1qrk5dqfnzhd9sy5ujd0p3q6gky0hztn3mrv5gzcj9yutcdu2552qflgy6s,
      age1a8gvyt8zw5qm0t752cezs5e7dfmymxqlqvw59vgu9kjnhj0aks2q3e937e
```

注意：這裡列出了 `secrets.nix` 中所有 `users` + `hosts` 的 public key。

- [ ] **Step 3: Commit**

```bash
git add .sops.yaml
git commit -m "chore(sops): add .sops.yaml creation rules"
```

---

## Task 2: 建立 sops 加密的 secrets.yaml（系統層 + doppler token）

**Files:**
- Create: `conf.d/sops/secrets.yaml`

- [ ] **Step 1: 建立安全暫存目錄並解密現有 age 檔案**

```bash
cd ~/.config/home-manager
identity=~/.config/age/keys.txt

# 建立權限受限的暫存目錄（防止多用戶系統上的明文洩漏）
TMPDIR=$(mktemp -d)
chmod 700 "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

# 系統層 secrets
age -d -i "$identity" conf.d/ages/ssh_ed25519.age > "$TMPDIR/ssh_ed25519"
age -d -i "$identity" conf.d/ages/ssh_ed25519_pub.age > "$TMPDIR/ssh_ed25519_pub"
age -d -i "$identity" conf.d/ages/host_configuration.age > "$TMPDIR/host_configuration"
age -d -i "$identity" conf.d/ages/allowed_signers.age > "$TMPDIR/allowed_signers"
```

- [ ] **Step 2: 建立 secrets.yaml 明文結構並用 sops 加密**

```bash
mkdir -p conf.d/sops

# 建立明文 YAML（稍後 sops 會加密 values）
cat > "$TMPDIR/secrets-plain.yaml" << 'YAMLEOF'
ssh_ed25519: |
    <paste content of $TMPDIR/ssh_ed25519>
ssh_ed25519_pub: |
    <paste content of $TMPDIR/ssh_ed25519_pub>
host_configuration: |
    <paste content of $TMPDIR/host_configuration>
allowed_signers: |
    <paste content of $TMPDIR/allowed_signers>
doppler_token: ""
YAMLEOF

# 用 sops 加密
export SOPS_AGE_KEY_FILE=~/.config/age/keys.txt
sops -e "$TMPDIR/secrets-plain.yaml" > conf.d/sops/secrets.yaml
```

驗證：
```bash
# 確認可以解密
sops -d conf.d/sops/secrets.yaml
# Expected: 顯示明文 YAML
```

- [ ] **Step 3: 清理暫存明文**

```bash
# trap EXIT 會自動清理 $TMPDIR，但也可以手動清理
rm -rf "$TMPDIR"
```

- [ ] **Step 4: Commit**

```bash
git add conf.d/sops/secrets.yaml
git commit -m "feat(sops): add sops-encrypted system secrets"
```

---

## Task 3: 設定 Doppler 專案並上傳應用層 secrets

**Files:** 無（Doppler 操作在雲端）

- [ ] **Step 1: 安裝 Doppler CLI**

```bash
nix profile install nixpkgs#doppler
# 或
brew install dopplerhq/cli/doppler
```

驗證：
```bash
doppler --version
```

- [ ] **Step 2: 登入 Doppler 並建立專案**

```bash
doppler login
doppler setup
# 建議專案名稱：dotfiles
# 環境：prod
```

- [ ] **Step 3: 上傳應用層 secrets**

```bash
identity=~/.config/age/keys.txt

# 解密每個 age 檔案並上傳到 Doppler
doppler secrets set \
  AZURE_OPENAI_API_ENDPOINT="$(age -d -i "$identity" conf.d/ages/azure_openai_api_endpoint.age)" \
  AZURE_OPENAI_API_KEY="$(age -d -i "$identity" conf.d/ages/azure_openai_api_key.age)" \
  AZURE_OPENAI_API_VERSION="$(age -d -i "$identity" conf.d/ages/azure_openai_api_version.age)" \
  AWS_REGION="$(age -d -i "$identity" conf.d/ages/aws_region.age)" \
  AWS_ACCESS_KEY_ID="$(age -d -i "$identity" conf.d/ages/aws_access_key_id.age)" \
  AWS_SECRET_ACCESS_KEY="$(age -d -i "$identity" conf.d/ages/aws_secret_access_key.age)" \
  TSTRUCT_TOKEN="$(age -d -i "$identity" conf.d/ages/d2_token.age)"
```

驗證：
```bash
doppler secrets
# Expected: 顯示所有 7 個 secrets
```

- [ ] **Step 4: 建立 Service Token 並存入 sops**

```bash
# 建立安全暫存
TMPDIR=$(mktemp -d)
chmod 700 "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

# 建立 machine 用的 service token
doppler configs tokens create \
  --project dotfiles \
  --config prod \
  --name "home-manager" \
  --plain > "$TMPDIR/doppler_token"

# 用 sops 編輯 secrets.yaml，填入 doppler_token
export SOPS_AGE_KEY_FILE=~/.config/age/keys.txt
sops conf.d/sops/secrets.yaml
# 將 doppler_token 欄位的值改為 $TMPDIR/doppler_token 的內容
# 存檔離開
```

- [ ] **Step 5: 清理暫存並 commit**

```bash
rm -rf "$TMPDIR"
git add conf.d/sops/secrets.yaml
git commit -m "feat(doppler): add doppler service token to sops secrets"
```

---

## Task 4: 替換 flake.nix 中的 agenix 為 sops-nix

**Files:**
- Modify: `flake.nix`

- [ ] **Step 1: 更新 inputs**

在 `flake.nix` 的 `inputs` 中：

```nix
# 移除
agenix = {
  url = "github:ryantm/agenix";
  inputs.nixpkgs.follows = "nixpkgs";
  # ...
};

# 新增
sops-nix = {
  url = "github:Mic92/sops-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

- [ ] **Step 2: 更新 base-attr**

```nix
# base-attr 中
# 移除 agenix
# 新增 sops-nix
base-attr = {
  inherit
    catppuccin
    home-manager
    nix-index-database
    nixpkgs
    snitch
    sops-nix  # 取代 agenix
    src
    ;
  hm_ver = "26.05";
};
```

- [ ] **Step 3: 移除此步驟（`enableSecrets` 改為 per-host，在 Task 14 的 `hosts.nix` 中定義）**

`enableSecrets` 不再放在 `base-attr`，改為每個 host 獨立設定，避免新增 host 時影響其他機器。見 Task 14。

- [ ] **Step 4: 更新 flake.lock**

```bash
nix flake lock --update-input sops-nix
# 如果 agenix 還在 inputs 裡會需要先移除再 lock
nix flake update
```

- [ ] **Step 5: Commit**

```bash
git add flake.nix flake.lock
git commit -m "feat(flake): replace agenix with sops-nix, add enableSecrets flag"
```

---

## Task 5: 建立 `modules/sops.nix`（取代 `modules/agenix.nix`）

**Files:**
- Create: `modules/sops.nix`

- [ ] **Step 1: 建立 sops.nix**

```nix
# modules/sops.nix
{ config, src, ... }:
let
  secretDir = "${config.xdg.dataHome}/secrets_output";
in
{
  sops = {
    defaultSopsFile = "${src}/conf.d/sops/secrets.yaml";
    age.keyFile = "${config.xdg.configHome}/age/keys.txt";

    secrets = {
      ssh_ed25519 = {
        path = "${config.home.homeDirectory}/.ssh/id_ed25519";
        mode = "0600";
      };
      ssh_ed25519_pub = {
        path = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
        mode = "0644";
      };
      host_configuration = {
        path = "${config.home.homeDirectory}/.ssh/host_configuration";
      };
      allowed_signers = {
        path = "${config.xdg.configHome}/git/allowed_signers";
      };
      doppler_token = {
        path = "${secretDir}/doppler/token";
        mode = "0400";
      };
    };
  };
}
```

- [ ] **Step 2: Commit**

```bash
git add modules/sops.nix
git commit -m "feat(sops): add sops-nix secret declarations"
```

---

## Task 6: 建立 `modules/doppler.nix`

**Files:**
- Create: `modules/doppler.nix`

- [ ] **Step 1: 建立 doppler.nix**

```nix
# modules/doppler.nix
{ config, pkgs, ... }:
let
  secretDir = "${config.xdg.dataHome}/secrets_output";
  # Hardcode path 而非引用 config.sops.secrets.doppler_token.path
  # 避免 plain function import 中的 circular dependency
  # 此路徑必須與 sops.nix 中 doppler_token 的 path 一致
  dopplerTokenPath = "${secretDir}/doppler/token";
in
{
  doppler = {
    packages = [ pkgs.doppler ];

    # 注意：DAG entry name "setupSecrets" 是 sops-nix home-manager module 的 activation name
    # 如果 sops-nix 版本不同，請用 `grep -r "entryAfter\|entryBefore\|activation" <sops-nix-src>` 確認
    activation = {
      doppler-secrets = config.lib.hm.dag.entryAfter [ "setupSecrets" ] ''
        if [ -r "${dopplerTokenPath}" ]; then
          export DOPPLER_TOKEN="$(cat "${dopplerTokenPath}")"
          mkdir -p "${secretDir}/doppler"
          chmod 700 "${secretDir}/doppler"
          (
            umask 077
            ${pkgs.doppler}/bin/doppler secrets download \
              --project dotfiles \
              --config prod \
              --no-file \
              --format env > "${secretDir}/doppler/env" 2>/dev/null || true
          )
          chmod 600 "${secretDir}/doppler/env"
        fi
      '';
    };
  };
}
```

注意：`dopplerTokenPath` hardcode 為 `${secretDir}/doppler/token`，必須與 `sops.nix` 中 `doppler_token.path` 的定義一致。`umask 077` 用 subshell `(...)` 包裝，避免影響後續 activation。

- [ ] **Step 2: Commit**

```bash
git add modules/doppler.nix
git commit -m "feat(doppler): add doppler activation script"
```

---

## Task 7: 更新 `modules/core.nix` — 加入 enableSecrets 條件

**Files:**
- Modify: `modules/core.nix`

- [ ] **Step 1: 加入 `enableSecrets` 參數並條件化 secrets 相關 import**

在 `core.nix` 的函式簽名中加入 `enableSecrets ? false`：

```nix
{ config, pkgs, lib, src, roles ? [], enableSecrets ? false, ... }:
```

- [ ] **Step 2: 將所有 secret-dependent config 集中在 `mkMerge` + `mkIf enableSecrets`**

**設計原則：** `git.nix`、`ssh.nix`、`zsh.nix` 等 sub-imports 是 plain function import，不接收 `enableSecrets`。所有 secret-dependent 設定（sops、doppler、git signing、ssh identity、zsh doppler env、ssh activation）統一在 `core.nix` 的 `mkIf` block 中 overlay。

原本 agenix 的 import 方式：
```nix
inherit (import "${src}/modules/agenix.nix" { inherit config src; }) age;
```

改為：
```nix
# 移除上面那行，改用 mkMerge + mkIf
```

在 module 的最外層 return 使用 `lib.mkMerge`：

```nix
lib.mkMerge [
  {
    # 所有原本的 config（programs, home.packages, activation 等）
    # 不包含 age = { ... }; 那段
    # git.nix / ssh.nix / zsh.nix 照常 import，但移除其中的 config.age.secrets.* 引用
  }
  (lib.mkIf enableSecrets (
    let
      sopsConfig = import "${src}/modules/sops.nix" { inherit config src; };
      dopplerConfig = import "${src}/modules/doppler.nix" { inherit config pkgs; };
    in
    {
      # sops-nix 設定
      inherit (sopsConfig) sops;

      # Doppler CLI + activation
      home.packages = dopplerConfig.doppler.packages;
      home.activation = dopplerConfig.doppler.activation;

      # Git signing（原本在 git.nix，移到這裡集中管理）
      programs.git.signing.key = "${config.sops.secrets.ssh_ed25519_pub.path}";
      programs.git.extraConfig.gpg.ssh.allowedSignersFile = "${config.sops.secrets.allowed_signers.path}";

      # SSH identity（原本在 ssh.nix，移到這裡）
      programs.ssh.matchBlocks."*".identityFile = "${config.sops.secrets.ssh_ed25519.path}";

      # Zsh: 載入 Doppler secrets env（原本在 zsh.nix 的 exportSecret）
      programs.zsh.envExtra = ''
        # Load Doppler secrets (application-layer)
        if [ -r "${config.xdg.dataHome}/secrets_output/doppler/env" ]; then
          set -a
          source "${config.xdg.dataHome}/secrets_output/doppler/env"
          set +a
        fi
      '';

      # SSH activation: 加入 authorized_keys（加 file existence guard）
      # 注意：必須從 base block 中移除 home.activation.ssh，否則 mkMerge 會因同名 DAG entry 衝突
      home.activation.ssh = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
        if [ -f "${config.home.homeDirectory}/.ssh/id_ed25519.pub" ]; then
          # ... 原本的 ssh activation 邏輯，加了 file existence guard ...
          (cat ${config.home.homeDirectory}/.ssh/id_ed25519.pub) >> ${config.home.homeDirectory}/.ssh/authorized_keys
        fi
      '';
    }
  ))
]
```

**重要注意事項：**
- **`home.activation.ssh` 必須從 base block 完全移除**，只放在 `mkIf` block 中。mkMerge 對同名 DAG entry 會衝突，不會覆蓋
- `home.activation.sshDirectory`（建立 `~/.ssh` + chmod 700）保留在 base block，因為所有機器都需要
- `programs.zsh.envExtra` 的型態是 `types.lines`，mkMerge 會 **串接**（concat），不會覆蓋 — base block 的非 secret env vars 和 mkIf block 的 Doppler env 會合併
- `programs.git.signing` 在 mkMerge 中會 overlay 到 git.nix 定義的基礎 git config 之上

- [ ] **Step 3: Commit**

```bash
git add modules/core.nix
git commit -m "feat(core): conditionally load sops/doppler based on enableSecrets"
```

---

## Task 8: 更新 host files — 替換 agenix module 為 sops-nix

**Files:**
- Modify: `modules/hosts/m3pro.nix`
- Modify: `modules/hosts/callisto.nix`
- Modify: `modules/hosts/pluto.nix`
- Modify: `modules/hosts/x86-vps.nix`
- Modify: `modules/hosts/x86-vps-gpu.nix`

- [ ] **Step 1: 更新每個 host file 的 overlays 和 modules**

在每個 host file 中：

```nix
# 移除（sops-nix 沒有 overlay，直接刪除整個 agenix overlay block）
overlays = [
  agenix.overlays.default                                              # 刪除
  (import "${src}/modules/overlays/agenix-wrapper.nix" { inherit agenix; })  # 刪除
];
# 如果 overlays 清空了，也移除 overlays 本身

# modules 中移除
agenix.homeManagerModules.default

# modules 中新增
sops-nix.homeManagerModules.sops
```

- [ ] **Step 2: 更新 extraSpecialArgs 傳入 per-host enableSecrets**

`enableSecrets` 不再從 `base-attr` 取，而是從 `hosts.nix` 的 per-host 定義傳入（見 Task 14）。
暫時可以先 hardcode `true`，等 Task 14 完成後再改為動態傳入：

```nix
extraSpecialArgs = {
  inherit src;
  roles = [ ... ];
  enableSecrets = true;  # Task 14 完成後改為從 hosts.nix 讀取
};
```

- [ ] **Step 3: 更新 function 簽名**

每個 host file 的函式簽名，將 `{ base-attr }:` 中的 `agenix` 替換為 `sops-nix`：

```nix
# 確保 base-attr 中的 sops-nix 能被解構出來
let
  inherit (base-attr) sops-nix catppuccin home-manager ...;
in
```

- [ ] **Step 4: 對每個 host file 重複以上步驟**

需要修改的 host files：
- `m3pro.nix`
- `callisto.nix`
- `pluto.nix`
- `x86-vps.nix`
- `x86-vps-gpu.nix`

- [ ] **Step 5: Commit**

```bash
git add modules/hosts/
git commit -m "feat(hosts): replace agenix with sops-nix module"
```

---

## Task 9: 移除 sub-imports 中的 agenix 引用

**Files:**
- Modify: `modules/apps/git.nix`
- Modify: `modules/apps/ssh.nix`

**設計原則：** Secret-dependent config（signing key、allowedSignersFile、identityFile）已移到 `core.nix` 的 `mkIf enableSecrets` block 中（Task 7）。這些 sub-import 只需要**移除** agenix 引用，不需要加入 sops 引用或 `enableSecrets` 邏輯。

- [ ] **Step 1: 更新 git.nix — 移除 secret-dependent 設定**

```nix
# 刪除這兩行（已移到 core.nix 的 mkIf block）
gpg.ssh.allowedSignersFile = "${config.age.secrets.git_allowed_signers.path}";
signing.key = "${config.age.secrets.ssh_ed25519_pub.path}";
```

其他 git 設定（userName、userEmail、delta 等）保持不變。

- [ ] **Step 2: 更新 ssh.nix — 移除 secret-dependent 設定**

```nix
# 刪除這行（已移到 core.nix 的 mkIf block）
matchBlocks."*".identityFile = "${config.age.secrets.ssh_ed25519.path}";
```

其他 SSH 設定保持不變。

- [ ] **Step 3: Commit**

```bash
git add modules/apps/git.nix modules/apps/ssh.nix
git commit -m "refactor(apps): remove agenix references from git and ssh (moved to core.nix)"
```

---

## Task 10: 移除 zsh.nix 中的 agenix 引用

**Files:**
- Modify: `modules/apps/zsh.nix`

**設計原則：** Doppler env 載入已移到 `core.nix` 的 `mkIf enableSecrets` block（Task 7）。`zsh.nix` 只需移除 `exportSecret` helper 和相關的 agenix `envExtra`。非 secret 的 env vars 必須保留。

- [ ] **Step 1: 移除 `exportSecret` helper 和 agenix envExtra**

```nix
# 刪除 exportSecret 函式定義
# 刪除所有 exportSecret { secret = "..."; env = "..."; } 呼叫

# 保留非 secret 的 env vars（這些不受 enableSecrets 影響）：
envExtra = ''
  export AWS_DEFAULT_OUTPUT="json"
  export AWS_DATA_PATH="${config.xdg.dataHome}/aws"
'';
# Doppler env 載入由 core.nix mkMerge 附加，zsh.nix 不需要處理
```

- [ ] **Step 2: Commit**

```bash
git add modules/apps/zsh.nix
git commit -m "refactor(zsh): remove agenix exportSecret (moved to core.nix doppler integration)"
```

---

## Task 11: 本地驗證

**Files:** 無修改

- [ ] **Step 1: 驗證 sops 解密正常**

```bash
export SOPS_AGE_KEY_FILE=~/.config/age/keys.txt
sops -d conf.d/sops/secrets.yaml | head -5
# Expected: 顯示 ssh_ed25519 等明文內容
```

- [ ] **Step 2: Dry-run home-manager switch（enableSecrets = true）**

```bash
home-manager build --flake .#charles@m3pro
# Expected: build 成功，無 agenix 相關錯誤
```

- [ ] **Step 3: 實際 switch**

```bash
home-manager switch --flake .#charles@m3pro
```

驗證：
```bash
# SSH key 存在
ls -la ~/.ssh/id_ed25519
# Expected: -rw------- ... id_ed25519

# Doppler secrets 已載入
cat ~/.local/share/secrets_output/doppler/env
# Expected: KEY=VALUE 格式的 secrets

# 環境變數可用（開新 shell）
echo $AZURE_OPENAI_API_KEY
# Expected: 非空值
```

- [ ] **Step 4: 測試 enableSecrets = false**

暫時將 `flake.nix` 中 `enableSecrets` 改為 `false`：

```bash
home-manager build --flake .#charles@m3pro
# Expected: build 成功，跳過所有 secrets
```

改回 `true` 後繼續。

- [ ] **Step 5: Commit（如有修正）**

```bash
git add -A
git commit -m "fix: address issues found during local verification"
```

---

## Task 12: 清理 agenix 遺留

**Files:**
- Delete: `secrets.nix`
- Delete: `modules/agenix.nix`
- Delete: `modules/overlays/agenix-wrapper.nix`
- Delete: `conf.d/ages/*.age`（11 個檔案）

- [ ] **Step 1: 確認所有 host 都能正常 build**

```bash
# 至少測試主要 host
home-manager build --flake .#charles@m3pro
```

- [ ] **Step 2: 移除 agenix 相關檔案**

```bash
rm secrets.nix
rm modules/agenix.nix
rm modules/overlays/agenix-wrapper.nix
rm conf.d/ages/*.age
rmdir conf.d/ages
```

- [ ] **Step 3: 從 flake.nix 移除 agenix input（如果 Task 4 還沒完全移除）**

確認 `flake.nix` 中沒有任何 `agenix` 引用。

```bash
grep -r "agenix" --include="*.nix" .
# Expected: 無結果
```

- [ ] **Step 4: 最終 build 驗證**

```bash
home-manager build --flake .#charles@m3pro
# Expected: 成功
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove agenix and legacy .age files"
```

---

## Task 13: 更新文件和 nix-filter

**Files:**
- Modify: `flake.nix`（nix-filter includes）
- Modify: `README.md`（如需要）

- [ ] **Step 1: 更新 nix-filter**

在 `flake.nix` 的 `src` 定義中，確認 `conf.d/sops/` 被包含、`conf.d/ages/` 被移除：

```nix
src = nix-filter.lib {
  root = ./.;
  include = [
    "conf.d"       # 如果是整個 conf.d 就不用改
    "modules"
    "flake.nix"
  ];
};
```

- [ ] **Step 2: Commit**

```bash
git add flake.nix
git commit -m "chore: update nix-filter for sops migration"
```

---

## Task 14: 建立 `hosts.nix` 資料驅動 host 定義

**Files:**
- Create: `hosts.nix`
- Modify: `flake.nix`

- [ ] **Step 1: 分析現有 host 定義，建立 `hosts.nix`**

根據 `flake.nix` 中現有的 `homeConfigurations`，整理出所有 host 的屬性。

```nix
# hosts.nix — 所有 host 定義集中管理
# enableSecrets 為 per-host 設定，新機器首次部署設為 false
{
  "charles@m3pro" = {
    system = "aarch64-darwin";
    hostFile = ./modules/hosts/m3pro.nix;
    enableSecrets = true;
  };
  "charles@callisto" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/callisto.nix;
    enableSecrets = true;
  };
  "charles@pluto" = {
    system = "aarch64-linux";
    hostFile = ./modules/hosts/pluto.nix;
    enableSecrets = true;
  };
  "charles@RDSrv01" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/x86-vps.nix;
    enableSecrets = true;
  };
  "charles@nics-demo-lab" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/x86-vps.nix;
    enableSecrets = true;
  };
  "charles@nate-test" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/x86-vps.nix;
    enableSecrets = true;
  };
  "charles@tmp-gpu" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/x86-vps-gpu.nix;
    gpu = true;
    enableSecrets = true;
  };
  "charles@testvm" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/x86-vps.nix;
    enableSecrets = true;
  };
  "charles@pg-proxy-dev" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/x86-vps.nix;
    enableSecrets = true;
  };
  "charles@pg-primary-dev" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/x86-vps.nix;
    enableSecrets = true;
  };
  "charles@pg-replica1-dev" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/x86-vps.nix;
    enableSecrets = true;
  };
  "charles@pg-replica2-dev" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/x86-vps.nix;
    enableSecrets = true;
  };
  # 新機器範例：
  # "charles@new-server" = {
  #   system = "x86_64-linux";
  #   hostFile = ./modules/hosts/x86-vps.nix;
  #   enableSecrets = false;  # 首次部署後改為 true
  # };
}
```

注意：`hosts.nix` 僅作為 lookup table（system、hostFile、enableSecrets、gpu）。Host 的詳細設定（roles、targets、news.display、homeDirectory 等）仍由各 host file 自行管理。

> **既有 Bug：`x86-vps-gpu.nix` 與 `gpu-attr` 結構不匹配**
> 現有 `x86-vps-gpu.nix` 用 `inherit (gpu-attr) agenix catppuccin hm_ver ...` 存取 `gpu-attr` 的 flat key，但 `gpu-attr` 實際結構是 nested `{ base-attr, nixgl }`。這些 key 在 `gpu-attr.base-attr` 裡，不在頂層。
> **在開始遷移前**，先修正 `x86-vps-gpu.nix`：`inherit (gpu-attr)` → `inherit (gpu-attr.base-attr)`，`gpu-attr.home-manager` → `gpu-attr.base-attr.home-manager`。並驗證 `home-manager build --flake .#charles@tmp-gpu` 能成功。

- [ ] **Step 2: 修改 `flake.nix` 使用 `hosts.nix` 動態生成 homeConfigurations**

```nix
# flake.nix outputs 中
let
  hosts = import ./hosts.nix;
  base-attr = { ... };  # 同 Task 4（不含 enableSecrets）
  gpu-attr = { ... };   # 同現有

  mkHost = name: hostCfg:
    let
      # 注意：傳入的參數名稱必須匹配 host file 的函式簽名
      # host file 接收 { base-attr } 或 { gpu-attr }，不是 { attr }
      # gpu-attr 是 nested 結構 { base-attr, nixgl }，enableSecrets 需注入 base-attr 內部
      enableSecrets = hostCfg.enableSecrets or true;
      hostArgs = if hostCfg.gpu or false
        then { gpu-attr = gpu-attr // {
                 base-attr = gpu-attr.base-attr // { inherit enableSecrets; };
               }; }
        else { base-attr = base-attr // { inherit enableSecrets; }; };
    in
      (import hostCfg.hostFile hostArgs).host;
in
{
  homeConfigurations = builtins.mapAttrs mkHost hosts;
}
```

注意：`enableSecrets` 透過 `base-attr` / `gpu-attr` 傳入 host file，host file 再透過 `extraSpecialArgs` 傳給 `core.nix`。

- [ ] **Step 2.1: 更新所有 host files 的 `extraSpecialArgs` 加入 `enableSecrets`**

每個 host file 都需要從 `base-attr`（或 `gpu-attr.base-attr`）取出 `enableSecrets` 並傳遞：

```nix
# modules/hosts/m3pro.nix, callisto.nix, pluto.nix, x86-vps.nix:
extraSpecialArgs = {
  inherit src;
  inherit (base-attr) enableSecrets;  # 加入這行
  roles = [ ... ];
};

# modules/hosts/x86-vps-gpu.nix:
extraSpecialArgs = {
  inherit src;
  inherit (gpu-attr.base-attr) enableSecrets;  # gpu-attr 是 nested
  roles = [ ... ];
};
```

- [ ] **Step 3: 驗證所有 host 仍能正常 build**

```bash
home-manager build --flake .#charles@m3pro
# Expected: 成功，行為與重構前完全一致
```

- [ ] **Step 4: Commit**

```bash
git add hosts.nix flake.nix
git commit -m "refactor(flake): data-driven host definitions via hosts.nix"
```

---

## Task 15: 建立 mise task — `get-remote-age-pubkey`

**Files:**
- Modify: `mise.toml`

- [ ] **Step 1: 新增 `get-remote-age-pubkey` task**

在 `mise.toml` 中新增：

```toml
[tasks.get-remote-age-pubkey]
description = "Get or generate age public key from remote host"
usage = '''
arg "<hostname>" help="Remote hostname (SSH reachable)"
'''
run = '''
#!/usr/bin/env bash
set -euo pipefail

HOST="${usage_hostname?}"
KEY_DIR=".config/age"
KEY_FILE="$KEY_DIR/keys.txt"

echo "[INFO] Checking age key on ${HOST}..."

# 檢查遠端是否有 age CLI
ssh "$HOST" "command -v age-keygen >/dev/null 2>&1" || {
  echo "[ERROR] age is not installed on ${HOST}. Install it first:"
  echo "  ssh ${HOST} 'sudo apt install -y age'  # or: nix profile install nixpkgs#age"
  exit 1
}

# 檢查遠端是否已有 age key，沒有就生成
PUBKEY=$(ssh "$HOST" "
  if [ ! -f ~/$KEY_FILE ]; then
    echo '[INFO] No age key found, generating...' >&2
    mkdir -p ~/$KEY_DIR
    age-keygen -o ~/$KEY_FILE 2>&1 | grep 'public key:' | awk '{print \$NF}'
  else
    echo '[INFO] Age key already exists.' >&2
    age-keygen -y ~/$KEY_FILE
  fi
")

echo "[OK] Remote age public key for ${HOST}:"
echo "$PUBKEY"
'''
```

- [ ] **Step 2: 驗證 task 可執行**

```bash
# 用一台已有的伺服器測試（不會覆蓋既有 key）
mise run get-remote-age-pubkey testvm
# Expected: 顯示 age1xxxxx... public key
```

- [ ] **Step 3: Commit**

```bash
git add mise.toml
git commit -m "feat(mise): add get-remote-age-pubkey task"
```

---

## Task 16: 建立 mise task — `add-host`

**Files:**
- Modify: `mise.toml`

- [ ] **Step 1: 新增 `add-host` task**

在 `mise.toml` 中新增：

```toml
[tasks.add-host]
description = "Add a new host: get remote age key, update .sops.yaml, rekey, add to hosts.nix"
usage = '''
arg "<hostname>" help="Remote hostname (SSH reachable)"
arg "<system>" help="Nix system (e.g. x86_64-linux, aarch64-linux)" default="x86_64-linux"
arg "<host_file>" help="Host nix file path relative to repo root" default="./modules/hosts/x86-vps.nix"
'''
depends = ["get-remote-age-pubkey {{arg(name='hostname')}}"]
run = '''
#!/usr/bin/env bash
set -euo pipefail

HOST="${usage_hostname?}"
SYSTEM="${usage_system?}"
HOST_FILE="${usage_host_file?}"
SOPS_FILE=".sops.yaml"
SECRETS_FILE="conf.d/sops/secrets.yaml"
HOSTS_FILE="hosts.nix"

# 1. 取得遠端 age public key
echo "[INFO] Fetching age public key from ${HOST}..."
AGE_KEY=$(ssh "$HOST" "age-keygen -y ~/.config/age/keys.txt")
echo "[OK] Got: $AGE_KEY"

# 2. 檢查是否已在 .sops.yaml 中
if grep -q "$AGE_KEY" "$SOPS_FILE"; then
  echo "[SKIP] Key already in $SOPS_FILE"
else
  echo "[INFO] Adding key to $SOPS_FILE..."
  # 在 age: block 的最後一個 key 後面加入新 key
  # 找到最後一個 age1 開頭的行，在其後插入
  sed -i '' "/^      age1.*$/{
    # 讀到最後一個 age key 時
    \$a\\
      ${AGE_KEY}
  }" "$SOPS_FILE"
  # 注意：sed 可能不夠精確，建議手動確認或用更好的 YAML 工具
  echo "[WARN] Please verify $SOPS_FILE manually — sed-based YAML editing is fragile"
fi

# 3. Rekey sops secrets
echo "[INFO] Rekeying secrets..."
export SOPS_AGE_KEY_FILE=~/.config/age/keys.txt
sops updatekeys "$SECRETS_FILE"

# 4. 檢查 hosts.nix 是否已有此 host
if grep -q "\"charles@${HOST}\"" "$HOSTS_FILE"; then
  echo "[SKIP] charles@${HOST} already in $HOSTS_FILE"
else
  echo "[INFO] Adding charles@${HOST} to $HOSTS_FILE..."
  # 在 hosts.nix 的倒數第二行（closing brace 之前）插入
  # enableSecrets = false：新機器首次部署先跳過 secrets
  sed -i '' "/^}$/i\\
\\  \"charles@${HOST}\" = {\\
\\    system = \"${SYSTEM}\";\\
\\    hostFile = ${HOST_FILE};\\
\\    enableSecrets = false;\\
\\  };
" "$HOSTS_FILE"
  echo "[WARN] Please verify $HOSTS_FILE manually"
fi

echo ""
echo "=== Summary ==="
echo "Host:       charles@${HOST}"
echo "System:     ${SYSTEM}"
echo "Host file:  ${HOST_FILE}"
echo "Age key:    ${AGE_KEY}"
echo ""
echo "Next steps:"
echo "  1. Verify .sops.yaml and hosts.nix are correct"
echo "  2. git add .sops.yaml $SECRETS_FILE $HOSTS_FILE"
echo "  3. git commit -m 'feat(host): add ${HOST}'"
echo "  4. git push"
echo "  5. On ${HOST}: home-manager switch --flake .#charles@${HOST}"
'''
```

- [ ] **Step 2: 端到端測試（dry run）**

先在一台已知的伺服器上測試，確認流程正確：

```bash
mise run add-host testvm x86_64-linux ./modules/hosts/x86-vps.nix
# Expected:
#   - 取得 testvm 的 age public key
#   - .sops.yaml 已有此 key → SKIP
#   - hosts.nix 已有此 host → SKIP
#   - 顯示 summary
```

- [ ] **Step 3: Commit**

```bash
git add mise.toml
git commit -m "feat(mise): add add-host task for automated host onboarding"
```

---

## 新機器部署流程（完成遷移後）

### 自動化方式（推薦）

```bash
# 前提：新伺服器已能 SSH 連入、已安裝 age CLI

# 1️⃣ 在本機跑 mise task（自動取得 key、更新設定、rekey）
#    add-host 會自動在 hosts.nix 中設定 enableSecrets = false
cd ~/.config/home-manager
mise run add-host new-server x86_64-linux ./modules/hosts/x86-vps.nix

# 2️⃣ 確認變更、commit、push
git diff  # 檢查 .sops.yaml, hosts.nix, secrets.yaml
git add .sops.yaml conf.d/sops/secrets.yaml hosts.nix
git commit -m "feat(host): add new-server"
git push

# 3️⃣ 在新伺服器上首次部署（enableSecrets = false，已在 hosts.nix 中設定）
home-manager switch --flake .#charles@new-server
# → 安裝所有工具，跳過 secrets（不影響其他 host）

# 4️⃣ 在本機：改 hosts.nix 中 new-server 的 enableSecrets = true
#    commit && push

# 5️⃣ 在新伺服器上再次部署
home-manager switch --flake .#charles@new-server
# → sops 解密 + doppler 拉 secrets → 完成
```

### 手動方式

```bash
# 1️⃣ SSH 到新伺服器，生成 age key
ssh new-server
age-keygen -o ~/.config/age/keys.txt
# 記下 public key: age1xxxxx...

# 2️⃣ 在本機加入新 host
#    a. 編輯 .sops.yaml，加入 public key
#    b. sops updatekeys conf.d/sops/secrets.yaml
#    c. 編輯 hosts.nix，加入 host entry（enableSecrets = false）
#    d. git commit && git push

# 3️⃣ 在新伺服器上首次部署（跳過 secrets）
home-manager switch --flake .#charles@new-server

# 4️⃣ 在本機改 hosts.nix 中 enableSecrets = true，commit && push

# 5️⃣ 在新伺服器上再次部署
home-manager switch --flake .#charles@new-server
```
