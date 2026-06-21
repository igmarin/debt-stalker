We're implementing Phase 1 of the Debt Stalker project — the ES + MX vertical slice. This is where real functionality begins.

## Project
- Repo: /Users/igmarin/Developer/Personal/Me/debt-stalker
- GitHub: igmarin/debt-stalker
- Phase 1 milestone: https://github.com/igmarin/debt-stalker/milestone/2
- Phase 1 issues: https://github.com/igmarin/debt-stalker/issues?q=is:open+label:phase-1

## Read these first (in order)
1. `docs/master-plan.md` — authoritative architecture + conventions (especially §4.1 Global Invariants, §4.6 API & Auth, §4.8 Code Org Contract, §4.9 Error Handling, §4.10 Logging, §4.11 Testing, §4.12 Status Flow, §8.1 Spec-Driven Workflow)
2. `docs/phases/phase-0-report.md` — what was built in Phase 0, decisions made, gotchas
3. `docs/phases/phase-1.md` — the phase scope, user stories, task seeds, seed data spec (§3.8), webhook flow diagram (§3.9), task dependency graph (§7), and DoD
4. `.github/review-prompt.md` — rs-guard review rules
5. `.reviewer.toml` — rs-guard config
6. `AGENTS.md` — development guidelines (TDD policy, code org, review loop)
7. `docs/handoff/README.md` — handoff file conventions

## Skills to use
This project has Elixir/Phoenix skills installed. Invoke them before writing code:
- `elixir-essentials` — before writing any .ex/.exs file
- `tdd` — for ALL [DOMAIN], [ASYNC], [API], [WEB] tasks (hard gate: test must exist, run, and fail for the right reason before implementation)
- `ecto-essentials` — for migrations, schemas, queries (T1.2-T1.4, T4.x)
- `ecto-migration` — for migration tasks specifically (T1.2-T1.4)
- `phoenix-liveview-essentials` — for LiveView work (T7.1-T7.3)
- `phoenix-json-api` — for API controllers (T6.1-T6.3)
- `phoenix-pubsub-patterns` — for PubSub broadcasting (T4.3, T7.1-T7.2)
- `testing-essentials` — before writing any test file
- `oban-essentials` — for Oban workers (T5.1-T5.3)
- `background-job` — for worker design with idempotency (T5.1-T5.3)
- `property-based-testing` — for DNI/CURP validation (T2.2-T2.3)
- `typespec-dialyzer` — for @spec on all public functions
- `security-essentials` — for JWT auth + webhook signature verification + PII encryption (T6.1, T6.3, T4.1)

## Workflow per task
1. Pick the next issue from the Phase 1 milestone (follow the dependency graph in phase-1.md §7 — critical path first)
2. Move it to in-progress: `gh issue edit <num> --remove-label "todo" --add-label "in-progress"`
3. Implement following the Spec-Driven Development loop (master-plan §8.1):
   - **TDD-gated tasks** ([DOMAIN], [ASYNC], [API], [WEB]):
     a. Write failing test for the acceptance criteria
     b. Run → verify FAILS for right reason (function not defined, not syntax error)
     c. Implement minimal code
     d. Run → verify PASSES
     e. Full suite green: `mix format && mix credo --strict && mix dialyzer && mix test`
     f. rs-guard local review → iterate (max 3 rounds)
     g. Commit when APPROVE/COMMENT
   - **TDD-exempt tasks** ([CHORE], [INFRA], [DB], [OPS], [DOCS], [QA]):
     Implement → test where applicable → rs-guard review → commit
4. Commit with conventional commit format + "Generated with Devin" footer
5. Move issue to done: `gh issue edit <num> --remove-label "in-progress" --add-label "done"` then `gh issue close <num>`
6. **Postman sub-tasks**: [API] tasks must update `docs/postman/debt-stalker.json` as part of the task
7. **Create one PR per issue** — branch from `main`, implement, push, open PR with `phase-1` label. Do NOT accumulate an entire phase into a single PR.

## Phase 1 TDD is a HARD GATE
[DOMAIN], [ASYNC], [API], [WEB] tasks CANNOT have implementation code written until:
1. The test EXISTS
2. The test has been RUN
3. The test FAILS for the right reason (feature missing, not a typo)

If you wrote implementation before the test, delete it and start over.

## Key decisions from Phase 0 (read phase-0-report.md for full context)
- Phoenix 1.8 + LiveView + Postgres + Oban + Joken + logger_json
- Credo strict + Dialyzer + ExDoc — all green
- rs-guard pre-commit hook + CI review functional
- CodeRabbit configured
- CI pipeline: format + compile + credo + dialyzer + test on every PR
- Docker Compose for local Postgres
- Postman collection skeleton created
- CHANGELOG + ADR template ready

## Key decisions for Phase 1
- DB triggers → outbox → EventDispatcherWorker with FOR UPDATE SKIP LOCKED (not Oban Pro)
- Simulated deterministic provider adapters (no real external calls)
- Cursor pagination (keyset) — no unbounded OFFSET
- PII encrypted at rest (Cloak) from day one + hash for lookup + redacted to last-4 in all responses + logs
- Status flow: submitted → pending_risk → approved/rejected/additional_review
- Country rules flag additional_review_required — they do NOT reject (decision D7)
- 10 seed applications covering all scenarios (see phase-1.md §3.8)
- k8s manifests created + dry-run validated (real deploy is Phase 2)

## Start
Begin with issue #19 (T0.0 — Create feature branch), then follow the dependency graph in `docs/phases/phase-1.md` §7. The critical path is:
T0.0 → T1.2 → T1.3 → T1.4 → T2.1 → T2.2/T2.3 → T4.1 → T4.3 → T5.1 → T5.2 → T6.2 → T7.1 → T8.3 → T9.2

Parallelizable early: T2.x (countries) + T3.x (providers) after T2.1/T3.1; T6.1 (JWT) is independent.
