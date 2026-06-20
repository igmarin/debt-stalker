# ADR 0002 — Async Outbox Pattern with Postgres Triggers

## Status

Accepted

## Context

Credit applications require multiple async side-effects (risk evaluation, notifications, audit logging) that must be:
1. Reliably triggered (no lost events)
2. At-least-once delivered
3. Safely consumed by concurrent workers

Options considered:
- **Direct Oban insertion from application code**: Simple but couples business logic to async dispatch; events can be lost if the transaction rolls back after Oban insert.
- **Change Data Capture (CDC)**: Debezium/Wal2JSON — powerful but heavy infrastructure for Phase 1.
- **Postgres triggers → outbox table**: Events are created atomically with the source change; workers drain with SKIP LOCKED.

## Decision

Use **Postgres triggers** that insert into `application_events` (outbox) after INSERT or UPDATE on `credit_applications`. An `EventDispatcherWorker` (Oban, cron-like) claims batches with `FOR UPDATE SKIP LOCKED` and routes to specialized workers.

## Consequences

**Positive:**
- Events are guaranteed to exist if the source change committed (same transaction)
- SKIP LOCKED enables safe concurrent consumption without blocking
- Decouples event production (triggers) from consumption (workers)
- Easy to add new event types by adding triggers

**Negative:**
- Triggers are invisible in application code (must check DB to see all side-effects)
- Debugging requires checking both application logs and `application_events` table
- Slight delay between write and dispatch (polling interval)

**Mitigations:**
- Document all triggers in migration files with clear comments
- EventDispatcherWorker runs frequently (every 5s via Oban cron)
- Integration test verifies the full path: insert → trigger → event → worker
