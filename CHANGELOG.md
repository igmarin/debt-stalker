# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Phase 1 — ES + MX Vertical Slice**
  - Credit application domain (create, get, list, update_status) with state machine
  - Country modules: ES (DNI validation, amount/income thresholds), MX (CURP validation, debt ratios)
  - Provider adapters: simulated ES + MX with deterministic responses
  - Async outbox pattern: Postgres triggers → application_events → EventDispatcherWorker (SKIP LOCKED)
  - RiskEvaluationWorker: automated risk assessment using country rules + provider scores
  - ExternalNotificationWorker: simulated notification delivery for terminal statuses
  - JWT authentication (Joken): read/update roles with AuthPlug + RequireRolePlug
  - REST API: `GET /api/health`, `/api/applications` (CRUD), `/api/applications/:id/status` (PATCH), `/api/auth/token`
  - Webhook endpoint: `/api/webhooks/provider-confirmations` with HMAC verification + idempotency
  - LiveView: applications list (filters, bounded page pagination, PubSub), detail view, create form
  - Cloak encryption (AES-256-GCM) for identity_document at rest
  - PII handling: identity documents are redacted to last-4 in API/UI responses and logs
  - API cursor-based pagination with capped limits
  - Status transitions: validated, recorded in status_transitions + audit_logs
  - Seeds: 10 demo applications (5 ES + 5 MX) + JWT token generation
  - k8s manifests: namespace, deployment, service, configmap, secrets, migration job
  - Postman collection: all Phase 1 endpoints with auto-token scripts
  - Concurrency integration test: verifies SKIP LOCKED parallel safety

- **Phase 2 — Resilience, Observability & Production Hardening**
  - Telemetry events for HTTP, Ecto, Oban, provider calls, and status transitions
  - Prometheus metrics exporter (port 9568) and LiveDashboard (`/dev/dashboard` in dev)
  - Business metrics: applications created, Oban jobs, provider latency, status transitions
  - Outbox dispatcher metrics: processed/failed event counts, remaining backlog, oldest-event age
  - Dead-letter table, `DeadLetter` context, and Oban exhaustion capture wiring
  - Provider circuit breaker module wired into provider fetches (custom GenServer, ADR-0005)
  - Test coverage gate at 85%
  - Custom Credo checks for architecture contracts: no country branching outside country/provider modules, public `@spec` enforcement, and no committed `IO.inspect`
  - Rate limiting plug (token bucket, per-IP sliding window) for auth and webhook endpoints (ADR-0007)
  - Application-level cache (Cachex) for get_application/1 with PubSub invalidation
  - Multi-stage Dockerfile + mix release config (hexpm/elixir builder, debian:bookworm-slim runtime)
  - lib/debt_stalker/release.ex with migrate/0, rollback/2, version/0 for prod release tasks
  - Web/worker deployment split: deployment-web.yaml (PHX_SERVER=true, OBAN_QUEUES=false) + deployment-worker.yaml (Oban queues)
  - Liveness/readiness probes: /api/health/live (no DB check) + /api/health/ready (DB check)
  - Worker HPA (autoscaling/v2, CPU 70% + memory 80%, min 2 max 10 replicas)
  - Deploy script (scripts/deploy.sh) with migration job, rollout status, and rollback support
  - Scaling demo script (scripts/scaling-demo.sh)
  - CI k8s manifest dry-run validation (Python YAML validation on every PR)
  - CD workflow (cd.yml): image build + push to GHCR, deploy with manual approval gate
  - PII ciphertext-at-rest verification test (raw SQL assertion, hash lookup, redaction)
  - Gitleaks secret-scanning CI job with .gitleaks.toml allowlist for dev/test placeholders
  - Log-scrubbing audit test (7 tests exercising every log path, no PII/secrets/raw payloads)
  - Environment variable contract documented in README
  - Postman collection: Rate Limiting, Provider Failures, DLQ Inspection folders
  - ADR-0005 (circuit breaker: custom GenServer), ADR-0006 (DLQ: table + telemetry), ADR-0007 (rate limiter)

### Fixed

- Circuit breaker half-open concurrency bug (F1/#97): single-probe enforcement via Process.monitor
- Provider_error audited Multi insert (F2/#98): audit_log now inserted atomically with status update
- Credo checks moved from lib/ to test/support/ to fix prod compilation (Credo.Check is dev-only)

### Security

- PII encryption verified at rest: identity_document is ciphertext in DB, hash lookup intact
- All secrets sourced from env vars (runtime.exs fail-fast in prod) + k8s Secrets
- Secret-scanning in CI (gitleaks) prevents accidental secret commits
- Log-scrubbing audit confirms no PII, secrets, or raw provider payloads in any log path

## [Unreleased] — Phase 2 Continuation

### Added

- **Issue #1 — README + Mermaid Architecture Diagrams**
  - Replaced ASCII architecture diagram with Mermaid flowchart
  - Added Mermaid sequence diagram for the async outbox flow
  - Expanded scalability section with concrete indexes, partitioning strategy,
    read replicas, and archiving notes
  - Fixed health endpoint documentation and linked ExDoc/ADRs/Postman

- **Issue #2 — Postman Collection + API Docs Accuracy**
  - Fixed health-check test assertion (`"healthy"` instead of `"ok"`)
  - Added `/api/health/live` and `/api/health/ready` requests
  - Added cursor-pagination flow example
  - Added `x-webhook-signature` header with HMAC pre-request script
  - Fixed token variables and removed non-existent DLQ admin endpoints
  - Added status transition examples for all terminal/review states

- **Issue #3 — Production/Security Hardening**
  - New `DebtStalker.Notifications` context for webhook events and outbound
    notification attempts
  - Removed `raw_payload` column from `webhook_events`; raw provider payloads
    are no longer persisted
  - Raw request body is now captured by `RawBodyReader` so webhook HMAC
    verification computes over the actual payload
  - `WEBHOOK_SECRET` is required in production and webhook signatures are
    required by default
  - `LIVE_VIEW_SIGNING_SALT` and `SESSION_SIGNING_SALT` are now env-driven
  - Authorized API responses and admin/applicant UI show `full_name` consistently
  - `ApplicationController.update_status/2` now handles unexpected changeset
    errors gracefully

### Fixed

- API cursor pagination now clamps invalid, zero, negative, and excessive limits
- Admin sort tests now assert row order instead of only checking that values render
- README now documents the authorized full-name policy, admin page-pagination tradeoff,
  and current MVP scale envelope
- EventDispatcherWorker now drains configurable multi-batch runs and emits backlog/lag metrics
- Added a partial outbox index for unprocessed event depth and lag queries

### Security

- Webhook HMAC verification now works correctly in production
- Raw provider payloads are no longer stored in `webhook_events`
- Identity documents stay redacted in API/UI responses and logs; full names are visible
  to authorized API/UI users and scrubbed from logs

## [0.1.0] - 2026-06-20

### Added

- **Phase 0 — Platform Foundation**
  - Phoenix 1.8 project scaffold with LiveView + Tailwind
  - PostgreSQL 16 via Docker Compose
  - Oban for async job processing
  - Cloak + Vault for encryption at rest
  - CI pipeline (format, compile warnings, credo strict, dialyzer, tests)
  - ExDoc documentation generation
  - Makefile with development commands
  - AGENTS.md with development conventions
  - ADR template + first ADR (Phoenix stack decision)
