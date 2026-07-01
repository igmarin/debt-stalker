# Dead Letter Queue (`lib/debt_stalker/dead_letter/`)

This folder implements the dead-letter queue (DLQ) for exhausted Oban jobs. It is driven by telemetry: when `ObanTelemetryHandler` observes a discarded or exhausted job, it captures a redacted snapshot into the `dead_letter_jobs` table so operations can inspect and replay it.

## Responsibilities

- Capture exhausted Oban jobs with PII-redacted arguments.
- Provide idempotent capture (same `job_id` is not duplicated).
- List, count, and retrieve dead-letter jobs for operations.
- Re-enqueue a captured job safely after scrubbing and revalidation.
- Use transactional concurrency control to prevent duplicate replay.

## Key modules

| Module | Purpose |
| ------ | ------- |
| `dead_letter.ex` | Public context for capture, list, count, get, and re-enqueue. |
| `dead_letter_job.ex` | Ecto schema for `dead_letter_jobs`. |

## Public API

### `DebtStalker.DeadLetter`

#### `capture_job(job :: Oban.Job.t(), reason :: String.t()) :: {:ok, DeadLetterJob.t()} | {:ok, :existing} | {:error, Ecto.Changeset.t()}`

Captures an exhausted Oban job. It redacts sensitive args (e.g. `identity_document`), stores the job id, worker, queue, attempt, max attempts, and error, and returns `{:ok, :existing}` if the `job_id` was already captured. This function is idempotent.

#### `list_jobs(opts :: keyword()) :: [DeadLetterJob.t()]`

Returns dead-letter jobs ordered by `inserted_at` descending. Supports `limit`, `offset`, and `status` filters.

#### `count_jobs() :: integer()`

Returns the total number of dead-letter jobs.

#### `get_job(id :: Ecto.UUID.t()) :: {:ok, DeadLetterJob.t()} | {:error, :not_found}`

Fetches a single dead-letter job by its id.

#### `reenqueue_job(id :: Ecto.UUID.t()) :: {:ok, Oban.Job.t()} | {:error, :not_found | :already_reenqueued | Ecto.Changeset.t()}`

Re-enqueues a captured job. It:

1. Fetches the dead-letter job.
2. Checks `reenqueued_at` to prevent duplicate replay.
3. Reconstructs safe args (removes PII fields, preserves `application_id`).
4. Inserts a new Oban job for the original worker.
5. Updates `reenqueued_at` in a transaction.

Returns `{:error, :already_reenqueued}` if the job has already been replayed.

## Schema

### `DeadLetterJob`

- `id` (binary id)
- `job_id` (integer, unique)
- `application_id` (string, nullable)
- `worker` (string)
- `queue` (string, nullable)
- `args` (map, redacted)
- `attempt` (integer)
- `max_attempts` (integer)
- `last_error` (text, nullable)
- `captured_at` (utc datetime)
- `reenqueued_at` (utc datetime, nullable)
- `timestamps` (normal Ecto timestamps)

## Important notes

- **PII redaction**: `identity_document` and similar fields are removed from `args` before persistence. `application_id` is preserved because it is not sensitive.
- **No admin UI/API today**: the DLQ context is internal-only. Operations replay via `iex` or a future admin tool. The Postman collection should not expose DLQ endpoints.
- **Telemetry-driven**: `DebtStalker.ObanTelemetryHandler` calls `capture_job/2` on `:discarded` and exhausted `:stopped` events.
- **Idempotent capture**: the unique index on `job_id` prevents duplicates.

## Where to look next

- `lib/debt_stalker/oban_telemetry_handler.ex` — the telemetry handler that feeds the DLQ.
- `docs/adr/0006-dlq-strategy.md` — why a custom DLQ table was chosen over Oban's built-in tools.
- `priv/repo/migrations/20260621062500_create_dead_letter_jobs.exs` and `20260621070000_add_reenqueued_at_to_dead_letter_jobs.exs` — schema evolution.
