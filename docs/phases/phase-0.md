# Phase 0 — Platform Foundation

> **Parent:** `docs/master-plan.md` · **Source of truth for requirements:** `docs/requirements.md`
> **Status:** Planning artifact only. No code written.
> **Goal:** A runnable, empty-but-wired Phoenix skeleton with full tooling, code review infrastructure, and development guidelines. After Phase 0, any developer or agent can clone the repo, run `make setup && make test`, and have a green suite with all quality gates operational.

---

## 1. Phase Goal & Boundaries

**Entry condition:** None (first phase).

**In scope:**
- Phoenix application skeleton (Postgres + LiveView + Ecto)
- Dependencies: `oban`, `joken`, `credo`, `dialyxir`, `ex_doc`, `mox`, `stream_data`, `logger_json`
- Configuration: `dev.exs`, `test.exs`, `runtime.exs`
- Docker Compose for Postgres
- Makefile with all common commands
- CI pipeline (GitHub Actions): format + warnings-as-errors + credo strict + dialyzer + tests
- **rs-guard** integration: pre-commit hook + `.github/review-prompt.md` + `.reviewer.toml`
- **CodeRabbit** CI configuration
- `.credo.exs` with strict checks + custom check for no country/provider branching
- `.dialyzer_ignore.exs` baseline
- `AGENTS.md` (coding guidelines, TDD policy, code org contract, review loop)
- `CHANGELOG.md` initialized (Keep-a-Changelog format)
- `docs/adr/` directory with ADR template
- `docs/postman/debt-stalker.json` skeleton (empty collection with environment variables)
- `.tool-versions` (Elixir + Erlang pinned)

**Out of scope (deferred to Phase 1):** Any domain logic, schemas, migrations (beyond Oban's), controllers, LiveViews, workers, business rules, **k8s manifests** (they reference actual components — web deployment, worker deployment, ingress, migration job — that don't exist until Phase 1 builds them). Phase 0 is purely infrastructure and tooling.

---

## 2. Product Perspective

### 2.1 Personas
- **Developer / Agent** — needs a green, reproducible starting point with all quality gates operational.
- **Reviewer** — needs rs-guard + CodeRabbit configured so every subsequent PR gets automated review.

### 2.2 User Stories & Acceptance Criteria

