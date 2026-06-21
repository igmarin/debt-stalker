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
  - LiveView: applications list (filters, cursor pagination, PubSub), detail view, create form
  - Cloak encryption (AES-256-GCM) for identity_document at rest
  - PII redaction: API responses and logs show last-4 only
  - Cursor-based pagination (no unbounded OFFSET)
  - Status transitions: validated, recorded in status_transitions + audit_logs
  - Seeds: 10 demo applications (5 ES + 5 MX) + JWT token generation
  - k8s manifests: namespace, deployment, service, configmap, secrets, migration job
  - Postman collection: all Phase 1 endpoints with auto-token scripts
  - Concurrency integration test: verifies SKIP LOCKED parallel safety

- **Phase 2 (partial) — Resilience & Observability**
  - Telemetry events for HTTP, Ecto, Oban, provider calls, and status transitions
  - Prometheus metrics exporter (port 9568) and LiveDashboard (`/dev/dashboard` in dev)
  - Business metrics: applications created, Oban jobs, provider latency, status transitions
  - Dead-letter table, `DeadLetter` context, and Oban exhaustion capture wiring
  - Provider circuit breaker module wired into provider fetches
  - Test coverage gate at 85%
  - Custom Credo checks for architecture contracts: no country branching outside country/provider modules, public `@spec` enforcement, and no committed `IO.inspect`

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
