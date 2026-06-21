# Phase 2 — Resilience, Observability & Production Hardening

> **Parent:** `docs/master-plan.md` · **Builds on:** `docs/phases/phase-1.md`
> **Status:** Planning artifact only. No code written.
> **Goal:** Take the green ES + MX vertical slice and make it **production-credible** — observable, resilient under failure, and actually deployable with secrets and PII protected.
> **Structure:** Two sub-tracks — **2a Resilience & Observability** and **2b Production & Security**. They can run in parallel after Phase 1 contracts are frozen; the phase gate requires both.

---

## 1. Phase Goal & Boundaries

**Entry condition:** Phase 1 Definition of Done fully met; all Global Architecture invariants hold; Code Organization Contract (master plan §4.8) enforced; Postman collection has all Phase 1 endpoints.

**In scope:**
- *2a:* telemetry + metrics, dashboards, provider circuit breakers + retry budgets, dead-letter handling, rate limiting, app-level detail caching with PubSub invalidation.
- *2b:* real Kubernetes deployment (probes, HPA, ingress), CI/CD pipeline, secrets management, log-scrubbing audit. (PII encryption is already in place from Phase 1.)
- *Both tracks:* Postman collection updated with failure scenarios; CHANGELOG + ADRs + Phase Report.

**Out of scope (deferred to Phase 3–4):** new countries (PT/IT/CO/BR); table partitioning; read replicas; archiving jobs; load testing at millions of rows. (Partitioning/replicas are Phase 4; this phase makes the *single-region* deployment solid first.)

**Why bundle 2a + 2b:** Resilience and production-readiness are mutually reinforcing — circuit breakers and DLQ are only meaningful once metrics/alerts exist, and a real deployment forces secrets + encryption + probes to be real. Keeping them in one phase with two tracks lets observability land just before (or alongside) the first real deploy.

---

## 2. Product Perspective

### 2.1 Personas
- **On-call / SRE** — needs metrics, alerts, dashboards, and safe rollbacks.
- **Security/compliance reviewer** — needs PII encrypted at rest, secrets managed, logs scrubbed.
- **Operations reviewer** (from Phase 1) — benefits from faster reads (cache) and fewer stuck jobs (DLQ).

### 2.2 User Stories & Acceptance Criteria

**Track 2a — Resilience & Observability**

**US-10 — Metrics & dashboards**
- **AC10.1** `:telemetry` events emitted for HTTP requests, Ecto queries, Oban jobs, provider calls, and status transitions.
- **AC10.2** Metrics exported (Prometheus endpoint or StatsD) and visible on a dashboard (LiveDashboard at minimum; Grafana optional).
- **AC10.3** Key business metrics tracked: applications created/min, jobs processed/failed, provider latency, transition counts by status.

**US-11 — Provider resilience**
- **AC11.1** Provider calls are wrapped in a circuit breaker; repeated failures open the circuit and fail fast.
- **AC11.2** A retry budget/backoff governs transient provider errors; exhaustion routes the application to `provider_error`.
- **AC11.3** Circuit state changes are logged + emitted as telemetry.

**US-12 — Dead-letter handling**
- **AC12.1** Oban jobs that exhaust retries are captured in a dead-letter view/table with `application_id`, job type, and last error.
- **AC12.2** A dead-lettered job can be inspected and manually re-enqueued.
- **AC12.3** No dead-lettered job silently disappears or duplicates side effects on replay.

**US-13 — Rate limiting**
- **AC13.1** Auth token issuance and webhook endpoints are rate-limited per client/IP.
- **AC13.2** Exceeding the limit returns `429` with a retry hint; limits are configurable via env.

**US-14 — Application-level caching**
- **AC14.1** Application detail reads are cache-backed.
- **AC14.2** A status update **invalidates** the cached detail (PubSub-driven invalidation).
- **AC14.3** Cache hit/miss is observable in metrics/logs.

**Track 2b — Production & Security**

**US-15 — Real Kubernetes deployment**
- **AC15.1** Web + worker deployments run in a real cluster (kind/minikube acceptable for the gate) with liveness + readiness probes.
- **AC15.2** A migration job runs before/with rollout; rollout supports rollback.
- **AC15.3** Horizontal scaling of the worker deployment increases throughput without code changes (demonstrates the concurrency requirement at the infra level).

