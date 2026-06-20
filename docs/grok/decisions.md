# Debt Stalker — Key Decisions

See master plan (docs/grok/plan.md) for full rationale.

## Phase 1 Countries
ES + MX (distinct documents, rules variety, Europe + LatAm coverage).

## Frontend
Phoenix LiveView + PubSub (realtime with minimal extra parts).

## Jobs
Oban on Postgres (durable, simple, already aligned).

## DB-Generated Async
PostgreSQL triggers → dedicated application_events outbox table (satisfies challenge requirement explicitly).

## Providers
Simulated deterministic adapters (repeatable tests + fast local setup).

## Auth
JWT (Joken) for API (challenge requirement, simple demo token endpoint).

## PII (Phase 1)
Hash + redaction (plain storage acceptable for MVP; upgrade path clear).

## Pagination & Scale
Cursor (keyset) from the beginning. Document partitioning + archiving for millions of rows.

## Cache
ETS for static country/registry config.

## k8s
Plain manifests (documented env vars).

These decisions support the global architecture and make later phases additive.
