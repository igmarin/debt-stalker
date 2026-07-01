# Notifications Context (`lib/debt_stalker/notifications/`)

This folder centralizes the persistence of inbound provider webhook events and outbound notification attempts. It was introduced by `ADR-0008` to keep webhook handling decoupled from the application lifecycle while preventing raw provider payloads from being stored or logged.

## Responsibilities

- Store metadata-only records of verified inbound webhook events.
- Detect duplicate webhook events by payload hash.
- Record outbound notification attempts (status, endpoint, response code, body, attempt number).
- Expose a small, read-only persistence API; business actions (status transitions) are performed by workers, not this context.

## Key modules

| Module | Purpose |
| ------ | ------- |
| `notifications.ex` | Public context for recording webhook events and notification attempts. |
| `webhook_event.ex` | Ecto schema for `webhook_events`. |
| `notification_attempt.ex` | Ecto schema for `notification_attempts`. |

## Public API

### `DebtStalker.Notifications`

#### `record_webhook_event(attrs :: map()) :: {:ok, WebhookEvent.t()} | {:error, Ecto.Changeset.t()}`

Persists an inbound webhook event. Required fields:

- `application_id` (UUID)
- `source` (string, e.g. `"provider"`)
- `payload_hash` (string, SHA-256 of the normalized payload)
- `verified` (boolean)
- `processed` (boolean, default `false`)

The raw payload is **not** stored; only the hash is kept for idempotency.

#### `webhook_event_exists?(payload_hash :: String.t()) :: boolean()`

Returns `true` if a webhook event with the same payload hash has already been recorded. Used by the webhook controller to deduplicate events.

#### `record_notification_attempt(attrs :: map()) :: {:ok, NotificationAttempt.t()} | {:error, Ecto.Changeset.t()}`

Records an outbound notification attempt. Fields include `application_id`, `notification_type`, `status`, `endpoint`, `response_code`, `response_body`, and `attempt_number`.

#### `list_notification_attempts(application_id :: Ecto.UUID.t()) :: [NotificationAttempt.t()]`

Returns notification attempts for an application, ordered newest first.

## Schemas

### `WebhookEvent`

- `id` (binary id)
- `application_id` (UUID, references `credit_applications`)
- `source` (string)
- `payload_hash` (string, unique index)
- `verified` (boolean)
- `processed` (boolean)
- `timestamps` with `updated_at: false`

No `raw_payload` column in the current schema (removed by `priv/repo/migrations/20260622050000_remove_raw_payload_from_webhook_events.exs`).

### `NotificationAttempt`

- `id` (binary id)
- `application_id` (UUID)
- `notification_type` (string)
- `status` (string, e.g. `"pending"`, `"delivered"`, `"failed"`)
- `endpoint` (string, nullable)
- `response_code` (integer, nullable)
- `response_body` (text, nullable)
- `attempt_number` (integer)
- `timestamps` with `updated_at: false`

## Important notes

- **No raw payloads**: raw provider webhook bodies are never persisted. The controller hashes the payload and stores only the hash.
- **Verification is separate**: HMAC signature verification happens in `DebtStalkerWeb.Api.WebhookController` before this context is called.
- **Idempotency**: duplicate webhook events are detected by `payload_hash` and returned with `{"status": "already_processed"}`.
- **Processing flag**: `WebhookProcessingWorker` marks the event as `processed` after applying the status transition.

## Where to look next

- `lib/debt_stalker_web/controllers/api/webhook_controller.ex` — HMAC verification and event ingestion.
- `lib/debt_stalker/workers/webhook_processing_worker.ex` — consumes webhook events and updates status.
- `lib/debt_stalker/workers/external_notification_worker.ex` — records and sends outbound notifications.
- `docs/adr/0008-notifications-context-and-webhook-payloads.md` — design rationale and security trade-offs.