**US-16 — CI/CD pipeline**
- **AC16.1** CI runs format + compile-warnings-as-errors + full test suite + `kubectl --dry-run` on every PR.
- **AC16.2** A build produces a container image; a deploy step (manual approval ok) ships it to the cluster.

**US-17 — PII encryption verification** (encryption is in place from Phase 1)
- **AC17.1** Verify `identity_document` is encrypted at rest (ciphertext in DB); `identity_document_hash` remains for lookup.
- **AC17.2** Encryption keys are sourced from secrets management in production (k8s secrets), never source/config files. Dev key in `config/dev.exs` is acceptable.
- **AC17.3** API responses + logs remain redacted (Phase 1 behaviour preserved).

**US-18 — Secrets management & log scrubbing**
- **AC18.1** JWT secret, webhook secret, DB credentials, and encryption keys are sourced from a secrets manager / k8s secrets, never committed.
- **AC18.2** A log-scrubbing audit confirms no PII, secrets, or raw provider payloads appear in any log path.
- **AC18.3** Production log level + structured format documented.

### 2.3 Demo Script
1. Deploy to a local cluster; show liveness/readiness probes passing and a worker `replicas` bump increasing throughput.
2. Open the dashboard; create applications and watch metrics move; force a provider failure and watch the circuit open + a job dead-letter, then re-enqueue it.
3. Hammer the token endpoint to trigger `429`.
4. Inspect the DB to show `identity_document` is ciphertext while the API/log still shows last-4 only.
5. Open Postman collection → run the failure scenarios (429 rate limit, provider failure, DLQ inspection).

---

## 3. Technical Scope

### 3.1 Track 2a
- `:telemetry` handlers + a metrics reporter (`telemetry_metrics_prometheus` or StatsD); LiveDashboard wired.
- Circuit breaker around provider adapters (e.g., `:fuse` or a small GenServer breaker) + backoff/retry budget in the provider boundary.
- Dead-letter mechanism: Oban error handling → DLQ table or Oban Pro-style discarded-jobs view + a re-enqueue helper.
- Rate limiter plug (e.g., `hammer` / `plug_attack`) on token + webhook routes.
- App-level cache (Cachex or ETS) for `get_application/1`, invalidated on status-change PubSub events.

### 3.2 Track 2b
- k8s: liveness/readiness endpoints, resource requests/limits, HPA on the worker deployment, ingress + TLS placeholder, migration `Job`/init step.
- CI/CD: pipeline stages (lint → test → dry-run → build image → deploy w/ approval); image registry config.
- Encryption: `Cloak`/`cloak_ecto` encrypted fields (in place from Phase 1); verify ciphertext at rest; production key from k8s secret; verify hash-based lookup still works.
- Secrets: k8s `Secret` (or external manager) wiring; remove any placeholder secrets from config; document the env contract.
- Log scrubbing: centralized redaction reviewed across controllers, workers, provider boundary, and telemetry handlers.

### 3.3 Postman Collection Updates

The existing `docs/postman/debt-stalker.json` (populated in Phase 1) gets new folders for Phase 2 failure scenarios:

| Folder | Endpoints | Purpose |
|--------|-----------|---------|
| `Rate Limiting` | `POST /api/auth/token` (x100 rapid), `POST /api/webhooks/provider-confirmations` (x100 rapid) | Verify 429 responses + retry hints |
| `Provider Failures` | `POST /api/applications` (with forced provider error scenario) | Verify `provider_error` status + circuit breaker |
| `DLQ Inspection` | (if admin endpoint exists) `GET /api/admin/dead-letters` | Inspect dead-lettered jobs |

---

## 4. Definition of Done

**Track 2a**
- [ ] Telemetry events + exported metrics + a working dashboard.
- [ ] Provider circuit breaker + retry budget with state telemetry.
- [ ] Dead-letter capture + inspect + safe re-enqueue.
- [ ] Rate limiting on token + webhook endpoints (`429` + configurable).
- [ ] App-level detail cache with PubSub invalidation; hit/miss observable.

