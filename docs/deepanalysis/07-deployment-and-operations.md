# 07 — Deployment & Operations

This document describes the container build, Kubernetes manifests, release tasks, runtime configuration, environment-variable contract, health probes, and operational gaps.

---

## 1. Container Build

### `Dockerfile`

Multi-stage build:

1. **Builder stage** (`hexpm/elixir:1.18.3-erlang-27.3.3-debian-bookworm-20260610-slim`):
   - Installs build deps (`build-essential`, `git`, `ca-certificates`).
   - Gets and compiles deps.
   - Copies source, compiles, builds assets with `mix assets.deploy`, then builds the release.

2. **Runtime stage** (`debian:bookworm-slim`):
   - Installs runtime deps (`libstdc++6`, `openssl`, `libncurses5`, `ca-certificates`, `curl`).
   - Creates a non-root `debtstalker` user.
   - Copies the release from the builder.
   - Exposes port 4000.
   - Defines a `HEALTHCHECK` against `/api/health`.
   - Default command: `bin/debt_stalker start`.

**Note:** `libncurses5` is installed, but Debian Bookworm typically provides `libncurses6`. This may cause runtime issues depending on the exact base image.

---

## 2. Local Infrastructure

### `docker-compose.yml`

Only runs PostgreSQL 16:

```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: debt_stalker_dev
    ports:
      - "5432:5432"
```

The Phoenix app itself is run locally with `make run`.

### Local deploy scripts

- `scripts/deploy.sh` — local `kind`/minikube deploy with migration job and rollout status.
- `scripts/scaling-demo.sh` — manual worker scale-up/scale-down demo.
- `scripts/install-hooks.sh` — installs the `rs-guard` pre-commit hook.

---

## 3. Kubernetes Manifests

### Namespace

`k8s/namespace.yaml` creates the `debt-stalker` namespace.

### ConfigMap

`k8s/configmap.yaml` holds non-sensitive env:

```yaml
PHX_HOST: "debt-stalker.example.com"
PHX_PORT: "4000"
POOL_SIZE: "10"
MIX_ENV: "prod"
```

### Secret

`k8s/secret.yaml` holds placeholders:

```yaml
DATABASE_URL: "ecto://postgres:CHANGE_ME@postgres:5432/debt_stalker_prod"
SECRET_KEY_BASE: "CHANGE_ME_generate_with_mix_phx_gen_secret"
CLOAK_KEY: "CHANGE_ME_base64_encoded_32_byte_key"
JWT_SECRET: "CHANGE_ME_strong_random_secret"
WEBHOOK_SECRET: "CHANGE_ME_hmac_signing_secret"
```

**Gap:** `runtime.exs` also requires `SESSION_SIGNING_SALT`, `ADMIN_PASSWORD`, and `LIVE_VIEW_SIGNING_SALT` in production, but these are missing from `k8s/secret.yaml`. A pod booted from these manifests would crash.

### Migration Job

`k8s/migration-job.yaml` runs `DebtStalker.Release.migrate/0` as a one-shot Job:

```yaml
metadata:
  name: debt-stalker-migrate
spec:
  backoffLimit: 3
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: ghcr.io/igmarin/debt-stalker:latest
          command: ["bin/debt_stalker"]
          args: ["eval", "DebtStalker.Release.migrate()"]
```

**Gap:** The Job has a fixed name. Re-applying a completed Job fails in Kubernetes, blocking subsequent deploys. Solutions include `generateName`, `ttlSecondsAfterFinished`, or deleting the Job before re-applying.

### Web Deployment

`k8s/deployment-web.yaml`:

- 2 replicas.
- `OBAN_QUEUES: "false"` — web pods do not process Oban jobs.
- HTTP readiness/liveness probes on `/api/health/ready` and `/api/health/live`.
- Resource requests/limits: 100m–500m CPU, 256Mi–512Mi memory.

### Worker Deployment

`k8s/deployment-worker.yaml`:

