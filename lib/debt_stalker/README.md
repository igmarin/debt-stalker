# Domain Contexts (`lib/debt_stalker/`)

This directory contains the **business logic** of Debt Stalker. It is organised as a set of Phoenix contexts, each with a clear bounded responsibility. The web layer (`DebtStalkerWeb`) and workers (`DebtStalker.Workers`) are only allowed to call these contexts; they must not reach into internal modules.

## Responsibilities

- Define the public API for credit applications, risk, audit, notifications, and dead-letter handling.
- Enforce business rules without knowing HTTP, LiveView, or job details.
- Keep country-specific and provider-specific logic isolated behind behaviours and registries.
- Protect PII: identity documents are encrypted at rest via `DebtStalker.Vault` and redacted before leaving the context.

## Top-level modules

| Module | Responsibility |
| ------ | -------------- |
| `DebtStalker` | Empty container module that documents the app boundaries. |
| `DebtStalker.Application` | OTP supervisor starting the supervision tree. |
| `DebtStalker.Repo` | Ecto repository for PostgreSQL. |
| `DebtStalker.Mailer` | Swoosh mailer (currently unused in production flows). |
| `DebtStalker.Release` | Release tasks for migrations/rollback in a deployed release. |
| `DebtStalker.Applications` | Public context for creating, listing, updating, and analytics. |
| `DebtStalker.Countries` | Public facade for country hints and currency symbols. |
| `DebtStalker.Risk` | Evaluates credit risk using country-specific rules. |
| `DebtStalker.Audit` | Read-only context for audit logs. |
| `DebtStalker.Notifications` | Persists inbound webhook events and outbound notification attempts. |
| `DebtStalker.DeadLetter` | Captures and replays exhausted Oban jobs. |
| `DebtStalker.CacheInvalidator` | PubSub subscriber that invalidates Cachex entries. |
| `DebtStalker.Telemetry` | Emits custom telemetry events. |
| `DebtStalker.ObanTelemetryHandler` | Bridges Oban telemetry to the DLQ and custom metrics. |

## Public API shapes

Most context functions return one of:

- `{:ok, struct_or_result}` on success.
- `{:error, %Ecto.Changeset{}}` for validation failures.
- `{:error, atom()}` for domain errors such as `:not_found`, `:invalid_transition`, `:provider_error`, or `:unsupported_country`.

## Important notes

- **No country branching outside `DebtStalker.Countries` and `DebtStalker.Providers`**: contexts look up modules via `Registry.lookup/1` and call the behaviour implementation.
- **Application date is server-set**: `Applications.create_application/1` always sets `application_date` to `DateTime.utc_now()`; callers cannot override it.
- **Audit logging is synchronous**: `Applications.update_status/3` writes an `AuditLog` row inside the same transaction as the status change (see `ADR-0004`).
- **Cache invalidation**: `CacheInvalidator` listens to `applications:list` PubSub and clears the per-application Cachex entry when a status changes.

## Where to look next

- `applications/` — schemas and changesets for `CreditApplication`, `StatusTransition`, and `AuditLog`.
- `countries/` — country behaviour and `ES`/`MX` implementations.
- `providers/` — provider behaviour, simulated adapters, and circuit breakers.
- `workers/` — Oban workers that consume the outbox.
- `notifications/` — webhook and notification attempt schemas.
- `dead_letter/` — dead-letter job schema and replay logic.
- `vault/` — Cloak encryption configuration.
- `seeds/` — demo data generation.
