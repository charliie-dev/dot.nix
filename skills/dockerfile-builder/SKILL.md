---
name: dockerfile-builder
description: Build secure, minimal, production-ready Dockerfiles following 11notes/RTFM best practices (multi-stage, rootless, distroless, minimal attack surface). Use this skill WHENEVER a Dockerfile or container image is authored or improved — containerizing a service, choosing a base image, shrinking a bloated image, making an image production-ready, adding multi-arch builds or a .dockerignore, or stopping the container from running as root. NOT for reviewing a docker-compose file (use compose-lint) or hardening an already-running container's runtime settings such as capabilities/seccomp (use container-security).
---

# Dockerfile Builder Skill

> Principles from [11notes/RTFM](https://github.com/11notes/RTFM) — minimal attack surface, rootless, and distroless are the foundation of container security.

## Reference Files

Load on demand; do not read them all up front:

| File | When to read |
| ---- | ------------ |
| `references/distroless.md` | Distroless concept, eStargz comparison, image size comparison, limitations |
| `references/rootless.md` | Rootless concept in depth, capability comparison, the PUID/PGID misconception |
| `references/custom.md` | Why build your own image instead of sending a PR upstream |

---

## Core principles

1. **Minimal attack surface**: the image contains only what the application needs to run, not one bit more
2. **Rootless**: the process never runs as root, from start to finish
3. **Multi-stage**: build environment and runtime environment fully separated
4. **Layer efficiency**: fewer cache busts, faster CI/CD
5. **Multi-arch**: support amd64 and arm64 together (standard for production)
6. **Distroless is the solution, eStargz is not a substitute**: lazy loading only speeds up pulls; it does not shrink the attack surface

Apply these principles by default; do not wait for the user to ask for distroless or rootless.
The templates below carry no real versions: every `<…>` marker is a placeholder to resolve before emitting, and a Dockerfile that still contains one is not finished. Derive the target release line from the project's own manifest and the user's stated constraints (`go.mod`, `.python-version` / `pyproject.toml`, `package.json` `engines`, the `.csproj` TFM) — never bump it unasked — then resolve the newest supported patch *within that line* and pin it (`<go-patch>` becomes a full `MAJOR.MINOR.PATCH`). For distroless the Debian release is part of the image name and only floating tags are published (`latest`, `nonroot`, `debug`, `debug-nonroot` and the like), so pin those by digest: `<digest>` becomes the hex the tag resolves to today. The .NET placeholders do not all come from the TFM; their rules sit with the .NET template below. Placeholders that no manifest names — `<rust-patch>` (unless `rust-toolchain.toml` pins a toolchain or Cargo.toml's `rust-version` sets a floor), `<nginx-patch>`, `<alpine-patch>`, `<debian-patch>` — take their release line from an existing `FROM` in the repo's Dockerfiles or compose files, and otherwise from the newest stable line, asked about or stated as an assumption alongside the Dockerfile.

---

## Standard multi-stage structure

```dockerfile
# ── Stage 1: Builder ──────────────────────────────
FROM docker.io/library/golang:<go-patch>-alpine AS builder

WORKDIR /build

# Copy dependency manifests first to use the layer cache
COPY go.mod go.sum ./
RUN go mod download

# Then copy the source
COPY . .

# Static build, no libc dependency
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app ./cmd/server

# ── Stage 2: Runtime ──────────────────────────────
FROM gcr.io/distroless/static-debian13:nonroot@sha256:<digest>

COPY --from=builder /app /app

USER 65532:65532

EXPOSE 8080

ENTRYPOINT ["/app"]
```

---

## Choosing the right base image

```
Application language / type
├── Statically compiled (Go, Rust, static C)
│   └── gcr.io/distroless/static-debian13
│       ⚠ Some Go/C apps use dynamic linking → use distroless/base or alpine instead
├── Dynamically linked glibc (C, C++, Go with CGO)
│   └── gcr.io/distroless/base-debian13
├── Java
│   ├── JRE 21 → gcr.io/distroless/java21-debian13
│   └── JRE 17 → gcr.io/distroless/java17-debian13
├── Python
│   ├── Pure stdlib (no C extensions, no dynamic package loading) → gcr.io/distroless/python3-debian13
│   └── C extensions / dynamic package loading → docker.io/library/python:<python-patch>-alpine (the "Python is usually not a fit for distroless" case in references/distroless.md)
├── Node.js / Deno
│   └── docker.io/library/node:<node-patch>-alpine (remove npm/yarn after install)
├── .NET Core
│   ├── No inline Assembly → mcr.microsoft.com/dotnet/runtime-deps:<dotnet-runtime-patch>-alpine<alpine-line> (self-contained)
│   └── Inline Assembly → docker.io/library/alpine:<alpine-patch>
├── Needs a shell / debugging tools
│   └── docker.io/library/alpine:<alpine-patch>
└── Unsure → start with alpine, then test whether distroless works
```

| Image | Size | Shell | Use |
| ----- | ---- | ----- | --- |
| `distroless/static` | ~2MB | ❌ | static binaries |
| `distroless/base` | ~20MB | ❌ | dynamically linked |
| `distroless/java21` | ~200MB | ❌ | Java |
| `alpine:<alpine-patch>` | ~8MB | ✅ ash | lightweight, needs a shell |
| `debian:<debian-patch>-slim` | ~75MB | ✅ | needs Debian compatibility |

---

## Rootless setup

The basic pattern is in each language template (Alpine uses `addgroup/adduser`, distroless uses the `:nonroot` tag, pinned by digest).

**Configurable UID/GID (overridable at build time):**
```dockerfile
ARG APP_UID=1000
ARG APP_GID=1000

RUN addgroup -g ${APP_GID} -S app && \
    adduser -u ${APP_UID} -S -G app app

USER ${APP_UID}:${APP_GID}
ENTRYPOINT ["/usr/local/bin/myapp"]
```

```bash
docker build --build-arg APP_UID=11420 --build-arg APP_GID=11420 -t registry.example.com/myapp:1.2.3 .
```

`COPY --from` keeps root ownership by default; remember to add `--chown=${APP_UID}:${APP_GID}` (matching the overridable UID/GID above; without the ARGs use the literal uid:gid, e.g. `1000:1000`).

---

## Multi-arch builds

```dockerfile
# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM docker.io/library/golang:<go-patch>-alpine AS builder

ARG TARGETOS TARGETARCH

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -ldflags="-s -w" -o /app .

FROM gcr.io/distroless/static-debian13:nonroot@sha256:<digest>
COPY --from=builder /app /app
USER 65532:65532
ENTRYPOINT ["/app"]
```

```bash
# Push a multi-platform image to the registry
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --push \
  -t registry.example.com/myapp:1.2.3 .
```

---

## Layer optimization

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

Copy order: **from least to most frequently changed**
```dockerfile
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/  # almost never changes
COPY config/defaults/ /app/config/                                        # changes occasionally
COPY --from=builder /app /app                                             # changes often
```

---

## Language templates

### Go (static build + distroless)
```dockerfile
FROM docker.io/library/golang:<go-patch>-alpine AS builder
WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /app .

FROM gcr.io/distroless/static-debian13:nonroot@sha256:<digest>
COPY --from=builder /app /app
USER 65532:65532
ENTRYPOINT ["/app"]
```

### Python (Alpine)
```dockerfile
FROM docker.io/library/python:<python-patch>-alpine AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM docker.io/library/python:<python-patch>-alpine
RUN addgroup -g 1000 -S app && adduser -u 1000 -S -G app app
WORKDIR /app
COPY --from=builder /install /usr/local
COPY --chown=app:app . .
USER 1000:1000
CMD ["python", "main.py"]
```

### Node.js (Alpine)
```dockerfile
FROM docker.io/library/node:<node-patch>-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM docker.io/library/node:<node-patch>-alpine
RUN addgroup -g 1000 -S app && adduser -u 1000 -S -G app app
WORKDIR /app
COPY --from=builder --chown=app:app /app/node_modules ./node_modules
COPY --chown=app:app . .
USER 1000:1000
CMD ["node", "index.js"]
```

### Rust (static build + distroless)
```dockerfile
FROM docker.io/library/rust:<rust-patch>-alpine AS builder
RUN apk add --no-cache musl-dev
WORKDIR /build
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && \
    cargo build --release --target x86_64-unknown-linux-musl && \
    rm -rf src
COPY src/ src/
RUN touch src/main.rs && \
    cargo build --release --target x86_64-unknown-linux-musl

FROM gcr.io/distroless/static-debian13:nonroot@sha256:<digest>
COPY --from=builder /build/target/x86_64-unknown-linux-musl/release/myapp /app
USER 65532:65532
ENTRYPOINT ["/app"]
```

### .NET Core (self-contained)

`<dotnet-sdk-patch>` and `<dotnet-runtime-patch>` are looked up separately, in their own mcr repositories:

- The SDK's third component is a feature band, not a runtime patch: one release wave ships SDK `x.y.Bnn` beside runtime `x.y.nn`, and reusing either number for the other names a tag that does not exist.
- `global.json` governs the SDK: its nearest `sdk.version`/`rollForward` fixes `<dotnet-sdk-patch>` (a `patch`/`latestPatch` roll-forward fails outside that feature band even if a newer SDK image exists); without one, use the TFM's newest SDK band.
- `<dotnet-runtime-patch>` always comes from the TFM.
- `<alpine-line>` is the two-component Alpine release (`3.NN`), unlike the three-component `<alpine-patch>`: on mcr a full-patch tag always carries it, and bare `-alpine` exists only on floating `major.minor` tags.

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:<dotnet-sdk-patch>-alpine<alpine-line> AS builder
WORKDIR /build
COPY *.csproj ./
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /publish \
    --self-contained true \
    -p:PublishSingleFile=true \
    -p:PublishTrimmed=true

FROM mcr.microsoft.com/dotnet/runtime-deps:<dotnet-runtime-patch>-alpine<alpine-line>
RUN addgroup -g 1000 -S app && adduser -u 1000 -S -G app app
WORKDIR /app
COPY --from=builder --chown=app:app /publish/myapp .
USER 1000:1000
ENTRYPOINT ["./myapp"]
```

### Static site (Nginx + Alpine)
```dockerfile
FROM docker.io/library/node:<node-patch>-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Use the official unprivileged image directly: runs as uid=101 and listens on 8080 by default
FROM docker.io/nginxinc/nginx-unprivileged:<nginx-patch>-alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
```

> **Why not stock `nginx`**: the official `nginx` image starts as root, and simply adding `USER` fails because it cannot write its pid/cache paths; `nginxinc/nginx-unprivileged` (uid=101, port 8080, pin it to a full patch tag) is truly rootless with no need to create a user or switch `USER` by hand.

---

## Inline config pattern

```dockerfile
FROM docker.io/library/alpine:<alpine-patch>

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
  mkdir -p /app/etc
  echo "$APP_CONFIG" > /app/etc/config.yaml
fi
exec /app/server "$@"
```

> **With `read_only: true`**: mount a `tmpfs` at the config directory only, e.g. `tmpfs: [/app/etc, /tmp]` — never at `/app`, which would hide the binary the entrypoint executes.

---

## .dockerignore

```
# Secrets and sensitive config
.env
.env.*
*.pem
*.key
secrets/

# Git history (including old secrets in past commits)
.git
.gitignore

# Build artifacts
dist/
build/
target/
__pycache__/
*.pyc

# Dependency directories
node_modules/
vendor/

# Editor / tooling config
.vscode/
.idea/
*.swp

# Tests and docs
tests/
docs/
*.md
!README.md

# Docker files
Dockerfile*
docker-compose*.yml
.dockerignore
```

---

## HEALTHCHECK

```dockerfile
# HTTP service
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

# distroless (no wget/curl) → have the application itself support a --healthcheck flag
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["/app", "--healthcheck"]
```

---

## Debugging distroless containers

```bash
PID=$(docker inspect --format '{{.State.Pid}}' <container_name>)
nsenter -t $PID -m -u -i -n -p -- /bin/sh

# Or enter only the filesystem namespace to inspect files
nsenter -t $PID -m -- ls /app
```

---

## Pre-completion checklist

- [ ] Multi-stage build; the runtime stage contains no compiler/build tools
- [ ] Runtime base is distroless or alpine (not full ubuntu/debian)
- [ ] Has a `USER` directive, and it is not root (uid 0)
- [ ] Caches cleared after installing dependencies (`--no-cache` or `rm -rf /var/lib/apt/lists/*`)
- [ ] COPY order goes from least to most frequently changed
- [ ] No secrets or passwords hard-coded in the Dockerfile
- [ ] `EXPOSE` declares only ports actually in use
- [ ] Has `ENTRYPOINT` or `CMD` (exec form `["..."]`, not shell form)
- [ ] Has `HEALTHCHECK` (or documents why none is needed)
- [ ] Services needing a config file: consider an entrypoint that reads an env var and writes it, instead of requiring a bind mount
- [ ] Multi-platform support needed: add `--platform=$BUILDPLATFORM` and `ARG TARGETOS TARGETARCH`
- [ ] Image is compatible with `read_only: true`: every write path (logs, tmp, pid, socket) moved to tmpfs or a volume
