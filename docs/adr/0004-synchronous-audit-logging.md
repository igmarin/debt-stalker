# ADR 0004 — Synchronous Audit Logging Instead of AuditWorker

## Status

Accepted

## Context

The Master Plan (§4.4) specifies five specialized Oban workers in the async pipeline: Dispatcher, Risk, Audit, Notification, and Webhook. The `EventDispatcherWorker` is responsible for routing outbox events to the appropriate worker based on `event_type`.

In practice, audit records are written synchronously inside `Applications.update_status/3` via `Ecto.Multi` — the same transaction that updates the application status and inserts the `application_status_transitions` row. This means audit data is atomically consistent with the state change it records.

Adding a separate `AuditWorker` that reads the outbox event and then writes an audit row would introduce:
1. A delay between the state change and the audit record (eventual consistency)
2. A risk of audit loss if the worker fails after the transaction commits
3. Additional complexity in the dispatch path

## Decision

Keep audit logging **synchronous** within the `Ecto.Multi` transaction in `update_status/3`. Do not dispatch an `AuditWorker` from `EventDispatcherWorker` in Phase 1.

If Phase 2 requires async audit enrichment (e.g., external audit trail, compliance reporting), a dedicated `AuditWorker` can be added at that time by extending the dispatcher's `dispatch_event/1` function.

## Consequences

### Positive

- Audit records are atomically consistent with state changes — no possibility of a committed status change without a corresponding audit row
- Simpler dispatch path (fewer workers to reason about)
- No delay between state change and audit availability
- One fewer Oban queue consumer

### Negative

- Diverges from the documented 5-worker design in the Master Plan
- Audit write adds latency to the synchronous request path (measured at <1ms for a single insert)
- If audit enrichment becomes async (Phase 2+), the dispatch path must be extended

### Neutral

- The `application_events` outbox still captures all state changes for other workers (Risk, Notification) — audit is the only concern that stays synchronous
