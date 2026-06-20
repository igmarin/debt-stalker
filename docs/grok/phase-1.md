# Debt Stalker — Phase 1: Spain + Mexico (First Vertical Slice)

Master reference: docs/grok/plan.md

## Goal (Understanding + Delivery)
Implement one complete, correct, observable end-to-end flow for ES and MX that exercises the full global architecture.

After Phase 1 anyone should be able to explain the entire system from this slice.

## What Phase 1 Must Make Real
1. Schema + PostgreSQL triggers + application_events outbox.
2. Countries.Behaviour + ES + MX + Registry (with cache).
3. Providers.Behaviour + two simulated normalized adapters.
4. Applications context (create with rules+provider, list/filter/cursor, get, validated transitions + audit + broadcast).
5. Async pipeline (dispatcher + risk/audit/notification/webhook Oban workers).
6. JWT auth + API + signed webhook endpoint.
7. LiveView (list + filters + create + detail) with realtime PubSub updates.
8. Audit, redaction, structured logs.
9. Reproducibility (Makefile, docker, seeds, k8s/, README + this docs/grok/).

## Definition of Done

**The authoritative acceptance criteria live in:**

→ [phase-1-acceptance.md](phase-1-acceptance.md)

Visual architecture & data flows: [global-architecture.md](global-architecture.md) (Mermaid diagrams)

That document is the **gate**. Phase 1 is complete only when every item in the checklist and criteria is verifiably true, and the Global Architecture invariants hold.

The summary below is for orientation only.

### High-Level Summary of What Must Be True
- All Required Functionality from `docs/spec.md` works for ES + MX.
- Global contracts and invariants (see `global-architecture.md`) are respected and visible in the code.
- A complete traceable flow is observable: create (UI or API) → PostgreSQL trigger + `application_events` → workers → status change + audit + realtime UI update.
- Non-functionals are satisfied: JWT + redaction, structured observability, <5 min reproducible local run, k8s manifests, comprehensive documentation including scale analysis.
- The design and implementation prove that adding more countries is additive.

See the full checklist, required flows, and verification approach in `phase-1-acceptance.md`.

## Out of Scope (by design)
- Real providers
- PT, IT, CO, BR
- Advanced resilience, production auth, full encryption at rest, etc.

**We are not implementing anything until the definitions (Global Architecture + this Phase 1 Acceptance + supporting docs) are considered complete.**

See master plan for recommended building order focused on understanding (schema/triggers → domain contracts → applications → async → delivery).

Respect AGENTS.md on all Phoenix/LiveView code.
