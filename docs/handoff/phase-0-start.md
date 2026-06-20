We're implementing Phase 0 of the Debt Stalker project — a fintech credit-application core built with Elixir/Phoenix.

## Project
- Repo: /Users/igmarin/Developer/Personal/Me/debt-stalker
- GitHub: igmarin/debt-stalker
- Phase 0 milestone: https://github.com/igmarin/debt-stalker/milestone/1
- Phase 0 issues: https://github.com/igmarin/debt-stalker/issues?q=is:open+label:phase-0

## Read these first (in order)
1. `docs/master-plan.md` — authoritative architecture + conventions (especially §4.8 Code Org Contract, §4.9 Error Handling, §4.10 Logging, §4.11 Testing, §8.1 Spec-Driven Workflow, §8.2 Phase Documentation Protocol)
2. `docs/phases/phase-0.md` — the phase scope, task seeds, and DoD
3. `.github/review-prompt.md` — rs-guard review rules
4. `.reviewer.toml` — rs-guard config
5. `docs/handoff/README.md` — handoff file conventions

## Skills to use
This project has Elixir/Phoenix skills installed. Invoke them before writing code:
- `setup` — for project bootstrap (mix phx.new, config, CI/CD) — invoke first for T0.1-T0.6
- `elixir-essentials` — before writing any .ex/.exs file
- `testing-essentials` — before writing any test file
- `credo-config` — when setting up .credo.exs (T0.11)
- `typespec-dialyzer` — when setting up Dialyzer (T0.12)
- `tdd` — for TDD-gated tasks (starts in Phase 1, but good to know the workflow)

## Workflow per task
1. Pick the next issue from the Phase 0 milestone (start with #1 / T0.0, then #2 / T0.1, etc.)
2. Move it to in-progress: `gh issue edit <num> --remove-label "todo" --add-label "in-progress"`
3. Implement following the Spec-Driven Development loop (master-plan §8.1):
   - TDD-gated tasks: write failing test → run → fail → implement → run → pass → full suite green → rs-guard review → iterate (max 3) → commit
   - TDD-exempt tasks: implement → test where applicable → rs-guard review → commit
4. Commit with conventional commit format + "Generated with Devin" footer
5. Move issue to in-review, then done when verified: `gh issue edit <num> --remove-label "in-progress" --add-label "done"` then `gh issue close <num>`
6. When all Phase 0 issues are done, create one PR from `phase-0-foundation` → `main`

## Phase 0 is TDD-exempt
Phase 0 tasks are [CHORE], [INFRA], [DB], [DOCS], [QA] — all TDD-exempt. But include tests where applicable (e.g., T0.16 smoke test). The TDD hard gate starts in Phase 1.

## Key decisions already made
- Phoenix 1.8 + LiveView + Postgres + Oban + Joken + logger_json
- Credo strict + Dialyzer + ExDoc
- Mox + StreamData for testing
- rs-guard with DeepSeek Pro for code review (pre-commit hook + CI)
- CodeRabbit as second reviewer in CI
- Single growing Postman collection: `docs/postman/debt-stalker.json`
- CHANGELOG per phase (Keep-a-Changelog format)
- ADRs for significant decisions (`docs/adr/`)
- Phase report per phase (`docs/phases/phase-N-report.md`)
- k8s manifests deferred to Phase 1; Docker Compose in Phase 0
- One feature branch per phase → one PR per phase

## Start
Begin with issue #1 (T0.0 — Create feature branch), then proceed sequentially through the Phase 0 issues. The full list with acceptance criteria is in `docs/phases/phase-0.md` §6.
