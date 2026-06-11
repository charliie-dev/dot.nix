---
name: compose-lint
description: Review, lint, and improve Docker Compose files — secrets management, networking, reliability (healthchecks, depends_on, restart, log rotation), image hygiene (pinned tags, registry prefixes), maintainability, and documentation. Use this skill WHENEVER the user wants a review, audit, or cleanup of a docker-compose.yml / compose.yaml — "review my compose", "lint my compose", "is my compose production ready", "clean up this messy compose", "audit this stack", or a general DevOps review of a compose stack, even when they never say the word "lint". For container security FUNDAMENTALS specifically (rootless, cap_drop, read_only, distroless, socket-proxy, named volumes, init, resource limits) pair with the container-security skill; to write a service's Dockerfile use dockerfile-builder. NOT for runtime/debugging issues (e.g. "port is already allocated", data lost after "down -v") or converting compose to Kubernetes.
---

# Compose Lint

Review a compose stack systematically. Report findings as a prioritized table (High/Medium/Low), confirm with the user, then apply in logical groups.

After each group, validate:
```bash
docker compose config --quiet
docker compose up -d && docker compose ps
docker compose logs <service> --tail=1000
```

> 安全基礎 (rootless、cap_drop、read_only、no-new-privileges、socket-proxy、named volumes、init、resource limits) → `container-security` skill。
> 若同目錄下發現 `Dockerfile`，同時套用 `dockerfile-builder` skill 審查 image 的建構方式。

---

## Checklist

### 1. Secrets Management

- [ ] Hardcoded secrets in `environment` or `.env` → move to `./secrets/` files
- [ ] Use `_FILE` env var suffix where supported (postgres, n8n, etc.)
- [ ] Add `secrets/` to `.gitignore`
- [ ] `chmod 600 secrets/*` enforced wherever secret files are created — both the first-time-create path and the already-exists path of your setup script/task
- [ ] `.env` = compose interpolation only; pass container vars via `environment:` or `env_file:`

> `environment` > `env_file` > Dockerfile `ENV`

### 2. Networking

- [ ] Remove unused network declarations
- [ ] Internet-facing services → external (reverse proxy) network; internal services (db, backup) → `default` only
- [ ] Services listening for container traffic bind on `0.0.0.0`, not `127.0.0.1`

### 3. Reliability

- [ ] Healthchecks on all services (`start_period`, `interval`, `timeout`, `retries`)
- [ ] `depends_on` with `condition: service_healthy` + `restart: true`
- [ ] `stop_grace_period: 30s` for databases; default 10s fine for stateless
- [ ] Env vars in healthchecks use `${VAR:-default}` fallback
- [ ] Log rotation on every service:
  ```yaml
  logging:
    driver: json-file
    options:
      max-size: "10m"
      max-file: "3"
  ```
- [ ] Postgres backups: `docker.io/prodrigestivill/postgres-backup-local` (match pg version tag), bind mount `./backups/`, `SCHEDULE: "@daily"`, retention vars, `_FILE` suffix support

### 4. Image Hygiene & Maintainability

- [ ] File header: `# yaml-language-server: $schema=https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json`
- [ ] File footer: `# vim: set ft=yaml.docker-compose :`
- [ ] YAML anchors for repeated patterns (`x-common`, `x-timezone`, `x-healthcheck`, `x-secrets`)
- [ ] Explicit registry prefix: `docker.io/library/postgres:18-alpine` not `postgres:18-alpine`
  - Official single-name images → `docker.io/library/<name>`; user images → `docker.io/<user>/<name>`
  - Already on `ghcr.io/`, `lscr.io/`, etc. → no change needed
- [ ] Pinned tags everywhere, including one-off/init containers (`alpine:3.21.3` not `alpine:3`)
- [ ] Unquote booleans, integers, plain strings; keep quotes for port mappings, special YAML chars, label values, healthcheck test strings
- [ ] `environment:` uses map syntax (`KEY: value`) not list syntax (`- KEY=value`)

### 5. Service Config Validation

For each service with bind-mounted config files:
1. Read the config file; note the image version
2. Use context7 MCP (`resolve-library-id` → `query-docs`) to check deprecated/renamed options for that version. context7 是選用的：若環境未安裝該 MCP，改用 WebSearch 或該服務官方文件查證即可，不要因缺 context7 而中斷審查。
3. Report: **High** = startup failures, **Medium** = warnings, **Low** = new optional improvements

### 6. Documentation

- [ ] `README.md`: one-liner, ASCII architecture diagram, prerequisites, quick-start, env vars table (with generation commands)
