We're implementing Phase 2 of the Debt Stalker project — making the ES + MX vertical slice production-credible: observable, resilient, and deployable with PII protection.

## Project
- Repo: /Users/igmarin/Developer/Personal/Me/debt-stalker
- GitHub: igmarin/debt-stalker
- Phase 2 milestone: https://github.com/igmarin/debt-stalker/milestone/3
- Phase 2 issues: https://github.com/igmarin/debt-stalker/issues?q=is:open+label:phase-2

## Read these first (in order)
1. `docs/master-plan.md` — authoritative architecture + conventions (especially §4.1 Global Invariants, §4.8 Code Org Contract, §4.9 Error Handling, §4.10 Logging, §4.11 Testing, §8.1 Spec-Driven Workflow, §8.2 Phase Documentation Protocol)
2. `docs/phases/phase-1-report.md` — what was built in Phase 1, decisions made, gotchas, next-agent instructions
3. `docs/phases/phase-2.md` — the phase scope, two tracks (2a Resilience & Observability, 2b Production & Security), task seeds, Postman updates (§3.3), task dependency graph (§7), and DoD
4. `.github/review-prompt.md` — rs-guard review rules
5. `.reviewer.toml` — rs-guard config
6. `AGENTS.md` — development guidelines (TDD policy, code org, review loop)
7. `docs/handoff/README.md` — handoff file conventions

## Skills to use
This project has Elixir/Phoenix skills installed. Invoke them before writing code:
- `elixir-essentials` — before writing any .ex/.exs file
- `tdd` — for ALL [OBS], [RES], [API], [PERF], [SEC] tasks (hard gate)
- `testing-essentials` — before writing any test file
- `oban-essentials` — for DLQ + circuit breaker around Oban workers (T11.1, T12.1-T12.2)
- `background-job` — for worker resilience design (T11.1, T12.x)
- `phoenix-json-api` — for rate limiting plug (T13.1)
- `phoenix-pubsub-patterns` — for cache invalidation via PubSub (T14.1)
- `cachex-caching` — for app-level detail cache (T14.1)
- `telemetry-essentials` — for telemetry events + metrics (T10.1-T10.3)
- `security-essentials` — for PII encryption verification + secrets management (T17.1, T18.1)
- `typespec-dialyzer` — for @spec on all public functions
- `deployment-gotchas` — for k8s deployment + probes + runtime config (T15.1-T15.3)
- `ci-cd-and-automation` — for CI/CD pipeline updates (T16.1-T16.2)

## Workflow per task
1. Pick the next issue from the Phase 2 milestone. Tracks 2a and 2b can run in parallel — see dependency graph in phase-2.md §7.
2. Move it to in-progress: `gh issue edit <num> --remove-label "todo" --add-label "in-progress"`
3. Implement following the Spec-Driven Development loop (master-plan §8.1):
   - **TDD-gated tasks** ([OBS], [RES], [API], [PERF], [SEC]):
     a. Write failing test for the acceptance criteria
     b. Run → verify FAILS for right reason
     c. Implement minimal code
     d. Run → verify PASSES
     e. Full suite green: `mix format && mix credo --strict && mix dialyzer && mix test`
     f. rs-guard local review → iterate (max 3 rounds)
     g. Commit when APPROVE/COMMENT
   - **TDD-exempt tasks** ([CHORE], [OPS], [CI], [CD], [DOCS]):
     Implement → test where applicable → rs-guard review → commit
4. Commit with conventional commit format + "Generated with Devin" footer
5. Move issue to done: `gh issue edit <num> --remove-label "in-progress" --add-label "done"` then `gh issue close <num>`
6. **Postman sub-tasks**: T13.1 (rate limiting) + T19.1 (finalization) must update `docs/postman/debt-stalker.json`
7. When all Phase 2 issues are done, create one PR from `phase-2-resilience` → `main`

## Phase 2 TDD is a HARD GATE
[OBS], [RES], [API], [PERF], [SEC] tasks CANNOT have implementation code written until:
1. The test EXISTS
2. The test has been RUN
3. The test FAILS for the right reason

If you wrote implementation before the test, delete it and start over.

## Two parallel tracks

### Track 2a — Resilience & Observability
T10.1 (telemetry) → T10.2 (metrics reporter) → T10.3 (business metrics)
T11.1 (circuit breaker) — depends on T10.1
T12.1 (DLQ capture) → T12.2 (DLQ re-enqueue)
T13.1 (rate limiting) — independent
T14.1 (app cache) — depends on Phase 1 get_application + PubSub

### Track 2b — Production & Security
T15.1 (probes) → T15.2 (real deploy) → T15.3 (HPA scaling)
T16.1 (CI update) → T16.2 (CD image build + deploy)
T17.1 (encrypted PII) → T17.2 (backfill migration)
T18.1 (secrets management) — independent
T18.2 (log-scrubbing audit) — depends on T10.1

### Closeout (after both tracks)
T19.1 (Postman finalization) → T19.2 (CHANGELOG + ADRs + Report)

## Key decisions from Phase 1 (read phase-1-report.md for full context)
- ES + MX vertical slice fully functional
- DB triggers → outbox → EventDispatcherWorker with SKIP LOCKED operational
- Simulated deterministic provider adapters
- Cursor pagination in place
- PII redacted to last-4 in responses + logs
- Status flow: submitted → pending_risk → approved/rejected/additional_review
- 10 seed applications
- k8s manifests created + dry-run validated
- Postman collection has all Phase 1 endpoints
- All Global Architecture invariants hold

## Key decisions for Phase 2
- Circuit breaker library: TBD (ADR required — :fuse vs custom GenServer)
- Encryption: Cloak/cloak_ecto (already in place from Phase 1 — Phase 2 verifies + wires production key)
- DLQ strategy: TBD (ADR required — table vs Oban Pro discarded-jobs)
- Rate limiter: TBD (ADR required — hammer vs plug_attack)
- Real deploy target: kind/minikube (local cluster acceptable for gate)
- No backfill migration needed — PII is encrypted from day one in Phase 1

## Start
Begin with issue #48 (T0.0 — Create feature branch), then start both tracks in parallel. See `docs/phases/phase-2.md` §7 for the full dependency graph.