**Track 2b**
- [ ] Web + worker deployed to a real cluster with liveness/readiness probes; rollback works.
- [ ] Worker horizontal scaling demonstrably increases throughput.
- [ ] CI/CD: lint + tests + dry-run on PRs; image build + deploy step.
- [ ] PII encryption verified at rest (from Phase 1); production keys from secrets; responses/logs still redacted.
- [ ] Secrets sourced from a manager/k8s secrets; nothing committed.
- [ ] Log-scrubbing audit passed (no PII/secrets/raw payloads in any log path).

**Quality Gates (both tracks)**
- [ ] `mix format --check-formatted` passes.
- [ ] `mix credo --strict` passes.
- [ ] `mix dialyzer` passes.
- [ ] `mix test` passes (including new Phase 2 tests).
- [ ] `mix docs` generates without warnings.
- [ ] Code Organization Contract (master plan §4.8) enforced on all new modules.

**Documentation & Artifacts**
- [ ] Postman collection updated with Phase 2 failure scenarios (§3.3).
- [ ] CHANGELOG.md updated with Phase 2 entry (Keep-a-Changelog format).
- [ ] ADRs written for significant decisions (circuit breaker library, encryption approach, DLQ strategy, rate limiter choice).
- [ ] Phase 2 Completion Report written to `docs/phases/phase-2-report.md`.

**Phase gate:** both tracks' DoD true; the system is deployable to a real cluster with observability and PII protection in place.

---

## 5. Phase 2 Risks

| Risk | Likelihood | Impact | Mitigation | Owner |
|------|------------|--------|------------|-------|
| Encryption key rotation breaks reads | Low | High | Document key rotation procedure; Cloak supports multi-key migration; test rotation in staging | Tech Lead |
| Circuit breaker hides real outages | Med | Med | Emit telemetry + alerts on open circuits; document thresholds | Backend dev |
| Real k8s deploy reveals config gaps | Med | Med | Use kind/minikube in CI to catch early; keep env contract in README | DevOps |
| Rate limits block legitimate demo traffic | Low | Low | Generous configurable defaults; documented | Backend dev |
| Secrets accidentally committed | Low | High | Pre-commit secret scan in CI; secret manager only | DevOps |
| DLQ replay duplicates side effects | Low | Med | Idempotency from Phase 1 preserved; replay keyed on event/job id | Backend dev |

---

## 6. Task Seeds (Spec-Driven, ticket-ready)

> Import under a "Phase 2" milestone via the `github-issue` skill. `2a` and `2b` may proceed in parallel.
>
> **TDD-gated tasks** (`[OBS]`, `[RES]`, `[API]`, `[PERF]`, `[SEC]`): Each follows the Spec-Driven Development loop (master plan §8.1):
> 1. Write failing test for the acceptance criteria → 2. Run → verify FAILS for right reason → 3. Implement → 4. Run → verify PASSES → 5. Full suite green (`mix format && mix credo --strict && mix dialyzer && mix test`) → 6. rs-guard local review → 7. Iterate (max 3 rounds) → 8. Commit when APPROVE/COMMENT.
>
> **TDD-exempt tasks** (`[CHORE]`, `[OPS]`, `[CI]`, `[CD]`, `[DOCS]`): No test-first gate, but tests included where applicable. Still go through rs-guard review loop (steps 6-8).

### Track 2a — Resilience & Observability

- **[CHORE] T0.0 — Create feature branch** · *AC:* branch created from `main` for this issue. Each issue gets its own branch + PR (tagged `phase-2`).
  *Review:* rs-guard on branch creation (no code yet, skip).

- **[OBS] T10.1 — Telemetry events across HTTP/Ecto/Oban/provider/transitions**
  *TDD:* (a) Write failing tests: `:telemetry.execute` is called with correct event names + measurements + metadata for HTTP requests, Ecto queries, Oban jobs, provider calls, and status transitions. Use `:telemetry_test` or attach a test handler. (b) Run → fail (no handlers attached). (c) Implement telemetry handlers. (d) Run → pass.
  *Review:* rs-guard → iterate (max 3).
  *AC:* events emitted with correct measurements/metadata; tests assert emission.

- **[OBS] T10.2 — Metrics reporter + LiveDashboard**
  *TDD:* (a) Write failing test: a Prometheus/StatsD endpoint exposes the metrics; LiveDashboard is wired. (b) Run → fail. (c) Implement reporter + dashboard wiring. (d) Run → pass.
  *Review:* rs-guard → iterate (max 3).
  *AC:* Prometheus/StatsD endpoint exposes the metrics; dashboard shows them.

