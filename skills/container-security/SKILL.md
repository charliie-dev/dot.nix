---
name: container-security
description: 'Apply container security and hardening best practices based on 11notes/RTFM. Use this skill WHENEVER the user asks whether a container setup is safe or how to harden it — running as root, dropping capabilities (cap_drop), no-new-privileges, privileged containers, read-only rootfs, Docker socket safety (mounting /var/run/docker.sock, the ":ro makes it safe" myth, socket-proxy), PUID/PGID vs true rootless, distroless-for-security, or securely mounting volumes. Triggers even on a bare "is this secure?" or "how do I lock this down?" about a container, Dockerfile, or compose stack. Covers both Dockerfile and Docker Compose security settings. NOT for authoring a fresh Dockerfile from scratch (use dockerfile-builder) or a general non-security compose cleanup (use compose-lint); also out of scope: image CVE scanning (trivy), host firewall rules, and Kubernetes RBAC/secrets.'
---

# Container Security Skill

> Principles from [11notes/RTFM](https://github.com/11notes/RTFM)

## Reference Files

Load on demand; do not read them all up front:

| File | When to read |
| ---- | ------------ |
| `references/rootless.md` | Rootless concept in depth, why PUID/PGID is not enough, capability details |
| `references/distroless.md` | Distroless concept, eStargz comparison, limitations |
| `references/socket.md` | Docker socket risk in depth, the `:ro` misconception |
| `references/volumes.md` | Named volumes vs bind mounts in depth, NFS/CIFS/S3 examples |
| `references/daemon.md` | What each daemon.json setting means |
| `references/custom.md` | Why build your own image instead of sending a PR upstream |

---

## Core philosophy

- **Minimal attack surface + least privilege** = most automated attacks fail outright
- **Never trust defaults**: distro and Docker defaults cannot cover the complexity of an individual installation
- **Security is layered**: rootless, distroless, socket-proxy, resource limits are independent and stack on each other
- These principles are not Docker-specific; they apply equally to Podman, containerd, and every other OCI-compatible runtime

---

## 1. Rootless containers

> **Docker rootless mode vs image rootless**: running the daemon itself in rootless mode (`dockerd-rootless`) reduces the host-level impact of a daemon or runtime compromise, but it does not replace image-level non-root — UID 0 inside the container still holds elevated privileges over that namespace and over everything exposed to the container. This section targets Docker running as a **regular root daemon**; apply its `USER`/least-privilege guidance under a rootless daemon too.

**Common misconception**: many images use `PUID`/`PGID` and look rootless, but the entrypoint still starts as root and then drops privileges with `su`/`gosu`. Truly rootless means the process never runs as root, from start to finish.

### Dockerfile
```dockerfile
RUN addgroup -g 1000 app && adduser -u 1000 -G app -s /bin/sh -D app
USER 1000:1000
```

### Compose
```yaml
services:
  myapp:
    user: "1000:1000"
    security_opt:
      - no-new-privileges=true
```

Dynamic UID/GID:
```yaml
services:
  myapp:
    user: "${UID}:${GID}"
```

> **11notes images default to UID/GID `1000:1000`**. When using official 11notes images, make sure volume ownership matches this value, or override it via dynamic UID/GID.

---

## 2. Distroless images

**Principle**: the image contains only what the application needs. No shell, no curl, no wget — an attacker who gains RCE loses the ready-made post-exploitation tooling, which shrinks the attack surface; it is not a guarantee that a payload cannot be fetched, since a language runtime or a raw socket call can still download and write content.

### Recommended base images
| Use case | Base image |
| -------- | ---------- |
| Statically compiled Go/Rust | `gcr.io/distroless/static-debian13` |
| Dynamically linked (glibc) | `gcr.io/distroless/base-debian13` |
| Java | `gcr.io/distroless/java21-debian13` |
| Python (with limitations) | `gcr.io/distroless/python3-debian13` |
| Lightweight but with a shell | `docker.io/library/alpine:3.21.7` |

> The base images above are illustrative. Pick the release that matches the workload (for distroless the Debian release is part of the image name, e.g. `-debian12` vs `-debian13`), then pin it: distroless publishes only floating tags (`latest`/`nonroot`/`debug`/`debug-nonroot`), so pin those by digest (`gcr.io/distroless/static-debian13@sha256:...`); images that do publish version tags get a full patch-level tag (`alpine:3.21.7`, not `alpine:3.21`), per compose-lint's pinned-tag rule. Never emit an untagged reference — it resolves to `:latest`. The pinned tags in this table and in the examples below are values from when this was written; re-resolve them before emitting.

### When distroless does not fit
- Python apps that load many packages dynamically
- Node.js / Deno with dynamically loaded libraries
- .NET Core using inline Assembly
→ Use Alpine instead and remove unnecessary tool packages

Debugging a distroless container (no shell): read `references/distroless.md`.

---

## 3. Docker socket security

**Core risk**: any program that can reach `/var/run/docker.sock` has full control of the Docker daemon, with no authentication.

**Common misconception**: mounting the socket with `:ro` "is safer because it is read-only" — **wrong**. `:ro` only stops the container from deleting or renaming the socket file itself; it has no effect on Docker API operations.

Tools such as Portainer, Dockge, and Komodo **require** full socket access to work. **If security matters, avoid these tools.**

### The right way: socket-proxy
```yaml
services:
  socket-proxy:
    image: docker.io/11notes/socket-proxy:2.1.7
    container_name: socket-proxy
    # starts as root to open the host socket, then serves the proxy socket as 1000:1000. The
    # startup check requires user: to equal the socket's owner uid:gid exactly, so the gid comes
    # from the deployer (upstream's "0:0" only works on a root:root socket); on a mismatch the
    # image exits and prints the pair to use
    user: "0:${DOCKER_SOCKET_GID:?set to the gid owning the docker socket: stat -c '%g' /run/docker.sock}"
    environment:
      # the image always starts a TCP proxy on :2375 and binds it to 0.0.0.0 by default, which any
      # container sharing a network with it could reach; pin it to loopback as the second line
      # behind network_mode: none below
      SOCKET_PROXY_HTTP_LISTEN_IP: "127.0.0.1"
    volumes:
      - /run/docker.sock:/run/docker.sock:ro
      - socket-proxy.run:/run/proxy
    # no network at all: consumers reach the proxy only through the shared socket volume, so the
    # TCP listener has nowhere to be reached from even if the loopback pin above is ever lost
    network_mode: none
    restart: unless-stopped
    read_only: true
    security_opt:
      - no-new-privileges=true

  myapp:
    depends_on:
      socket-proxy:
        condition: service_healthy
    # the proxy socket is created after the image drops to SOCKET_PROXY_UID/GID (default 1000:1000)
    # and is never chmod'd, so it lands at 0755 and only that exact uid can connect. Match it here,
    # or set SOCKET_PROXY_UID/SOCKET_PROXY_GID on the proxy to this app's ids
    user: "1000:1000"
    volumes:
      - socket-proxy.run:/var/run   # the app finds the proxied socket at /var/run/docker.sock

volumes:
  socket-proxy.run:
```

The policy is fixed, not configured: the proxy forwards only read requests (`GET`/`HEAD`) and refuses everything else, and even over `GET` it blocks `/containers/{id}/attach/ws`, `/containers/{id}/export`, `/containers/{id}/archive`, `/secrets`, `/configs` and `/swarm/unlockkey`. Its README also lists `/images/{name}/get`, but the 2.1.7 pattern (`images/get(/|)$`) does not match that path, so image contents can still be exported through the proxy. No variable widens the request policy — an app that needs write access does not belong behind this proxy.

> **Warning**: the image serves the same proxy over TCP on port 2375 as well, and that listener binds to `0.0.0.0` unless told otherwise, so on a compose network every other container could reach it. Two independent lines keep access to the shared `socket-proxy.run` volume: `network_mode: none` leaves the proxy with no network to be reached over, and `SOCKET_PROXY_HTTP_LISTEN_IP: "127.0.0.1"` confines the listener should a network ever be attached — do not rely on either alone. Never add `ports:` to the service or attach it to a network the outside can reach.

---

## 4. Named volumes vs bind mounts

**Principle**: if you want Infrastructure as Code, use named volumes, not bind mounts.

| Aspect | Named Volume | Bind Mount | Tmpfs |
| ------ | ------------ | ---------- | ----- |
| Directory auto-created | ✅ | ❌ manual | ✅ |
| Permission handling | ✅ inherits parent directory | ❌ manual chown | ✅ |
| Self-contained compose | ✅ | ❌ depends on host path | ✅ |
| Storage backend | NFS/CIFS/S3/local | host path only | RAM/swap |
| Quota | ✅ definable in compose | ❌ host-level setup | ✅ |

Named volume storage backend example (details in `references/volumes.md`):
```yaml
volumes:
  app-data:
    driver_opts:
      type: "nfs"
      o: "addr=192.168.1.30,nolock,soft,nfsvers=4"
      device: ":/volume1/containers/myapp/data"
```

---

## 5. Changing UID/GID: the init-container pattern

```yaml
services:
  init-permissions:
    image: docker.io/library/alpine:3.21.7
    command: chown -R 1000:1000 /data
    volumes:
      - app-data:/data
    restart: "no"

  myapp:
    image: registry.example.com/myapp:1.2.3
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

## 6. Inline config pattern

Put the config content in an env var; the entrypoint writes it to a file at startup:

```yaml
services:
  adguard:
    image: docker.io/11notes/adguard:0.107.79
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
    volumes:
      - adguard.etc:/adguard/etc
      - adguard.var:/adguard/var
    tmpfs:
      # needed for read_only: true — the entrypoint writes its runtime files here
      - /adguard/run:uid=1000,gid=1000

volumes:
  adguard.etc:
  adguard.var:
```

> **With `read_only: true`**: mount a `tmpfs` at the runtime directory the entrypoint writes to (`/adguard/run` for this image), and keep the config directory and the work directory on named volumes — AdGuard rewrites its config in place, so a `tmpfs` there would discard it on every restart, and it writes its statistics DB and query logs to `/adguard/var`. This image declares `VOLUME` for both directories, so leaving a mount out does not break startup: Docker silently creates an anonymous volume instead, which is exactly what section 4 says not to rely on.

---

## 7. Docker daemon hardening (daemon.json)

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

Notes: `log-opts.env` is the list of env keys to attach to each log entry (comma-separated; `env-regex` matches by regex) — **do not list env keys that hold secrets** (or use an overly broad regex), or the secret values end up in the logs; `mtu: 9000` requires jumbo-frame support along the whole network path, use `1500` if unsure; full address-pool and per-setting details in `references/daemon.md`.

Apply: `systemctl restart docker`

---

## 8. Compose security settings

### RTFM original x-lockdown (for 11notes images)
```yaml
x-lockdown: &lockdown
  read_only: true
  security_opt:
    - "no-new-privileges=true"
```

### Full hardened variant (for third-party images)
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

> **Where `deploy.resources.limits` applies**: with Compose v2 (`docker compose`) a local `up` applies `cpus`/`memory`/`pids` — no Swarm or `--compatibility` needed; only the legacy `docker-compose` v1 ignores `deploy` and needs Swarm mode. Swap limits (`memswap_limit`/`mem_swappiness`) still go at the service level, not under `deploy`.

### Rootless container binding a low port (< 1024)
```yaml
services:
  dns:
    user: "1000:1000"
    sysctls:
      net.ipv4.ip_unprivileged_port_start: 53
```

### Capabilities commonly re-added after cap_drop: ALL
| Capability | Needed when |
| ---------- | ----------- |
| `NET_BIND_SERVICE` | binding a port < 1024 (for rootless, prefer sysctls) |
| `CHOWN` | entrypoint changes file ownership |
| `SETUID` / `SETGID` | entrypoint switches user |
| `DAC_OVERRIDE` | reading/writing files it does not own |
| `NET_RAW` | healthcheck uses ping |

---

## Quick diagnostic checklist

- [ ] Does the container run as a non-root user? (`docker inspect`, `User` field)
- [ ] Does it start with PUID/PGID and then drop privileges? → not truly rootless; consider another image
- [ ] Does the image include a shell or system tools it does not need? (consider distroless/Alpine)
- [ ] Is `/var/run/docker.sock` mounted directly? → use a read-only, distroless socket-proxy that serves the proxied socket as non-root (e.g. 11notes/socket-proxy, section 3: it opens the host socket as root and then drops to 1000:1000, so by the section 1 definition it is not itself rootless)
- [ ] Are Portainer/Dockge/Komodo or similar management tools in use? → they need full socket access; decide whether that risk is acceptable
- [ ] Are bind mounts used for persistent data? → consider named volumes (NFS/CIFS/S3 supported)
- [ ] Is `no-new-privileges=true` set?
- [ ] Is `cap_drop: [ALL]` set?
- [ ] Do services that need to write have `read_only: true` + tmpfs?
- [ ] Is `init: true` set? (signal forwarding, zombie processes)
- [ ] Are `deploy.resources.limits` set? (pids, memory, CPU; applied by a local Compose v2 `up`, only legacy `docker-compose` v1 needs Swarm/`--compatibility`)
- [ ] When volume ownership must change, is an init container used instead of a manual chown?
- [ ] Can the config be an inline env var instead of a bind-mounted file?
- [ ] When a rootless container must bind a port < 1024, is `sysctls` used instead of `cap_add: NET_BIND_SERVICE`?
- [ ] Is the host daemon.json configured with XFS data-root, log rotation, storage limits, address-pools?
