---
name: container-security
description: Apply container security and hardening best practices based on 11notes/RTFM. Use this skill WHENEVER the user asks whether a container setup is safe or how to harden it — running as root, dropping capabilities (cap_drop), no-new-privileges, privileged containers, read-only rootfs, Docker socket safety (mounting /var/run/docker.sock, the ":ro makes it safe" myth, socket-proxy), PUID/PGID vs true rootless, distroless-for-security, or securely mounting volumes. Triggers even on a bare "is this secure?" or "how do I lock this down?" about a container, Dockerfile, or compose stack. Covers both Dockerfile and Docker Compose security settings. NOT for authoring a fresh Dockerfile from scratch (use dockerfile-builder) or a general non-security compose cleanup (use compose-lint); also out of scope: image CVE scanning (trivy), host firewall rules, and Kubernetes RBAC/secrets.
---

# Container Security Skill

> 原則來源：[11notes/RTFM](https://github.com/11notes/RTFM)

## Reference Files

按需載入，不要全部預先讀取：

| 檔案 | 何時讀取 |
| ---- | -------- |
| `references/rootless.md` | 解釋 rootless 概念、為何 PUID/PGID 不夠、caps 詳情 |
| `references/distroless.md` | 解釋 distroless 概念、eStargz 比較、limitations |
| `references/socket.md` | 深入解釋 Docker socket 風險、`:ro` 誤解 |
| `references/volumes.md` | 深入解釋 named volumes vs bind mounts、NFS/CIFS/S3 範例 |
| `references/daemon.md` | 深入解釋 daemon.json 各設定的意義 |
| `references/custom.md` | 解釋為何自建 image 而非提 PR |

---

## 核心哲學

- **最小攻擊面 + 最低權限** = 大多數自動化攻擊直接失效
- **永遠不要信任預設值**：distro 和 Docker 的預設設定無法涵蓋個別安裝的複雜性
- **安全是多層拼圖**：rootless、distroless、socket-proxy、resource limits 各自獨立但互相疊加
- 以上原則不限於 Docker，同樣適用於 Podman、containerd 等所有 OCI 相容 runtime

---

## 1. Rootless 容器

> **Docker rootless mode vs image rootless**：若 Docker daemon 本身以 rootless mode 運行（`dockerd-rootless`），以下風險不適用。本章節針對**以一般 root daemon 方式執行 Docker** 的情境。

**常見誤解**：很多 image 用 `PUID`/`PGID` 看起來像 rootless，但 entrypoint 仍以 root 啟動再 `su`/`gosu` 降權。真正的 rootless 是 process 從頭到尾不以 root 跑。

### Dockerfile 做法
```dockerfile
RUN addgroup -g 1000 app && adduser -u 1000 -G app -s /bin/sh -D app
USER 1000:1000
```

### Compose 做法
```yaml
services:
  myapp:
    user: "1000:1000"
    security_opt:
      - no-new-privileges=true
```

動態 UID/GID：
```yaml
services:
  myapp:
    user: "${UID}:${GID}"
```

> **11notes images 的預設 UID/GID 是 `1000:1000`**。使用 11notes 官方 images 時，確保 volume 的 ownership 設為此值，或透過動態 UID/GID 覆蓋。

---

## 2. Distroless Images

**原則**：image 裡只放應用程式需要的東西。沒有 shell、沒有 curl、沒有 wget，攻擊者拿到 RCE 也無法下載 payload。

### 推薦 base images
| 用途 | Base image |
| ------ | ----------- |
| 靜態編譯的 Go/Rust | `gcr.io/distroless/static-debian12` |
| 動態連結 (glibc) | `gcr.io/distroless/base-debian12` |
| Java | `gcr.io/distroless/java21-debian12` |
| Python（有限制） | `gcr.io/distroless/python3-debian12` |
| 輕量但有 shell | `docker.io/library/alpine:3.21` |

### 不適合 distroless 的情境
- Python app 大量動態載入套件
- Node.js / Deno 有動態載入 library
- .NET Core 使用 inline Assembly
→ 這些改用 Alpine，移除不必要的工具套件

除錯 distroless 容器（無 shell）：讀 `references/distroless.md`。

---

## 3. Docker Socket 安全

**核心風險**：任何能存取 `/var/run/docker.sock` 的程式，不需任何驗證即可完全控制 Docker daemon。

**常見誤解**：掛載 socket 加 `:ro` 旗標「唯讀比較安全」— **錯誤**。`:ro` 只是讓容器不能刪除或重命名 socket 檔案本身，對 Docker API 操作完全無影響。

Portainer、Dockge、Komodo 等工具**必須**要求完整的 socket 存取才能運作。**若重視安全性，應避免使用這類工具。**

### 正確做法：socket-proxy
```yaml
services:
  socket-proxy:
    image: docker.io/11notes/socket-proxy:latest
    container_name: socket-proxy
    environment:
      EVENTS: 1
      PING: 1
      CONTAINERS: 1
      VERSION: 1
      INFO: 1
      IMAGES: 1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - socket-proxy
    restart: unless-stopped
    read_only: true
    tmpfs:
      - /run
    security_opt:
      - no-new-privileges=true

  myapp:
    environment:
      DOCKER_HOST: tcp://socket-proxy:2375
    networks:
      - socket-proxy

networks:
  socket-proxy:
    internal: true
```

常用 endpoint 變數（預設 1 代表開啟）：`EVENTS`、`PING`（預設開）；`CONTAINERS`、`IMAGES`、`INFO`、`VERSION`、`NETWORKS`、`VOLUMES`（預設關）；`POST` 允許寫入操作（start/stop/pull 等）。

> **警告**：socket-proxy 的 port 2375 **絕對不能暴露到公網**。

---

## 4. Named Volumes vs Bind Mounts

**原則**：如果想要 Infrastructure as Code，就必須用 named volumes，不能用 bind mounts。

| 比較項目 | Named Volume | Bind Mount | Tmpfs |
| --------- | ------------- | ------------ | ------- |
| 目錄自動建立 | ✅ | ❌ 需手動建立 | ✅ |
| 權限管理 | ✅ 繼承 parent 目錄 | ❌ 需手動 chown | ✅ |
| Compose 自包含 | ✅ | ❌ 依賴 host 路徑 | ✅ |
| Storage backend | NFS/CIFS/S3/local | 只有 host 路徑 | RAM/swap |
| Quota 限制 | ✅ 可在 compose 定義 | ❌ 需 host 層設定 | ✅ |

Named volume storage backend 範例（詳細說明讀 `references/volumes.md`）：
```yaml
volumes:
  app-data:
    driver_opts:
      type: "nfs"
      o: "addr=192.168.1.30,nolock,soft,nfsvers=4"
      device: ":/volume1/containers/myapp/data"
```

---

## 5. UID/GID 變更：Init Container 模式

```yaml
services:
  init-permissions:
    image: docker.io/library/alpine:3.21
    command: chown -R 1000:1000 /data
    volumes:
      - app-data:/data
    restart: "no"

  myapp:
    image: some/image
    user: "1000:1000"
    depends_on:
      init-permissions:
        condition: service_completed_successfully
    volumes:
      - app-data:/data
    tmpfs:
      - /tmp:uid=1000,gid=1000

volumes:
  app-data:
```

---

## 6. Inline Config 模式

把 config 內容直接寫成 env var，entrypoint 在啟動時寫入檔案：

```yaml
services:
  adguard:
    image: docker.io/11notes/adguard-home:latest
    environment:
      ADGUARD_CONFIG: |
        http:
          address: 0.0.0.0:3000
        users:
          - name: admin
            password: ${ADGUARD_PASSWORD}
        dns:
          upstream_dns:
            - 1.1.1.1
            - 8.8.8.8
    env_file:
      - .env
    read_only: true
    security_opt:
      - no-new-privileges=true
```

> **搭配 `read_only: true`**：必須為 config 寫入路徑掛載 `tmpfs`，否則 entrypoint 無法寫入 config 檔。

---

## 7. Docker Daemon 硬化（daemon.json）

```json
{
  "hosts": ["unix:///run/docker.sock"],
  "data-root": "/opt/docker",
  "storage-driver": "overlay2",
  "storage-opts": ["overlay2.size=4G"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "1", "env": "os,customer" },
  "bip": "169.254.253.254/23",
  "fixed-cidr": "169.254.252.0/23",
  "default-address-pools": [{ "base": "169.254.2.0/23", "size": 28 }],
  "mtu": 9000,
  "dns": ["1.1.1.1", "8.8.8.8"],
  "registry-mirrors": ["https://your-mirror.domain.com"]
}
```

重點：`log-opts.env` 是「要附加到 log 的 env key 清單」（逗號分隔，另有 `env-regex` 以 regex 比對），**不要把含 secret 的 env key 列進去**（或用過寬的 regex），否則對應的 secret 值會被寫進 log；`mtu: 9000` 需整條網路路徑支援，不確定改 `1500`；完整 address-pools 和各設定詳解讀 `references/daemon.md`。

套用：`systemctl restart docker`

---

## 8. Compose 安全設定

### RTFM 原始 x-lockdown（11notes image 用）
```yaml
x-lockdown: &lockdown
  read_only: true
  security_opt:
    - "no-new-privileges=true"
```

### 完整強化版（第三方 image 用）
```yaml
x-lockdown: &lockdown
  restart: unless-stopped
  init: true
  security_opt:
    - no-new-privileges=true
  cap_drop:
    - ALL

services:
  myapp:
    <<: *lockdown
    read_only: true
    tmpfs:
      - /tmp
      - /run
    user: "1000:1000"
    deploy:
      resources:
        limits:
          pids: 100
          cpus: "2"
          memory: 1G
        reservations:
          cpus: "0.5"
          memory: 256M
```

> **`deploy.resources.limits` 生效範圍**：在 Compose v2（`docker compose`）本機 `up` 即套用 `cpus`/`memory`/`pids`，不需 Swarm 或 `--compatibility`；只有舊版 `docker-compose` v1 才會忽略 `deploy` 而需要 Swarm 模式。swap 限制（`memswap_limit`/`mem_swappiness`）仍寫在 service 層，不在 `deploy` 下。

### Rootless 容器綁定低 port（< 1024）
```yaml
services:
  dns:
    user: "1000:1000"
    sysctls:
      net.ipv4.ip_unprivileged_port_start: 53
```

### cap_drop: ALL 後常需補回的 capability
| Capability | 需要的情境 |
| ----------- | ---------- |
| `NET_BIND_SERVICE` | 綁定 port < 1024（rootless 建議改用 sysctls） |
| `CHOWN` | entrypoint 需修改檔案 owner |
| `SETUID` / `SETGID` | entrypoint 切換使用者 |
| `DAC_OVERRIDE` | 讀寫自己不擁有的檔案 |
| `NET_RAW` | healthcheck 用 ping |

---

## 快速診斷清單

- [ ] 容器是否以非 root 使用者執行？（`docker inspect` 看 `User` 欄位）
- [ ] 是否用 PUID/PGID 啟動然後降權？→ 這不是真正 rootless，考慮換 image
- [ ] Image 是否必要地包含 shell 或系統工具？（考慮換 distroless/Alpine）
- [ ] 是否直接掛載 `/var/run/docker.sock`？→ 改用 rootless + distroless 的 socket-proxy（如 11notes/socket-proxy）
- [ ] 是否使用 Portainer/Dockge/Komodo 等管理工具？→ 這些需要完整 socket 存取，評估是否接受此風險
- [ ] 是否使用 bind mounts 存放持久資料？→ 考慮改 named volumes（支援 NFS/CIFS/S3）
- [ ] 是否設定 `no-new-privileges=true`？
- [ ] 是否設定 `cap_drop: [ALL]`？
- [ ] 需要寫入的服務是否加了 `read_only: true` + tmpfs？
- [ ] 是否設定 `init: true`？（signal 傳遞、殭屍 process）
- [ ] 是否設定 `deploy.resources.limits`？（pids、memory、CPU；Compose v2 本機 `up` 即生效，舊版 `docker-compose` v1 才需 Swarm/`--compatibility`）
- [ ] Volume ownership 需要調整時，是否用 init container 而非手動 chown？
- [ ] Config 是否能改用 inline env var 而非 bind mount 檔案？
- [ ] Rootless 容器需綁定 port < 1024 時，是否用 `sysctls` 而非 `cap_add: NET_BIND_SERVICE`？
- [ ] Host 層 daemon.json 是否設定 XFS data-root、log rotation、storage 限制、address-pools？
