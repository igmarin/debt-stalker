# Workers (`lib/debt_stalker/workers/`)

This folder contains Oban workers that process events from the `application_events` outbox table. Workers contain **no business logic**; they delegate to domain contexts (`DebtStalker.Applications`, `DebtStalker.Risk`, `DebtStalker.Notifications`).

## Responsibilities

- Drain the Postgres outbox (`application_events`) and dispatch events to the right worker.
- Evaluate risk asynchronously after a new application is created.
- Send outbound notifications when an application reaches a terminal status.
- Process verified inbound webhook events and apply status transitions.
- Respect retry semantics and emit telemetry for every job.

## Key modules

| Module | Purpose |
| ------ | ------- |
| `event_dispatcher_worker.ex` | Cron-driven Oban worker that drains the outbox table with `FOR UPDATE SKIP LOCKED` and dispatches events. |
| `risk_evaluation_worker.ex` | Handles `application.created` events: fetches provider data, evaluates risk, and transitions status. |
| `external_notification_worker.ex` | Handles `application.status_changed` events for terminal statuses: idempotently sends outbound notifications. |
| `webhook_processing_worker.ex` | Processes a verified webhook event from `Notifications` and applies a status transition. |

## Public API

### `DebtStalker.Workers.EventDispatcherWorker`

#### `new() :: Oban.Job.t()`

Builds a job. The worker is normally scheduled by the Oban Cron plugin every minute, but it can be enqueued manually for testing.

#### `perform(%Oban.Job{}) :: :ok | {:error, reason}`

Drains up to `batch_size * max_batches_per_run` unprocessed events from `application_events`, marks them as processed, and inserts one specialized job per event. Emits telemetry about processed, failed, and remaining counts.

### `DebtStalker.Workers.RiskEvaluationWorker`

#### `new(args :: %{application_id: String.t()}) :: Oban.Job.t()`

Builds a job for a specific application.

#### `perform/1` for `RiskEvaluationWorker`

Loads the application, calls `DebtStalker.Risk.evaluate/1`, and moves the application through the resulting status transition. Returns `{:cancel, reason}` for permanent errors (e.g. unknown country) so Oban does not retry forever.

### `DebtStalker.Workers.ExternalNotificationWorker`

#### `new/1` for `ExternalNotificationWorker`

Builds a notification job for a terminal status change. Args: `application_id`, `status`, `triggered_by`.

#### `perform/1` for `ExternalNotificationWorker`

Idempotently checks whether a notification was already sent for this application/status combination, records a `NotificationAttempt`, and either delivers to the configured endpoint or simulates delivery when no endpoint is configured. Returns `{:cancel, ...}` for terminal failures (e.g. missing application).

### `DebtStalker.Workers.WebhookProcessingWorker`

#### `new/1` for `WebhookProcessingWorker`

Builds a webhook-processing job after a webhook event is verified and stored. Args: `application_id`, `status`, `triggered_by`.

#### `perform/1` for `WebhookProcessingWorker`

Applies the status transition via `Applications.update_status/3` and marks the `WebhookEvent` as processed. Permanent failures (e.g. invalid transition) are cancelled; transient errors are retried.

## Important notes

- **Workers delegate to contexts**: no country rules, no provider HTTP details, no business decisions live in this folder.
- **Outbox pattern**: the database triggers in `add_outbox_triggers.exs` write events; the dispatcher reads them; the workers act on them. This decouples the web/API request from async work.
- **Retry semantics**:
  - Transient errors return `{:error, reason}` and are retried by Oban.
  - Permanent errors return `{:cancel, reason}` to stop retries.
- **Telemetry**: every worker emits `[:debt_stalker, :oban, :job, ...]` events via `DebtStalker.ObanTelemetryHandler`.

## Where to look next

- `lib/debt_stalker/applications.ex` — the context workers call for state changes.
- `lib/debt_stalker/risk.ex` — risk evaluation called by `RiskEvaluationWorker`.
- `lib/debt_stalker/notifications.ex` — persistence layer for webhooks and notification attempts.
- `priv/repo/migrations/20260620220901_add_outbox_triggers.exs` — the Postgres triggers that feed the outbox.
- `docs/adr/0002-async-outbox-pattern.md` — why the outbox pattern was chosen.
