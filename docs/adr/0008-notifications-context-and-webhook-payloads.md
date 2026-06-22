# 0008. Notifications Context and Webhook Payload Handling

## Status

Accepted

## Context

The master plan established two architecture invariants:

1. Webhook and notification logic should live in a domain context, not in
   controllers or workers.
2. Raw provider payloads are never persisted or exposed.

During Phase 2 review we found that:

- The `ExternalNotificationWorker` inserted directly into `notification_attempts`
  via `Repo.insert_all`, bypassing a context.
- The `WebhookController` inserted directly into `webhook_events` and stored the
  raw provider payload in a `raw_payload` JSONB column.
- Webhook HMAC verification read `conn.assigns[:raw_body]`, but the endpoint did
  not capture the raw request body, so verification computed the HMAC over an
  empty string in production.
- Production runtime config did not require `WEBHOOK_SECRET` or enable
  signature enforcement by default.

## Decision

1. Introduce a `DebtStalker.Notifications` context with
   `Notifications.WebhookEvent` and `Notifications.NotificationAttempt` schemas.
2. Make the `WebhookController` and `ExternalNotificationWorker` delegate to
   this context.
3. Remove the `raw_payload` column from `webhook_events`; only the SHA-256
   payload hash and event metadata are stored.
4. Capture the raw request body via a `RawBodyReader` plugged into
   `Plug.Parsers` so HMAC verification is computed over the actual payload.
5. Require `WEBHOOK_SECRET` in production and default
   `require_webhook_signature` to `true` in production.

## Consequences

**Positive:**

- The architecture invariants are enforced in code.
- Webhook signatures are verifiable in production.
- No raw provider payload is persisted, reducing PII/exposure risk.
- Notification and webhook logic is centralized and testable.

**Negative:**

- A database migration is required to drop `raw_payload`.
- Existing webhook events that relied on `raw_payload` for debugging lose that
  data (acceptable for an MVP; future debugging relies on payload_hash + logs).
- Operators must set `WEBHOOK_SECRET` in production before webhooks work.
