---
name: dockerfile-builder
description: Build secure, minimal, production-ready Dockerfiles following 11notes/RTFM best practices (multi-stage, rootless, distroless, minimal attack surface). Use this skill WHENEVER the user authors or improves a Dockerfile or container image — writing a Dockerfile for an app, containerizing an existing service, choosing a base image, shrinking a bloated image ("why is my image so big", "my image is 1.8GB"), making an image production-ready, adding multi-arch builds or a .dockerignore, or stopping the container from running as root in the image. Apply these principles by default; do not wait for the user to say "distroless" or "rootless". NOT for reviewing a docker-compose file (use compose-lint) or hardening an already-running container's runtime settings such as capabilities/seccomp (use container-security) — but DO use it whenever a Dockerfile is being created or edited.
---

# Dockerfile Builder Skill

> 原則來源：[11notes/RTFM](https://github.com/11notes/RTFM) — 最小化攻擊面、rootless、distroless 是容器安全的基石。

## Reference Files

按需載入，不要全部預先讀取：

| 檔案 | 何時讀取 |
| ---- | -------- |
| `references/distroless.md` | 解釋 distroless 概念、eStargz 比較、image 大小比對、limitations |
| `references/rootless.md` | 深入解釋 rootless 概念、caps 比較、PUID/PGID 誤解 |
| `references/custom.md` | 解釋為何自建 image 而非向 upstream 提 PR |

---

## 核心原則

1. **最小攻擊面**：image 只包含應用程式運作所需，不多一個 bit
2. **Rootless**：process 從啟動到結束都不以 root 執行
3. **Multi-stage**：build 環境與 runtime 環境完全分離
4. **Layer 效率**：減少 cache bust，加速 CI/CD
5. **Multi-arch**：同時支援 amd64、arm64（生產環境標配）
6. **Distroless 是解法，eStargz 不是替代品**：lazy-loading 只優化拉取速度，不減少攻擊面

---

## 標準 Multi-Stage 結構

```dockerfile
# ── Stage 1: Builder ──────────────────────────────
FROM docker.io/library/golang:1.23-alpine AS builder

WORKDIR /build

# 先複製相依定義，利用 layer cache
COPY go.mod go.sum ./
RUN go mod download

# 再複製原始碼
COPY . .

# 靜態編譯，不依賴 libc
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app ./cmd/server

# ── Stage 2: Runtime ──────────────────────────────
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /app /app

USER 65532:65532

EXPOSE 8080

ENTRYPOINT ["/app"]
```

---

## 選擇正確的 Base Image

```
應用程式語言/類型
├── 靜態編譯（Go, Rust, C 靜態）
│   └── gcr.io/distroless/static-debian12
│       ⚠ 某些 Go/C app 使用 dynamic links → 改用 distroless/base 或 alpine
├── 動態連結 glibc（C, C++, Go with CGO）
│   └── gcr.io/distroless/base-debian12
├── Java
│   ├── JRE 21 → gcr.io/distroless/java21-debian12
│   └── JRE 17 → gcr.io/distroless/java17-debian12
├── Python
│   ├── 純 stdlib（無 C 擴充、無動態套件載入）→ gcr.io/distroless/python3-debian12
│   └── 有 C 擴充 / 動態套件載入 → docker.io/library/python:3.13-alpine（即 references/distroless.md 所指「Python 通常不適合 distroless」的情境）
├── Node.js / Deno
│   └── docker.io/library/node:22-alpine（移除 npm/yarn after install）
├── .NET Core
│   ├── 無 inline Assembly → mcr.microsoft.com/dotnet/runtime-deps（self-contained）
│   └── 有 inline Assembly → docker.io/library/alpine:3.21
├── 需要 shell/除錯工具
│   └── docker.io/library/alpine:3.21
└── 不知道 → 先用 alpine，後續測試能否改 distroless
```

| Image | 大小 | Shell | 適用 |
| ------- | ------ | ------- | ------ |
| `distroless/static` | ~2MB | ❌ | 靜態二進位 |
| `distroless/base` | ~20MB | ❌ | 動態連結 |
| `distroless/java21` | ~200MB | ❌ | Java |
| `alpine:3.21` | ~8MB | ✅ ash | 需要 shell 的輕量 |
| `debian:12-slim` | ~75MB | ✅ | 需要 Debian 相容性 |

---

## Rootless 設定

基本模式見各語言範本（Alpine 用 `addgroup/adduser`，distroless 用 `:nonroot` tag）。

**可設定 UID/GID（讓使用者 build 時覆蓋）：**
```dockerfile
ARG APP_UID=1000
ARG APP_GID=1000

RUN addgroup -g ${APP_GID} -S app && \
    adduser -u ${APP_UID} -S -G app app

USER ${APP_UID}:${APP_GID}
ENTRYPOINT ["/usr/local/bin/myapp"]
```

```bash
docker build --build-arg APP_UID=11420 --build-arg APP_GID=11420 -t myapp .
```

`COPY --from` 預設保留 root ownership，記得加 `--chown=${APP_UID}:${APP_GID}`（與上方可覆蓋的 UID/GID 一致；若未使用 ARG 則用實際 uid:gid，如 `1000:1000`）。

---

## Multi-Arch Builds

```dockerfile
# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM docker.io/library/golang:1.23-alpine AS builder

ARG TARGETOS TARGETARCH

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -ldflags="-s -w" -o /app .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /app /app
USER 65532:65532
ENTRYPOINT ["/app"]
```

```bash
# 推送多平台到 registry
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --push \
  -t myapp:latest .
```

---

## Layer 最佳化

```dockerfile
# Alpine
RUN apk add --no-cache curl ca-certificates

# Debian/Ubuntu
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl && \
    rm -rf /var/lib/apt/lists/*
```

複製順序：**變動頻率由低到高**
```dockerfile
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/  # 幾乎不變
COPY config/defaults/ /app/config/                                        # 偶爾變
COPY --from=builder /app /app                                             # 常常變
```

---

## 各語言範本

### Go（靜態編譯 + distroless）
```dockerfile
FROM docker.io/library/golang:1.23-alpine AS builder
WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /app .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /app /app
USER 65532:65532
ENTRYPOINT ["/app"]
```

### Python（Alpine）
```dockerfile
FROM docker.io/library/python:3.13-alpine AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM docker.io/library/python:3.13-alpine
RUN addgroup -g 1000 -S app && adduser -u 1000 -S -G app app
WORKDIR /app
COPY --from=builder /install /usr/local
COPY --chown=app:app . .
USER 1000:1000
CMD ["python", "main.py"]
```

### Node.js（Alpine）
```dockerfile
FROM docker.io/library/node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM docker.io/library/node:22-alpine
RUN addgroup -g 1000 -S app && adduser -u 1000 -S -G app app
WORKDIR /app
COPY --from=builder --chown=app:app /app/node_modules ./node_modules
COPY --chown=app:app . .
USER 1000:1000
CMD ["node", "index.js"]
```

### Rust（靜態編譯 + distroless）
```dockerfile
FROM docker.io/library/rust:1.83-alpine AS builder
RUN apk add --no-cache musl-dev
WORKDIR /build
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && \
    cargo build --release --target x86_64-unknown-linux-musl && \
    rm -rf src
COPY src/ src/
RUN touch src/main.rs && \
    cargo build --release --target x86_64-unknown-linux-musl

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /build/target/x86_64-unknown-linux-musl/release/myapp /app
USER 65532:65532
ENTRYPOINT ["/app"]
```

### .NET Core（self-contained）
```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0-alpine AS builder
WORKDIR /build
COPY *.csproj ./
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /publish \
    --self-contained true \
    -p:PublishSingleFile=true \
    -p:PublishTrimmed=true

FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-alpine
RUN addgroup -g 1000 -S app && adduser -u 1000 -S -G app app
WORKDIR /app
COPY --from=builder --chown=app:app /publish/myapp .
USER 1000:1000
ENTRYPOINT ["./myapp"]
```

### 靜態網站（Nginx + Alpine）
```dockerfile
FROM docker.io/library/node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# 直接用 unprivileged 官方 image：預設以 uid=101 執行、監聽 8080
FROM docker.io/nginxinc/nginx-unprivileged:1.27-alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
```

> **為何不用 stock `nginx`**：官方 `nginx` image 預設以 root 啟動，且直接加 `USER` 會因無法寫入 pid/cache 路徑而失敗；改用 `nginxinc/nginx-unprivileged`（uid=101、聽 8080、固定版本 tag）才是真正 rootless，不需手動建 user 或切 `USER`。

---

## Inline Config 模式

```dockerfile
FROM docker.io/library/alpine:3.21

RUN addgroup -g 1000 -S app && adduser -u 1000 -S -G app app

COPY --chown=app:app entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY --from=builder --chown=app:app /app /app

USER 1000:1000
ENTRYPOINT ["/entrypoint.sh"]
```

```bash
#!/bin/sh
# entrypoint.sh
if [ -n "$APP_CONFIG" ]; then
  echo "$APP_CONFIG" > /app/config.yaml
fi
exec /app/server "$@"
```

> **搭配 `read_only: true`**：config 寫入路徑必須掛載 `tmpfs`，例如 `tmpfs: [/app, /tmp]`。

---

## .dockerignore

```
# Secrets 和敏感設定
.env
.env.*
*.pem
*.key
secrets/

# Git 歷史（含提交紀錄中的舊 secrets）
.git
.gitignore

# Build artifacts
dist/
build/
target/
__pycache__/
*.pyc

# 依賴目錄
node_modules/
vendor/

# 開發工具設定
.vscode/
.idea/
*.swp

# 測試與文件
tests/
docs/
*.md
!README.md

# Docker 相關
Dockerfile*
docker-compose*.yml
.dockerignore
```

---

## HEALTHCHECK

```dockerfile
# HTTP 服務
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

# distroless（沒有 wget/curl）→ 讓應用程式本身支援 --healthcheck flag
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["/app", "--healthcheck"]
```

---

## 除錯 Distroless 容器

```bash
PID=$(docker inspect --format '{{.State.Pid}}' <container_name>)
nsenter -t $PID -m -u -i -n -p -- /bin/sh

# 或只進入 filesystem namespace 查看檔案
nsenter -t $PID -m -- ls /app
```

---

## 完成前檢查清單

- [ ] 使用 multi-stage build，runtime stage 不含 compiler/build tools
- [ ] Runtime base 是 distroless 或 alpine（非 ubuntu/debian full）
- [ ] 有 `USER` directive，且不是 root（uid 0）
- [ ] 相依安裝後有清除 cache（`--no-cache` 或 `rm -rf /var/lib/apt/lists/*`）
- [ ] COPY 順序符合「變動頻率由低到高」
- [ ] 沒有在 Dockerfile 硬寫 secrets 或 passwords
- [ ] `EXPOSE` 只宣告實際使用的 port
- [ ] 有 `ENTRYPOINT` 或 `CMD`（exec form `["..."]`，非 shell form）
- [ ] 有 `HEALTHCHECK`（或文件說明為何不需要）
- [ ] 需要 config 檔的服務：考慮 entrypoint 讀取 env var 寫入，而非要求 bind mount
- [ ] 需要支援多平台：加上 `--platform=$BUILDPLATFORM` 及 `ARG TARGETOS TARGETARCH`
- [ ] Image 相容 `read_only: true`：確認所有寫入需求（logs、tmp、pid、socket）已改用 tmpfs 或 volume