**US-0.1 — Runnable skeleton**
> As a developer, I can clone the repo and have a running Phoenix app in under 5 minutes.
- **AC0.1.1** `make setup` installs deps, creates the database, runs migrations (Oban's only).
- **AC0.1.2** `make run` starts the Phoenix server with LiveView enabled.
- **AC0.1.3** `http://localhost:4000` shows a placeholder page (no domain content).
- **AC0.1.4** Docker Compose provides Postgres 16 on port 5432.

**US-0.2 — Quality gates operational**
> As a developer, all quality gates pass on the empty skeleton.
- **AC0.2.1** `mix format --check-formatted` passes.
- **AC0.2.2** `mix credo --strict` passes (zero warnings).
- **AC0.2.3** `mix dialyzer` passes (zero warnings, no PLT errors).
- **AC0.2.4** `mix test` passes (at least a smoke test verifying the app boots).
- **AC0.2.5** `mix docs` generates without warnings.

**US-0.3 — Code review infrastructure**
> As a reviewer, automated code review is configured locally and in CI.
- **AC0.3.1** rs-guard pre-commit hook is installed and functional (runs on `git commit`).
- **AC0.3.2** `.github/review-prompt.md` is committed with project-specific rules.
- **AC0.3.3** `.reviewer.toml` is committed with DeepSeek Pro configuration.
- **AC0.3.4** CodeRabbit is configured (`.coderabbit.yaml` or equivalent) for CI review.
- **AC0.3.5** rs-guard runs in CI on PRs (`.github/workflows/ai-review.yml`).

**US-0.4 — Development guidelines documented**
> As a new developer or agent, I can read AGENTS.md and understand all conventions.
- **AC0.4.1** `AGENTS.md` documents: TDD policy (hard gate per feature), code organization contract (§4.8 of master plan), review loop (max 3 iterations), error handling strategy, logging spec, testing strategy.
- **AC0.4.2** `AGENTS.md` lists all Makefile commands and their purpose.
- **AC0.4.3** `AGENTS.md` references the master plan and phase docs as canonical sources.

**US-0.5 — Phase documentation infrastructure**
> As an agent, phase documentation artifacts are ready to be populated.
- **AC0.5.1** `CHANGELOG.md` exists with `## [Unreleased]` section.
- **AC0.5.2** `docs/adr/` directory exists with `0000-template.md`.
- **AC0.5.3** `docs/postman/debt-stalker.json` exists as a valid Postman collection skeleton with environment variables (`base_url`, `jwt_token_read`, `jwt_token_update`).

### 2.3 Verification Script (what "done" looks like)
1. `git clone` → `make setup` → `make test` → all green.
2. `mix credo --strict` → clean.
3. `mix dialyzer` → clean.
4. `mix docs` → opens ExDoc without warnings.
5. Make a test commit → rs-guard pre-commit hook fires.
6. Push a branch → open PR → rs-guard + CodeRabbit both post reviews.

---

## 3. Technical Scope

### 3.1 Phoenix Application
- `mix phx.new debt_stalker --database postgres --live`
- Single application (not umbrella)
- `mix.exs` with all deps pinned

### 3.2 Dependencies

| Dep | Purpose | Env |
|-----|---------|-----|
| `phoenix` | Web framework | all |
| `phoenix_live_view` | Realtime UI | all |
| `ecto_sql` | DB layer | all |
| `postgrex` | Postgres driver | all |
| `oban` | Background jobs | all |
| `joken` | JWT auth | all |
| `logger_json` | Structured JSON logs | all |
| `credo` | Linting | dev/test |
| `dialyxir` | Type checking | dev/test |
| `ex_doc` | API documentation | dev/test |
| `mox` | Provider mocking | test |
| `stream_data` | Property-based testing | test |

### 3.3 Configuration
- `config/dev.exs` — debug logging, dev database, LiveView enabled
- `config/test.exs` — warning log level, test database, Ecto sandbox, Mox global mode
- `config/runtime.exs` — env-driven config (JWT secret, DB URL, Oban queues, log level)
- `.tool-versions` — `elixir 1.18.x` + `erlang 27.x` (pin to current stable at implementation time)

### 3.4 Makefile Commands
```makefile
setup:    ## Install deps, create DB, run migrations
db:       ## Create + migrate database
migrate:  ## Run migrations
seed:     ## Run seeds (empty in Phase 0)
run:      ## Start Phoenix server
test:     ## Run full test suite
format:   ## Format code
lint:     ## Run credo --strict
dialyzer: ## Run dialyzer
docs:     ## Generate ExDoc
```

> **Note:** `k8s-apply` is added in Phase 1 when k8s manifests are created.

### 3.5 CI Pipeline (`.github/workflows/ci.yml`)
Stages:
1. Checkout + setup Elixir/Erlang (from `.tool-versions`)
2. `mix deps.get`
3. `mix format --check-formatted`
4. `mix compile --warnings-as-errors`
5. `mix credo --strict`
6. `mix dialyzer --halt-exit-status` (with PLT caching)
7. `mix test`

> **Note:** k8s dry-run validation (`kubectl apply --dry-run=client -f k8s/`) is added to CI in Phase 1 when k8s manifests are created.

### 3.6 rs-guard Integration

**Pre-commit hook** (`.git/hooks/pre-commit`):
- Loads API key from `~/.config/rs-guard/env` or environment
- Runs `rs-guard` on staged changes
- Exit 2 (REQUEST_CHANGES) blocks the commit
- Exit 0 (APPROVE/COMMENT) allows the commit
- Bypass: `git commit --no-verify`

**`.reviewer.toml`**:
```toml
provider = "deepseek"
model = "deepseek-v4-pro"
temperature = 0.1
```

**`.github/review-prompt.md`**: See the dedicated file (drafted alongside this phase doc). Covers:
- Five review axes: Correctness, Security, Architecture, Readability, Performance
- Project-specific rules: `@doc`/`@spec` required, cursor pagination, no country branching, PII never logged, workers idempotent, migrations reversible
- rs-guard metadata block format

**CI review** (`.github/workflows/ai-review.yml`):
- Runs rs-guard on PRs (CI mode, fetches PR diff)
- CodeRabbit configured via `.coderabbit.yaml`

### 3.7 AGENTS.md Content
- Project overview + tech stack
- TDD policy: hard gate per feature (test-first for `[DOMAIN]`, `[ASYNC]`, `[API]`, `[WEB]` tasks; exempt for `[CHORE]`, `[INFRA]`, `[DB]`, `[OPS]`, `[DOCS]`)
- Code organization contract (from master plan §4.8)
- Review loop: implement → rs-guard → evaluate → iterate (max 3)
- Error handling strategy (from master plan §4.9)
- Logging spec (from master plan §4.10)
- Testing strategy (from master plan §4.11)
- Makefile command reference
- Links to master plan, phase docs, ADR directory

### 3.8 Credo Configuration (`.credo.exs`)
- Strict mode enabled
- All default checks at strict level
- Custom check module: `DebtStalker.CredoChecks.NoCountryBranching` — fails if `if/cond/case` on country/provider code appears outside `DebtStalker.Countries` / `DebtStalker.Providers`
- Custom check: `DebtStalker.CredoChecks.RequireSpec` — fails if public function lacks `@spec`
- Custom check: `DebtStalker.CredoChecks.NoIOInspect` — fails if `IO.inspect` is used

### 3.9 Dialyzer Configuration
- `.dialyzer_ignore.exs` — empty baseline (only known false positives documented)
- PLT caching in CI (save/restore via actions/cache)
- `--halt-exit-status` in CI

### 3.10 Documentation Infrastructure
- `CHANGELOG.md` — Keep-a-Changelog format, `## [Unreleased]` section
- `docs/adr/0000-template.md` — ADR template
- `docs/postman/debt-stalker.json` — Postman collection skeleton with:
  - Environment: `base_url` (localhost:4000), `jwt_token_read`, `jwt_token_update`
  - Folder structure: `Auth`, `Applications`, `Webhooks` (empty, populated in Phase 1)

---

## 4. Definition of Done

- [ ] `make setup` succeeds: deps installed, DB created, Oban migrations run.
- [ ] `make run` starts Phoenix server; `localhost:4000` shows placeholder page.
- [ ] `mix format --check-formatted` passes.
- [ ] `mix credo --strict` passes (zero warnings, custom checks active).
- [ ] `mix dialyzer` passes (zero warnings).
- [ ] `mix test` passes (smoke test: app boots, DB connection works).
- [ ] `mix docs` generates ExDoc without warnings.
- [ ] rs-guard pre-commit hook installed and functional (verified with a test commit).
- [ ] `.github/review-prompt.md` committed with project-specific rules.
- [ ] `.reviewer.toml` committed with DeepSeek Pro config.
- [ ] `.github/workflows/ci.yml` runs all stages green on push.
- [ ] `.github/workflows/ai-review.yml` runs rs-guard on PRs.
- [ ] CodeRabbit configured (`.coderabbit.yaml` or equivalent).
- [ ] `AGENTS.md` committed with all guidelines.
- [ ] `.credo.exs` committed with strict checks + custom checks.
- [ ] `.dialyzer_ignore.exs` committed (empty baseline).
- [ ] `.tool-versions` committed (Elixir + Erlang pinned).
- [ ] `CHANGELOG.md` committed with `## [Unreleased]` section.
- [ ] `docs/adr/` directory exists with `0000-template.md`.
- [ ] `docs/postman/debt-stalker.json` committed (valid Postman collection skeleton).
- [ ] Docker Compose provides Postgres 16; `docker compose up -d` works.
- [ ] **Phase 0 Completion Report** written to `docs/phases/phase-0-report.md`.
- [ ] **CHANGELOG.md** updated with Phase 0 entry.
- [ ] **ADR-0001** written: "Use Phoenix single-app with Oban + Joken + Credo + Dialyzer stack."

---

## 5. Phase 0 Risks (delta from master register)

| Risk | Mitigation |
|------|------------|
| Dialyzer PLT build is slow in CI | Cache PLT via `actions/cache`; use `--plt` only on dep changes |
| Credo custom checks are non-trivial to write | Start with default strict checks; add custom checks incrementally |
| rs-guard API key not available in all environments | Document setup in AGENTS.md; hook degrades gracefully (exit 1 on error, not exit 2) |
| `.tool-versions` pins wrong Elixir version | Verify against Phoenix 1.8 compatibility at implementation time |
| Postman collection skeleton format errors | Validate JSON with `jq . docs/postman/debt-stalker.json` |

---

## 6. Task Seeds (TDD-exempt — infrastructure tasks)

> Phase 0 tasks are **TDD-exempt** (infrastructure/scaffolding). Tests are included where applicable (smoke test, config test) but the test-first gate does not apply. Each task still goes through the rs-guard review loop.

- **[CHORE] T0.0 — Create feature branch** · *AC:* branch `phase-0-foundation` created from `main`.
- **[INFRA] T0.1 — `mix phx.new` + deps in `mix.exs`** · *AC:* Phoenix app generated; all deps from §3.2 added; `mix deps.get` succeeds.
- **[INFRA] T0.2 — Configuration files (`dev.exs`, `test.exs`, `runtime.exs`)** · *AC:* configs written; `runtime.exs` reads JWT secret + DB URL from env; fail-fast on missing prod secrets.
- **[INFRA] T0.3 — `.tool-versions`** · *AC:* Elixir + Erlang versions pinned; compatible with Phoenix 1.8 + all deps.
- **[INFRA] T0.4 — Docker Compose for Postgres** · *AC:* `docker compose up -d` starts Postgres 16 on port 5432; healthcheck configured.
- **[INFRA] T0.5 — Makefile** · *AC:* all commands from §3.4 work; `make setup && make test` is green.
- **[INFRA] T0.6 — CI pipeline (`.github/workflows/ci.yml`)** · *AC:* all 7 stages run; green on push to `main`; PLT cached.
- **[INFRA] T0.7 — rs-guard pre-commit hook + `.reviewer.toml`** · *AC:* hook installed; `rs-guard` runs on commit; `.reviewer.toml` uses DeepSeek Pro.
- **[DOCS] T0.8 — `.github/review-prompt.md`** · *AC:* prompt covers 5 axes + project-specific rules; rs-guard metadata block format correct.
- **[INFRA] T0.9 — CodeRabbit configuration** · *AC:* `.coderabbit.yaml` committed; CodeRabbit posts review on PR.
- **[INFRA] T0.10 — `.github/workflows/ai-review.yml`** · *AC:* rs-guard runs in CI mode on PRs; uses `RS_GUARD_GITHUB_TOKEN` secret.
- **[INFRA] T0.11 — `.credo.exs` with strict checks** · *AC:* `mix credo --strict` passes; custom check stubs created (full implementation may extend into Phase 1).
- **[INFRA] T0.12 — `.dialyzer_ignore.exs` baseline** · *AC:* `mix dialyzer` passes; ignore file empty or documented.
- **[DOCS] T0.13 — `AGENTS.md`** · *AC:* all guidelines from §3.7 documented; references master plan + phase docs.
- **[DOCS] T0.14 — `CHANGELOG.md` + `docs/adr/0000-template.md`** · *AC:* CHANGELOG has `## [Unreleased]` section; ADR template committed.
- **[DOCS] T0.15 — `docs/postman/debt-stalker.json` skeleton** · *AC:* valid Postman collection JSON; environment variables defined; folder structure created.
- **[QA] T0.16 — Smoke test** · *AC:* a test file verifies the app boots and DB connection works; `mix test` includes this.
- **[DOCS] T0.17 — Phase 0 Completion Report + ADR-0001** · *AC:* `docs/phases/phase-0-report.md` written; `docs/adr/0001-phoenix-stack-decision.md` written; CHANGELOG updated with Phase 0 entry.

---

## 7. Relevant Files

| File | Created in | Purpose |
|------|-----------|---------|
| `mix.exs` | T0.1 | Project config + deps |
| `config/dev.exs`, `config/test.exs`, `config/runtime.exs` | T0.2 | Environment config |
| `.tool-versions` | T0.3 | Version pinning |
| `docker-compose.yml` | T0.4 | Postgres for local dev |
| `Makefile` | T0.5 | Task automation |
| `.github/workflows/ci.yml` | T0.6 | CI pipeline |
| `.github/workflows/ai-review.yml` | T0.10 | rs-guard CI review |
| `.github/review-prompt.md` | T0.8 | rs-guard review prompt |
| `.reviewer.toml` | T0.7 | rs-guard config |
| `.coderabbit.yaml` | T0.9 | CodeRabbit config |
| `.credo.exs` | T0.11 | Credo strict config |
| `.dialyzer_ignore.exs` | T0.12 | Dialyzer ignores |
| `AGENTS.md` | T0.13 | Development guidelines |
| `CHANGELOG.md` | T0.14 | Change log |
| `docs/adr/0000-template.md` | T0.14 | ADR template |
| `docs/postman/debt-stalker.json` | T0.15 | Postman collection |
| `docs/phases/phase-0-report.md` | T0.17 | Phase completion report |
| `docs/adr/0001-phoenix-stack-decision.md` | T0.17 | First ADR |
