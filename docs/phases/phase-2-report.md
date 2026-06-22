# Phase 2 Completion Report — Resilience, Observability & Production Hardening

> **Date:** 2026-06-22 · **Parent:** `docs/master-plan.md` · **Phase doc:** `docs/phases/phase-2.md`

---

## 1. What Was Built

### Track 2a — Resilience & Observability

| Task | Issue | PR | Description |
|------|-------|-----|-------------|
| T10.1 | #43 | #89 | Telemetry events (HTTP, Ecto, Oban, provider, transitions) |
| T10.2 | #44 | #89 | Prometheus metrics exporter (port 9568) + LiveDashboard |
| T11.1 | #45 | #91 | Dead-letter table + DeadLetter context + Oban exhaustion capture |
| T11.2 | #46 | #91 | DLQ admin API (list/replay) |
| T12.1 | #47 | #93 | Provider circuit breaker (custom GenServer) |
| T12.2 | #48 | #93 | Circuit breaker telemetry + half-open probe |
| F1 | #97 | #103 | Fix circuit breaker half-open concurrency bug |
| F2 | #98 | #104 | Fix provider_error audited Multi insert |
| T13.1 | #49 | #106 | Rate limiting plug + ADR-0007 + Postman folder |
| T14.1 | #50 | #107 | App-level cache (Cachex) + PubSub invalidation |

### Track 2b — Production & Security

| Task | Issue | PR | Description |
|------|-------|-----|-------------|
| F3 | #99 | #113 | Dockerfile + mix release config |
| T15.1 | #57 | #114 | Liveness/readiness probes + resource limits |
| T15.2 | #58 | #114 | Web/worker split + deploy script |
| T15.3 | #59 | #114 | Worker HPA + scaling demo |
| T16.1 | #101 | #116 | CI k8s manifest dry-run gate (F5) |
| T16.2 | #61 | #116 | CD image build + deploy (manual approval) |
| T17.1 | #62 | #117 | PII ciphertext-at-rest verification test |
| T18.1 | #64 | #118 | Secrets management wiring + env contract |
| T18.2 | #65 | #118 | Log-scrubbing audit (7 tests, all log paths) |
| F6 | #102 | #118 | Gitleaks secret-scanning CI |

### Closeout

| Task | Issue | PR | Description |
|------|-------|-----|-------------|
| T19.1 | #66 | #119 | Postman collection finalization (failure scenarios) |
| T19.2 | #67 | #119 | CHANGELOG + ADRs 0005-0007 + this report |
| F4 | #100 | #119 | Doc fixes: phase-2.md status, handoff T17.2, ADRs |

---

## 2. Decisions Made (ADRs)

| ADR | Title | Decision |
|-----|-------|----------|
| [ADR-0005](../adr/0005-circuit-breaker-choice.md) | Circuit breaker choice | Custom GenServer over `:fuse` (fine-grained half-open control, telemetry, no external dep) |
| [ADR-0006](../adr/0006-dlq-strategy.md) | DLQ strategy | Custom `dead_letter_jobs` table + Oban telemetry capture over Oban Pro (open-source, full control) |
| [ADR-0007](../adr/0007-rate-limiter-choice.md) | Rate limiter choice | Custom token-bucket plug over Hammer (simple, no Redis dep, per-IP sliding window) |

---

## 3. Risks Materialized vs. Risk Register

| Risk (from master plan §7) | Materialized? | Mitigation Applied |
|----------------------------|--------------|-------------------|
| Provider cascading failure | No (circuit breaker prevents) | Custom GenServer circuit breaker (open/half-open/closed) |
| Oban job exhaustion | No (DLQ captures) | dead_letter_jobs table + telemetry handler |
| k8s manifests drift | No (CI gate) | Python YAML validation in CI on every PR |
| Secrets accidentally committed | No (gitleaks CI) | Gitleaks action with allowlist for dev/test placeholders |
| PII leak in logs | No (audit passed) | 7 log-scrubbing tests covering all log paths |
| Rate limit bypass | No (plug enforced) | Token-bucket plug on auth + webhook endpoints |
| Cache stampede | No (Cachex get-or-set) | Application-level cache with PubSub invalidation |
| Circuit breaker half-open concurrency | Yes (F1) | Fixed via Process.monitor slot reclamation |

---

## 4. Test Status

- **Total tests:** 500 ExUnit tests total, including 2 property-based tests, in the latest continuation verification
- **Failures:** 0
- **Coverage gate:** 85% (enforced in CI)
- **Quality gates:** format, compile (warnings-as-errors), credo (strict), dialyzer, test — all green
- **Latest stabilization:** authorized API/UI surfaces show full names consistently; identity documents remain redacted and logs remain scrubbed
- **CI checks:** Quality Checks, k8s Manifest Dry-Run, Secret Scan (gitleaks), Semgrep, rs-guard (known v1.2.0 bug, ignored)