- 2 replicas.
- `PHX_SERVER: "false"`.
- Oban queue sizes set via env:
  - `OBAN_QUEUE_DEFAULT: "10"`
  - `OBAN_QUEUE_EVENTS: "20"`
  - `OBAN_QUEUE_NOTIFICATIONS: "10"`
- Exec liveness probe: `bin/debt_stalker rpc DebtStalker.Release.version()`.
- Same resource limits as web.

### Service

`k8s/service.yaml`:

- `type: ClusterIP` on port 4000.
- Selects `component: web` pods.

**Gap:** No Ingress or TLS manifest is provided. A real cluster needs an Ingress (or LoadBalancer) and TLS termination.

### Horizontal Pod Autoscaler

`k8s/hpa-worker.yaml`:

- Targets `debt-stalker-worker` deployment.
- Min 2, max 10 replicas.
- Scales on CPU ≥ 70% and memory ≥ 80%.
- Scale-up: +2 pods per 60s, 30s stabilization.
- Scale-down: -1 pod per 60s, 300s stabilization.

---

## 4. Release Tasks

**File:** `lib/debt_stalker/release.ex`

Provides Mix-free release tasks:

```elixir
DebtStalker.Release.migrate()      # Run pending migrations
DebtStalker.Release.rollback(repo, version)  # Roll back to version
DebtStalker.Release.version()      # Print app version
```

Called from the release as:

```bash
bin/debt_stalker eval "DebtStalker.Release.migrate()"
```

---

## 5. Runtime Configuration

**File:** `config/runtime.exs`

All production secrets are loaded from environment variables.

### Required production env vars

| Variable | Used for |
|----------|----------|
| `DATABASE_URL` | Ecto Repo connection |
| `SECRET_KEY_BASE` | Phoenix session/endpoint signing |
| `SESSION_SIGNING_SALT` | Session cookie signing |
| `JWT_SECRET` | JWT signing |
| `ADMIN_PASSWORD` | Admin dashboard login |
| `CLOAK_KEY` | Cloak AES-256-GCM encryption |
| `WEBHOOK_SECRET` | HMAC webhook verification |
| `LIVE_VIEW_SIGNING_SALT` | LiveView token signing |

### Optional production env vars

| Variable | Default |
|----------|---------|
| `PHX_HOST` | `example.com` |
| `PORT` | `4000` |
| `POOL_SIZE` | `10` |
| `OBAN_QUEUES` | `[default: 10, events: 20, notifications: 10]` or `false` |
| `OBAN_QUEUE_DEFAULT` | `10` |
| `OBAN_QUEUE_EVENTS` | `20` |
| `OBAN_QUEUE_NOTIFICATIONS` | `10` |
| `RATE_LIMIT_AUTH_TOKEN` | `10` per window |
| `RATE_LIMIT_AUTH_TOKEN_WINDOW_MS` | `60000` |
| `RATE_LIMIT_WEBHOOK` | `20` per window |
| `RATE_LIMIT_WEBHOOK_WINDOW_MS` | `60000` |
| `APP_CACHE_TTL_MS` | `60000` |
| `EVENT_DISPATCHER_BATCH_SIZE` | `50` |
| `EVENT_DISPATCHER_MAX_BATCHES_PER_RUN` | `5` |
| `LOG_LEVEL` | `info` |

### Dev/test defaults

For local development, `runtime.exs:170-179` sets safe defaults:

```elixir
config :debt_stalker, :jwt_secret, "dev-jwt-secret-not-for-production"
config :debt_stalker, :admin_password, System.get_env("ADMIN_PASSWORD", "admin123")
config :debt_stalker, :webhook_secret, System.get_env("WEBHOOK_SECRET", "dev-webhook-secret")
config :debt_stalker, :require_webhook_signature, false
config :debt_stalker, DebtStalkerWeb.Endpoint,
  live_view: [signing_salt: "dev-live-view-signing-salt"]
```

---

## 6. Health Probes

**File:** `lib/debt_stalker_web/controllers/api/health_controller.ex`

