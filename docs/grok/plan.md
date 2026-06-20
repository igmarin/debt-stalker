# Debt Stalker — Refined Plan (Global Architecture + Phase 1)

> **This is a planning artifact only.**  
> No implementation code has been or will be written during the creation/review of this plan.  
> All activity has been limited to reading the existing specs (docs/spec.md, docs/v1/spec.md, docs/kimi/plan.md) and the current project structure for context, then producing this improved, clearest-possible definition of the global model + first phase.

**User priority:** **understanding the design before any implementation begins**.

**Date:** 2026-06-19  
**Sources reviewed:** 
- `docs/spec.md` (original technical challenge)
- `docs/v1/spec.md`
- `docs/kimi/plan.md` (existing detailed v1 plan)

**Purpose of this plan:** Provide the **clearest, most actionable** definition of:
1. **Global architecture** (extensible to all 6 countries + future scale)
2. **First phase** (concrete, minimal but complete MVP for Spain + Mexico)

This is the master plan. Split supporting files are in the same directory.

---

## 1. Executive Summary & Objectives

(See full details in the working session copy or expand from original review.)

Key from `docs/spec.md`:
- 6 countries (ES, PT, IT, MX, CO, BR).
- MVP: create, country rules, provider data, query/list/update, async (DB triggers), webhooks, realtime UI.
- At least 2 countries.
- All the non-functionals (JWT, <5min run, scale notes, k8s, Makefile, etc.).

**Refined approach in this plan:**
- **Global layer first** — behaviours, registry, data model, async contracts, invariants that make adding countries trivial.
- **Phase 1** — full vertical for ES + MX that proves the global model.
- Later phases expand.

**Guiding principles:**
- Understanding before code.
- Strong separation of global contracts vs phase deliverables.
- Scannable, explicit, with checkpoints.

---

## 2. Global Architecture (The Core for Understanding)

See dedicated files:
- `global-architecture.md` (includes new **Architecture Diagrams** section with Mermaid)
- `data-model.md` (includes outbox trigger diagram)

Key points (summary):

### Core Domain Concepts
- Credit Application
- Country Module (behaviour)
- Provider Adapter (normalized only)
- Database-Generated Work (triggers → application_events outbox)
- Async Boundary + Realtime Surface

### Modular Structure + Invariants
(See `global-architecture.md` for full diagram and responsibility matrix.)

### Country Behaviour (The Heart)
Callbacks + exact Phase 1 rules for ES (DNI) and MX (CURP).

**Adding countries later** = new module + register. Nothing else changes.

### Provider Behaviour
Normalization contract. Raw payloads never escape.

### Data Model + DB-Generated Async (non-negotiable)
Defined in `data-model.md`.

The exact required trigger + outbox flow is non-negotiable per the challenge.

### API, Frontend, Security, Caching, Observability, Deployment
High-level global contracts as defined.

---

## 3. Phase Breakdown

### Phase 0 — Foundation (Conceptual)
Platform substrate (no domain yet): Postgres, Oban, JWT handling, LiveView, Makefile, docker, k8s space, coding guidelines.

### Phase 1 — ES + MX Vertical Slice (Understanding + Delivery)

**The complete, authoritative Definition of Done is here:**

→ [phase-1-acceptance.md](phase-1-acceptance.md)

This is the gate. Nothing in Phase 1 is considered complete until every item in that document is true and the Global Architecture invariants (see `global-architecture.md`) hold.

High-level summary of what Phase 1 must deliver:
- Schema + PostgreSQL triggers + `application_events` outbox
- Countries.Behaviour + ES + MX + Registry
- Providers.Behaviour + two simulated normalized adapters
- Applications full lifecycle (create, list, get, transitions)
- Async pipeline (dispatcher + risk/audit/notification/webhook workers)
- JWT + API + signed webhook endpoint
- LiveView realtime UI
- Audit, redaction, structured logging
- Full reproducibility artifacts + documentation

**We are not going to implement until everything has been defined first.**

---

## 4–6. Later Phases, Decisions, Risks
See the tables and rationale in the detailed approved plan.

---

## 7. docs/grok/ Files (This Directory)

- `plan.md` (this file) — master reference
- `global-architecture.md` — extract full Global Architecture section
- `data-model.md`
- `phase-1.md` — concrete tasks + acceptance
- `phase-1-acceptance.md`
- `decisions.md`
- `risks.md`

**How to use:** After any update, keep this directory in sync. The plan is the single source of truth for scope and understanding.

---

## 8. How to Proceed (Understanding First)

1. Review this plan + related docs.
2. Provide feedback / adjustments.
3. Materialize / refine the split files in this directory.
4. Only then begin implementation (test-first where sensible, respect AGENTS.md and global contracts).

**This plan was produced with zero code changes to the project.**

---

**End of docs/grok/plan.md**  
Refer to the full session plan copy for the complete expanded text if needed during review.
