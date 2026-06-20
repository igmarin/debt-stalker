# Debt Stalker — Risks & Mitigations

From the approved plan.

- DNI/CURP validation accuracy → Clear rules + documented simplifications + tests.
- Async races → SKIP LOCKED + idempotent workers + state checks in context.
- LiveView realtime tests → Direct PubSub in tests + proper patterns.
- Provider failure leaving orphans → Always persist with recoverable status (provider_error).
- k8s drift → Dry-run validation in Makefile/CI.
- Overbuilding → Strict Phase 1 scope + behaviours from day one.

Full list and mitigations in master plan.md.