| Endpoint | Purpose | Implementation |
|----------|---------|----------------|
| `/api/health` | Legacy health | Returns `{"status": "healthy"}` |
| `/api/health/live` | Liveness | Returns 200 if BEAM is up |
| `/api/health/ready` | Readiness | Executes `SELECT 1`; returns 200 `{"status": "ready"}` or 503 `{"status": "not_ready"}` |

The web deployment uses both readiness and liveness probes; the worker deployment uses only an exec liveness probe.

---

## 7. Operational Flow

```mermaid
flowchart LR
    Dev[Developer push/PR] --> CI[CI quality + k8s dry-run + secret scan]
    CI --> PRReview[rs-guard + CodeRabbit]
    PRReview --> Merge[Merge to main]
    Merge --> CD[CD build image]
    CD --> Approve[Manual approve_deploy]
    Approve --> Migrate[kubectl apply migration-job.yaml]
    Migrate --> Web[kubectl apply deployment-web.yaml]
    Migrate --> Worker[kubectl apply deployment-worker.yaml]
    Web --> Service[kubectl apply service.yaml]
    Worker --> HPA[kubectl apply hpa-worker.yaml]
```

---

## 8. Operational Gaps

| # | Issue | Severity | Evidence |
|---|-------|----------|----------|
| 1 | **Migration Job has fixed name** | High (blocks redeploy) | `k8s/migration-job.yaml:4` uses `name: debt-stalker-migrate`; no `generateName` or cleanup. CD step `kubectl wait ... job/debt-stalker-migrate` will fail on re-deploy. |
| 2 | **CD approval condition compares boolean to string** | High (deploy never runs) | `.github/workflows/cd.yml:69` checks `github.event.inputs.approve_deploy == 'true'`, but the input is `type: boolean`. |
| 3 | **Production Secret manifest is incomplete** | High (pod crash) | `k8s/secret.yaml` omits `SESSION_SIGNING_SALT`, `ADMIN_PASSWORD`, `LIVE_VIEW_SIGNING_SALT`, all required by `config/runtime.exs:45, :70, :123`. |
| 4 | **Deployments use mutable `:latest` tag** | Medium | `k8s/deployment-web.yaml:23` and `k8s/deployment-worker.yaml:23` reference `ghcr.io/igmarin/debt-stalker:latest`. CD outputs digest/tags but never patches them into the manifests. |
| 5 | **Placeholder secrets committed** | Medium | `k8s/secret.yaml:9-13` contains placeholder values. While commented to override, this is risky and may be flagged by scanners. |
| 6 | **k8s dry-run is structural only** | Low | `.github/workflows/ci.yml:104-141` validates YAML shape with PyYAML, not `kubectl apply --dry-run=client`. |
| 7 | **No Ingress / TLS manifest** | Medium | Only a ClusterIP service is provided. Production needs an Ingress and TLS termination. |
| 8 | **Dockerfile runtime package mismatch** | Low | `Dockerfile:47` installs `libncurses5`; Debian Bookworm typically provides `libncurses6`. |
| 9 | **Rate limit trusts X-Forwarded-For** | Medium | `lib/debt_stalker_web/plugs/rate_limit.ex:66-73` uses leftmost proxy header without validation. |
| 10 | **Worker liveness probe uses temporary node** | Low | `k8s/deployment-worker.yaml:42-43` uses `bin/debt_stalker rpc`; a dedicated health command or exec check would be more conventional. |

---

## 9. Quick Operational Fixes

1. **Use `generateName` for the migration Job** or add a pre-apply delete step.
2. **Fix CD approval condition** to `github.event.inputs.approve_deploy == true`.
3. **Add missing secrets** to `k8s/secret.yaml` or switch to Sealed Secrets / External Secrets Operator.
4. **Pin image tags** in deployments to the SHA digest produced by the build step.
5. **Add an Ingress manifest** with TLS.
6. **Use `kubectl apply --dry-run=client`** in CI for schema validation.
7. **Validate proxy headers** in the rate-limit plug or move rate limiting to the Ingress.