- **[OBS] T10.3 — Business metrics (created/min, jobs ok/fail, provider latency, transitions by status)**
  *TDD:* (a) Write failing tests: business metrics are present in the metrics output with correct values. (b) Run → fail. (c) Implement business metric handlers. (d) Run → pass.
  *Review:* rs-guard → iterate (max 3).
  *AC:* metrics present + documented.

- **[RES] T11.1 — Provider circuit breaker + retry budget**
  *TDD:* (a) Write failing tests using Mox: circuit opens after N consecutive failures; open circuit fails fast with `{:error, :circuit_open}`; retry budget with exponential backoff; exhaustion → `provider_error` status; circuit state changes emitted as telemetry. (b) Run → fail. (c) Implement circuit breaker + retry budget. (d) Run → pass.
  *Review:* rs-guard → iterate (max 3).
  *AC:* opens after threshold; fails fast; exhaustion → `provider_error`; state telemetry.

- **[RES] T12.1 — Dead-letter capture for exhausted Oban jobs**
  *TDD:* (a) Write failing tests using `Oban.Testing`: a job that exhausts retries is captured in DLQ table with `application_id`, job type, and last error; no silent disappearance. (b) Run → fail. (c) Implement DLQ capture. (d) Run → pass.
  *Review:* rs-guard → iterate (max 3).
  *AC:* exhausted jobs recorded with app id/type/error.

- **[RES] T12.2 — DLQ inspect + safe re-enqueue**
  *TDD:* (a) Write failing tests: a dead-lettered job can be listed; re-enqueue creates a new Oban job; replay does not duplicate side effects (idempotency from Phase 1 preserved). (b) Run → fail. (c) Implement inspect + re-enqueue. (d) Run → pass.
  *Review:* rs-guard → iterate (max 3).
  *AC:* re-enqueue does not duplicate side effects.

- **[API] T13.1 — Rate limiting on token + webhook endpoints**
  *TDD:* (a) Write failing tests: N rapid requests to `/api/auth/token` → first N succeed, N+1 returns `429` with `Retry-After` header; N rapid webhook requests → same pattern; limits configurable via env. (b) Run → fail. (c) Implement rate limiter plug. (d) Run → pass.
  *Review:* rs-guard → iterate (max 3).
  *Postman:* Add `Rate Limiting` folder → `POST /api/auth/token` (x100 rapid), `POST /api/webhooks/provider-confirmations` (x100 rapid) with 429 response example.
  *AC:* `429` past limit; configurable via env; tests cover limit + reset.

- **[PERF] T14.1 — App-level detail cache + PubSub invalidation**
  *TDD:* (a) Write failing tests: repeat `get_application/1` hits cache (assert cache hit metric/log); status update via `update_status/3` invalidates cache (next read fetches fresh); PubSub broadcast triggers invalidation; hit/miss observable. (b) Run → fail. (c) Implement cache + invalidation. (d) Run → pass.
  *Review:* rs-guard → iterate (max 3).
  *AC:* cache hit on repeat read; status update invalidates; hit/miss observable.

### Track 2b — Production & Security

- **[OPS] T15.1 — Liveness/readiness probes + resource limits** · *AC:* probes pass in-cluster; pods restart on failure; resource requests/limits set.
  *Review:* rs-guard on k8s YAML + health endpoint code.

- **[OPS] T15.2 — Real deploy to kind/minikube + migration job + rollback** · *AC:* rollout + rollback verified; migration runs before serving.
  *Review:* rs-guard on deployment scripts + migration job YAML.

- **[OPS] T15.3 — Worker HPA / scaling demo** · *AC:* increasing replicas raises processed-jobs throughput; no code change; HPA config documented.
  *Review:* rs-guard on HPA YAML + demo script.

- **[CI] T16.1 — CI: lint + warnings-as-errors + tests + k8s dry-run on PRs** · *AC:* pipeline gates merges; all stages run on every PR.
  *Review:* rs-guard on CI workflow YAML.

- **[CD] T16.2 — Image build + deploy stage (manual approval)** · *AC:* image published to registry; deploy ships to cluster; manual approval gate works.
  *Review:* rs-guard on CD workflow YAML + Dockerfile.

