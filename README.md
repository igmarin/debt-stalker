# Debt Stalker

Multi-country credit-application core for a fintech operating in 6 countries (ES, PT, IT, MX, CO, BR). Built with Elixir + Phoenix + PostgreSQL + Oban + LiveView.

## Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   LiveView  │     │   REST API       │     │   Webhooks      │
│   (Browser) │     │   (JSON + JWT)   │     │   (Provider)    │
└──────┬──────┘     └────────┬─────────┘     └────────┬────────┘
       │                     │                         │
       └──────────┬──────────┴─────────────────────────┘
                  │
       ┌──────────▼──────────┐
       │  Applications       │ ← Domain context (create, get, list, update_status)
       │  (State Machine)    │
       └──────────┬──────────┘
                  │
    ┌─────────────┼───────────────────┐
    │             │                   │
    ▼             ▼                   ▼
┌────────┐  ┌──────────┐  ┌─────────────────┐
│Countries│  │Providers │  │  Outbox/Workers  │
│(ES, MX) │  │(Simulated)│  │  (Oban + PG)    │
└────────┘  └──────────┘  └─────────────────┘
```

**Key Design Decisions:**
- **Async outbox pattern**: Postgres triggers → `application_events` table → `EventDispatcherWorker` drains with `FOR UPDATE SKIP LOCKED` → specialized workers
- **Country modules**: Pluggable country rules via behaviour (ES: DNI + threshold, MX: CURP + debt ratio)
- **Provider adapters**: Simulated, deterministic responses; normalized output never exposes raw payloads
- **PII at rest**: `identity_document` encrypted with AES-256-GCM (Cloak); API/logs show last-4 only
- **Cursor pagination**: No unbounded OFFSET; stable cursor based on (application_date, id)
- **Status machine**: submitted → pending_risk → approved/rejected/additional_review; all transitions validated + audited

## Quick Start

```bash
# Prerequisites: Elixir 1.18.x, Erlang/OTP 27.x, Docker

# Start Postgres
make up

# Setup (deps + DB + migrations + seed)
make setup

# Run Phoenix server
make run
```

Visit [`localhost:4000`](http://localhost:4000) for the LiveView UI.

### API Usage

```bash
# Get a JWT token
curl -X POST http://localhost:4000/api/auth/token -H 'Content-Type: application/json' -d '{"role":"update"}'

# Create an application
curl -X POST http://localhost:4000/api/applications \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{"country":"ES","full_name":"Juan Garcia","identity_document":"12345678Z","requested_amount":"5000","monthly_income":"2000"}'

# List applications
curl http://localhost:4000/api/applications -H 'Authorization: Bearer <token>'

# Get single application
curl http://localhost:4000/api/applications/<id> -H 'Authorization: Bearer <token>'

# Update status
curl -X PATCH http://localhost:4000/api/applications/<id>/status \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{"status":"pending_risk"}'
```

## Development

```bash
make test       # Run test suite
make lint       # Credo strict
make dialyzer   # Type checking
make check      # format + credo + dialyzer
make ci         # Full CI pipeline locally
make docs       # Generate ExDoc
make format     # Format code
make up         # Start Postgres (Docker Compose)
make down       # Stop Postgres
make seed       # Create 10 demo apps + print JWT tokens
```

## Security

- **JWT authentication**: All API endpoints (except `/api/auth/token`) require Bearer token
- **Role-based access**: `read` (list/get) vs `update` (create/patch status)
- **PII encryption**: `identity_document` encrypted at rest with AES-256-GCM via Cloak
- **Redaction**: API responses and logs show document as `****XXXX` (last-4 only)
- **Webhook verification**: HMAC-SHA256 signature validation (configurable)

## Scalability

- **Oban workers**: Async processing with configurable queues (default:10, events:20, notifications:10)
- **SKIP LOCKED**: Event dispatcher uses advisory locks for concurrent-safe consumption
- **Cursor pagination**: Stable, efficient pagination without OFFSET
- **Kubernetes-ready**: k8s manifests in `k8s/` directory (namespace, deployment, service, configmap, secrets, migration job)

## Documentation

- [Master Plan](docs/master-plan.md)
- [Requirements](docs/requirements.md)
- [Phase 0 — Foundation](docs/phases/phase-0.md)
- [Phase 1 — ES+MX Vertical](docs/phases/phase-1.md)
- [Phase 2 — Resilience](docs/phases/phase-2.md)
- [AGENTS.md](AGENTS.md) — Development conventions
- [ADRs](docs/adr/) — Architecture Decision Records
- [CHANGELOG](CHANGELOG.md) — Release history

## License

See [LICENSE](LICENSE).
