# Phase 2 — Resilience, Observability & Production Hardening

> **Parent:** `docs/master-plan.md` · **Builds on:** `docs/phases/phase-1.md`
> **Status:** Planning artifact only. No code written.
> **Goal:** Take the green ES + MX vertical slice and make it **production-credible** — observable, resilient under failure, and actually deployable with secrets and PII protected.
> **Structure:** Two sub-tracks — **2a Resilience & Observability** and **2b Production & Security**. They can run in parallel after Phase 1 contracts are frozen; the phase gate requires both.

---

## 1. Phase Goal & Boundaries

**Entry condition:** Phase 1 Definition of Done fully met; all Global Architecture invariants hold.

**In scope:**
- *2a:* telemetry + metrics, dashboards, provider circuit breakers + retry budgets, dead-letter handling, rate limiting, app-level detail caching with PubSub invalidation.
- *2b:* real Kubernetes deployment (probes, HPA, ingress), CI/CD pipeline, **PII encryption at rest**, secrets management, log-scrubbing audit.

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

**US-17 — PII encryption at rest**
- **AC17.1** `identity_document` (and other PII as identified) is encrypted at rest; `identity_document_hash` remains for lookup.
- **AC17.2** Encryption keys come from secrets management, never source/config files.
- **AC17.3** API responses + logs remain redacted (Phase 1 behaviour preserved); a migration encrypts existing rows.

**US-18 — Secrets management & log scrubbing**
- **AC18.1** JWT secret, webhook secret, DB credentials, and encryption keys are sourced from a secrets manager / k8s secrets, never committed.
- **AC18.2** A log-scrubbing audit confirms no PII, secrets, or raw provider payloads appear in any log path.
- **AC18.3** Production log level + structured format documented.

### 2.3 Demo Script
1. Deploy to a local cluster; show liveness/readiness probes passing and a worker `replicas` bump increasing throughput.
2. Open the dashboard; create applications and watch metrics move; force a provider failure and watch the circuit open + a job dead-letter, then re-enqueue it.
3. Hammer the token endpoint to trigger `429`.
4. Inspect the DB to show `identity_document` is ciphertext while the API/log still shows last-4 only.

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
- Encryption: `Cloak`/`cloak_ecto` (or equivalent) encrypted fields; key from secret; backfill migration; verify hash-based lookup still works.
- Secrets: k8s `Secret` (or external manager) wiring; remove any placeholder secrets from config; document the env contract.
- Log scrubbing: centralized redaction reviewed across controllers, workers, provider boundary, and telemetry handlers.

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
- [ ] PII encrypted at rest; keys from secrets; existing rows migrated; responses/logs still redacted.
- [ ] Secrets sourced from a manager/k8s secrets; nothing committed.
- [ ] Log-scrubbing audit passed (no PII/secrets/raw payloads in any log path).

**Phase gate:** both tracks' DoD true; the system is deployable to a real cluster with observability and PII protection in place.

---

## 5. Phase 2 Risks

| Risk | Likelihood | Impact | Mitigation | Owner |
|------|------------|--------|------------|-------|
| Encryption migration corrupts/locks data | Med | High | Expand-contract: add encrypted column → backfill in batches → switch reads → drop plaintext; test on a copy; keep hash for lookup | Tech Lead |
| Circuit breaker hides real outages | Med | Med | Emit telemetry + alerts on open circuits; document thresholds | Backend dev |
| Real k8s deploy reveals config gaps | Med | Med | Use kind/minikube in CI to catch early; keep env contract in README | DevOps |
| Rate limits block legitimate demo traffic | Low | Low | Generous configurable defaults; documented | Backend dev |
| Secrets accidentally committed | Low | High | Pre-commit secret scan in CI; secret manager only | DevOps |
| DLQ replay duplicates side effects | Low | Med | Idempotency from Phase 1 preserved; replay keyed on event/job id | Backend dev |

---

## 6. Task Seeds (TDD-ordered, ticket-ready)

> Import under a "Phase 2" milestone via the `github-issue` skill. Each implementation task implies the TDD quadruplet (failing test → fail → implement → pass). `2a` and `2b` may proceed in parallel.

**Track 2a — Resilience & Observability**
- **[CHORE] T0.0 — Create feature branch** · *AC:* branch `phase-2-resilience` from `main`.
- **[OBS] T10.1 — Telemetry events across HTTP/Ecto/Oban/provider/transitions** · *AC:* events emitted with correct measurements/metadata; tests assert emission.
- **[OBS] T10.2 — Metrics reporter + LiveDashboard** · *AC:* Prometheus/StatsD endpoint exposes the metrics; dashboard shows them.
- **[OBS] T10.3 — Business metrics (created/min, jobs ok/fail, provider latency, transitions by status)** · *AC:* metrics present + documented.
- **[RES] T11.1 — Provider circuit breaker + retry budget** · *AC:* opens after threshold; fails fast; exhaustion → `provider_error`; state telemetry.
- **[RES] T12.1 — Dead-letter capture for exhausted Oban jobs** · *AC:* exhausted jobs recorded with app id/type/error.
- **[RES] T12.2 — DLQ inspect + safe re-enqueue** · *AC:* re-enqueue does not duplicate side effects.
- **[API] T13.1 — Rate limiting on token + webhook endpoints** · *AC:* `429` past limit; configurable via env; tests cover limit + reset.
- **[PERF] T14.1 — App-level detail cache + PubSub invalidation** · *AC:* cache hit on repeat read; status update invalidates; hit/miss observable.

**Track 2b — Production & Security**
- **[OPS] T15.1 — Liveness/readiness probes + resource limits** · *AC:* probes pass in-cluster; pods restart on failure.
- **[OPS] T15.2 — Real deploy to kind/minikube + migration job + rollback** · *AC:* rollout + rollback verified; migration runs before serving.
- **[OPS] T15.3 — Worker HPA / scaling demo** · *AC:* increasing replicas raises processed-jobs throughput; no code change.
- **[CI] T16.1 — CI: lint + warnings-as-errors + tests + k8s dry-run on PRs** · *AC:* pipeline gates merges.
- **[CD] T16.2 — Image build + deploy stage (manual approval)** · *AC:* image published; deploy ships to cluster.
- **[SEC] T17.1 — Encrypted PII field + key from secret** · *AC:* `identity_document` ciphertext at rest; hash lookup intact; responses/logs redacted.
- **[SEC] T17.2 — Backfill migration (expand-contract)** · *AC:* existing rows encrypted in batches; reversible plan documented; tested on a copy.
- **[SEC] T18.1 — Secrets management wiring** · *AC:* all secrets from k8s/secret manager; none committed; env contract documented.
- **[SEC] T18.2 — Log-scrubbing audit** · *AC:* documented review proving no PII/secrets/raw payloads in any log path; production log level set.
