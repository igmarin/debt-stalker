# ADR-0006: Dead-Letter Job Strategy (Custom Table + Telemetry Capture)

## Status

Accepted

## Context

Oban workers can fail permanently — either because a job is explicitly discarded (`{:cancel, reason}`) or because it exhausts its retry attempts. When that happens we still need to:

- Preserve the original job args, error, and metadata for later inspection
- Allow operators to replay (re-enqueue) a dead-lettered job after the underlying issue is fixed
- Expose a list/replay API for admins without granting direct database access

Oban ships a built-in "discarded jobs" view, but the richer retry/discard policies and admin tooling live in **Oban Pro**, which is a paid library. Debt Stalker is an open-source project, so depending on Oban Pro is not an option.

We therefore need a DLQ mechanism that:

1. Costs nothing (no paid dependencies)
2. Gives us full control over retry and discard policies
3. Captures failed jobs automatically, without requiring each worker to opt in
4. Retains the original args, error, and metadata for inspection
5. Is queryable and replayable via an Admin API

## Decision

Use a custom `dead_letter_jobs` table with an Oban telemetry handler that captures failed jobs and moves them into the table.

- **`dead_letter_jobs` table** — created by migration `20260621062500_create_dead_letter_jobs.exs`. Stores `job_id`, `application_id`, `worker`, `queue`, `args`, `attempt`, `max_attempts`, `last_error`, and `captured_at`, with indexes on `job_id` (unique), `application_id`, `worker`, and `inserted_at`.
- **`DebtStalker.ObanTelemetryHandler`** (`lib/debt_stalker/oban_telemetry_handler.ex`) — a supervised GenServer that attaches to Oban's `[:oban, :job, :stop]` and `[:oban, :job, :exception]` telemetry events. When a job is discarded or has exhausted its attempts, it calls `DebtStalker.DeadLetter.capture/1` to insert a row into `dead_letter_jobs`.
- **`DebtStalker.DeadLetter`** context — owns the `dead_letter_jobs` schema (`DebtStalker.DeadLetter.DeadLetterJob`) and exposes `capture/1`, list, and replay (re-enqueue) operations.
- **Admin API** — lists and replays dead-lettered jobs by re-enqueuing the original args onto the original worker/queue.

Capture is automatic and centralized in the telemetry handler, so individual workers do not need to know about the DLQ — they simply return `{:cancel, reason}` for permanent failures or let retries exhaust naturally.

### Alternatives considered

| Option | Rejected because |
|--------|-----------------|
| Oban Pro discarded-jobs feature | Paid library; not available for an open-source project |
| Per-worker `discard_on` callbacks writing to a log/table | Requires every worker to opt in; easy to forget; logic duplicated across workers |
| Relying on Oban's `oban_jobs` table alone | Discarded/expired jobs are eventually pruned; no structured replay or admin API |
| External DLQ (Redis/RabbitMQ dead-letter exchange) | Adds infrastructure not present in the stack; Oban is already Postgres-backed |

## Consequences

### Positive

- No paid dependencies — fully open-source friendly
- Full control over retention, retry, and discard policies via our own schema and context
- Automatic capture via telemetry — workers stay unaware of the DLQ
- Original args, error, and metadata are preserved for inspection and replay
- Admin API can list and replay dead-lettered jobs without direct DB access
- Indexes on `application_id`, `worker`, and `inserted_at` support efficient querying

### Negative

- We own the capture, retention, and replay logic instead of using a maintained library feature
- The telemetry handler must be supervised and re-attach on restart (mitigated by the GenServer design in `ObanTelemetryHandler`)
- A second migration (`20260621070000_add_reenqueued_at_to_dead_letter_jobs.exs`) was needed to track replay state, showing the schema will evolve with operational needs

### Neutral

- The `dead_letter_jobs` table lives in the same Postgres database as Oban, keeping infrastructure simple
- Replay re-enqueues a fresh Oban job rather than mutating the original row, so the dead-letter record remains an immutable audit trail