### Test breakdown by area:
- Phase 1 domain tests: ~200
- Phase 2 telemetry/metrics: ~30
- Circuit breaker: ~25
- DLQ: ~15
- Rate limiting: ~10
- Cache: ~10
- PII encryption at rest: 6
- Log-scrubbing audit: 7
- Health endpoints: 4
- Property-based: 2

---

## 5. Deferred Items

Items considered for Phase 2 but deferred to Phase 3/4:

| Item | Reason | Target |
|------|--------|--------|
| T17.2 (backfill migration) | PII encrypted from day one — no backfill needed | Closed (removed) |
| External secrets manager (Vault/AWS SM) | k8s Secrets sufficient for current scale | Phase 4 |
| Oban Pro upgrade | Custom DLQ table works well; Pro is paid | Phase 4 (if scale demands) |
| Multi-region k8s deployment | Single-region sufficient for ES+MX | Phase 4 |
| Provider retry with exponential backoff | Circuit breaker handles fail-fast; retry is in Oban | Phase 3 |
| Webhook signature rotation | Static HMAC secret sufficient | Phase 4 |
| Million-row hardening | MVP uses scale-ready primitives, but admin keyset search, dispatcher tuning, outbox lag alerts, and dashboard rollups need focused follow-up work | Follow-up PR / Phase 4 |

---

## 6. Next-Agent Instructions

### Key files to know:
- `lib/debt_stalker/providers/circuit_breaker.ex` — Custom circuit breaker GenServer
- `lib/debt_stalker/oban_telemetry_handler.ex` — DLQ capture via telemetry
- `lib/debt_stalker/dead_letter.ex` — DeadLetter context (list/replay)
- `lib/debt_stalker/cache_invalidator.ex` — PubSub cache invalidation
- `lib/debt_stalker_web/plugs/rate_limit_plug.ex` — Rate limiting plug
- `config/runtime.exs` — All prod config (secrets from env, fail-fast)
- `k8s/` — All k8s manifests (web/worker split, HPA, migration job)
- `.github/workflows/ci.yml` — CI: quality + k8s dry-run + gitleaks
- `.github/workflows/cd.yml` — CD: image build + deploy (manual approval)
- `Dockerfile` — Multi-stage build (hexpm/elixir → debian:bookworm-slim)
- `lib/debt_stalker/release.ex` — Prod release tasks (migrate, rollback)

### Patterns to follow:
- **Telemetry:** Emit `:telemetry` events for all significant operations. See existing patterns in `Applications`, `CircuitBreaker`, workers.
- **Error handling:** Use tagged tuples (`{:ok, _}`, `{:error, reason}`). Let transient errors crash (let-it-crash), catch permanent ones.
- **Testing:** TDD — write failing test first, implement, verify pass. Use `DataCase` for DB tests, `ConnCase` for API tests.
- **Credo:** Custom checks enforce architecture contracts. Run `mix credo --strict` before every commit.
- **Secrets:** Never commit secrets. All secrets from env vars. Gitleaks CI will catch accidental commits.

### Gotchas:
- `Credo.Check` modules are dev-only — keep custom checks in `test/support/credo_checks/`, not `lib/`.
- `kubectl --dry-run=client` still needs a cluster — CI uses Python YAML validation instead.
- `Ecto.UUID.dump!/1` needed for raw SQL queries with UUID columns (Postgres expects 16-byte binary).
- `OBAN_QUEUES=false` disables all Oban queues (for web deployment). Individual `OBAN_QUEUE_*` vars for worker.
- rs-guard v1.2.0 has a known bug — failures are expected and should be ignored.

---

## 7. Postman Collection Reference

The Postman collection is at `docs/postman/debt-stalker.json`. It includes:

| Folder | Endpoints | Phase |
|--------|-----------|-------|
| Health | GET /api/health, /api/health/live, /api/health/ready | 1+2 |
| Auth | POST /api/auth/token (read, update) | 1 |
| Applications | CRUD + status updates | 1 |
| Webhooks | POST /api/webhooks/provider-confirmations | 1 |
| Rate Limiting | Rapid-fire auth + webhook (expect 429) | 2 |
| Provider Failures | Create with forced error, get provider_error status | 2 |
| DLQ Inspection | List dead-letters, replay dead-letter job | 2 |

Import into Postman: File → Import → `docs/postman/debt-stalker.json`