- **[SEC] T17.1 — PII encryption verification + production key wiring** (encryption is in place from Phase 1)
  *TDD:* (a) Write failing test: `identity_document` is ciphertext in DB (assert via raw SQL query); hash lookup still works; API responses still show last-4 only; logs still redacted. (b) Run → pass (should already pass from Phase 1). (c) If any gaps, fix. (d) Run → pass.
  *Review:* rs-guard → iterate (max 3).
  *AC:* `identity_document` ciphertext at rest verified; hash lookup intact; responses/logs redacted; production encryption key sourced from k8s secret (not config file).

- ~~**[SEC] T17.2 — Backfill migration (expand-contract)**~~ — **Removed.** PII is encrypted from day one in Phase 1, so no backfill migration is needed.

- **[SEC] T18.1 — Secrets management wiring** · *AC:* all secrets from k8s/secret manager; none committed; env contract documented in README.
  *Review:* rs-guard on config files + k8s secret YAML.

- **[SEC] T18.2 — Log-scrubbing audit**
  *TDD:* (a) Write failing test: a test that exercises every log path (creation, validation failure, provider call, job, webhook, transition) and asserts no PII/secrets/raw payloads appear in captured log output. (b) Run → fail (or pass if Phase 1 redaction is solid). (c) Fix any leaks found. (d) Run → pass.
  *Review:* rs-guard → iterate (max 3).
  *AC:* documented review proving no PII/secrets/raw payloads in any log path; production log level set.

### Phase Closeout

- **[DOCS] T19.1 — Postman collection finalization** · *AC:* `docs/postman/debt-stalker.json` updated with Phase 2 failure scenarios (§3.3); all new endpoints have example requests/responses; collection is importable.
  *Review:* rs-guard on JSON file.

- **[DOCS] T19.2 — CHANGELOG + ADRs + Phase 2 Completion Report** · *AC:* CHANGELOG.md updated with Phase 2 entry (Added/Changed/Fixed/Security); ADRs written for: circuit breaker library choice, DLQ strategy, rate limiter choice; `docs/phases/phase-2-report.md` written with: what was built, decisions made, risks materialized, test status, deferred items, next-agent instructions, Postman collection reference. (Encryption ADR is in Phase 1.)
  *Review:* rs-guard on all doc files.

---

## 7. Task Dependency Graph

```text
T0.0 (branch)
  ├─ Track 2a (parallel)
  │    ├─ T10.1 (telemetry events)
  │    │    ├─ T10.2 (metrics reporter + dashboard)
  │    │    └─ T10.3 (business metrics)
  │    ├─ T11.1 (circuit breaker) ← depends on T10.1 (telemetry)
  │    ├─ T12.1 (DLQ capture) ← depends on Phase 1 workers
  │    │    └─ T12.2 (DLQ inspect + re-enqueue)
  │    ├─ T13.1 (rate limiting) ← independent
  │    └─ T14.1 (app cache) ← depends on Phase 1 get_application + PubSub
  │
  └─ Track 2b (parallel)
       ├─ T15.1 (probes + resource limits) ← independent
       │    └─ T15.2 (real deploy + migration + rollback) ← depends on T15.1
       │         └─ T15.3 (worker HPA demo) ← depends on T15.2
       ├─ T16.1 (CI pipeline) ← independent
       │    └─ T16.2 (CD image build + deploy) ← depends on T16.1 + T15.2
       ├─ T17.1 (PII encryption verification + prod key) ← independent (encryption from Phase 1)
       ├─ T18.1 (secrets management) ← independent
       └─ T18.2 (log-scrubbing audit) ← depends on T10.1 (all log paths exercised)

  T19.1 (Postman finalization) ← depends on T13.1 + all API tasks
  T19.2 (CHANGELOG + ADRs + Report) ← depends on all above
```

**Critical path (2a):** T0.0 → T10.1 → T11.1 → T12.1 → T12.2
**Critical path (2b):** T0.0 → T15.1 → T15.2 → T16.2
**Phase gate:** both tracks complete + T19.1 + T19.2

**Parallelizable:** Track 2a and 2b are fully independent. Within 2a, T13.1 (rate limiting) and T14.1 (cache) are independent of T10.x/T11.x. Within 2b, T17.1 (encryption), T18.1 (secrets), and T15.1 (probes) can all start immediately.
