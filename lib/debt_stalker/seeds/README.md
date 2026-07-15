# Seeds (`lib/debt_stalker/seeds/`)

This folder generates demo data for development, manual UI testing, and dashboards. It is invoked from `priv/repo/seeds.exs`.

## Responsibilities

- Build realistic and bulk demo credit applications.
- Use country modules to generate valid identity documents.
- Walk a subset of records through realistic status transitions so the audit trail and timeline are populated.
- Print demo credentials (admin UI password, API tokens) after seeding.

## Key modules

| Module | Purpose |
| ------ | ------- |
| `demo.ex` | Demo seed builder with `run/1`, `build_attrs/1`, and `create_realistic/1`. |

## Public API

### `DebtStalker.Seeds.Demo`

#### `run(opts :: keyword()) :: %{created: integer(), failed: integer(), realistic: integer(), bulk: integer()}`

Seeds the database. Options:

- `count` — total records (default `1000`).
- `mode` — `:bulk`, `:realistic`, or `:mixed` (default `:mixed`).
- `realistic_count` — number of lifecycled records in mixed mode (default `5`).
- `countries` — list of country codes (default `["ES", "MX", "PL"]`).
- `scenario` — `:default` or `:dashboard` (default `:default`).
- `quiet` — suppress per-record logging (default `false`).

Returns a summary map with counts.

#### `build_attrs(opts :: keyword()) :: map()`

Builds a single attribute map for an application. Uses `DebtStalker.Countries.random_identity_document/1` to generate a valid document for the chosen country.

#### `create_realistic(opts :: keyword()) :: {:ok, CreditApplication.t()} | {:error, term()}`

Creates one application through the real `Applications.create_application/1` context and then walks it through status transitions to a target status (`approved`, `rejected`, `pending_risk`, or `additional_review`).

#### `options_from_env() :: keyword()`

Reads `SEED_COUNT`, `SEED_MODE`, `SEED_REALISTIC_COUNT`, `SEED_COUNTRIES`, and `SEED_SCENARIO` from environment variables and returns a keyword list.

#### `print_credentials() :: :ok`

Prints the admin UI password and read/update API tokens to the console.

## Modes

- **`:realistic`** — every record goes through `create_realistic/1`, populating transitions, audit logs, and provider summaries. Slow but realistic.
- **`:bulk`** — direct `Repo.insert/1` with random statuses. Fast but no lifecycle history.
- **`:mixed`** — first `realistic_count` records are realistic, the rest are bulk. Good default for volume + a few lifecycled examples.

## Important notes

- **Seeds are not tests**: seed data uses the real contexts for realistic records but bypasses them for bulk records. Do not rely on seeds for correctness verification.
- **Application dates are randomized**: bulk records get a random date within the last 90 days via `random_application_date/0`.
- **Demo credentials are printed**: after seeding, `print_credentials/0` shows the admin password and JWT tokens useful for hitting the API.
- **Country coverage matches the registry**: only countries configured in `DebtStalker.Countries.Registry` can be seeded.

## Where to look next

- `priv/repo/seeds.exs` — the entry point that calls `Demo.run/1`.
- `lib/debt_stalker/countries.ex` — `random_identity_document/1` used by seeds.
- `lib/debt_stalker/applications.ex` — the context used by realistic mode.
- `Makefile` — `make seed` runs the seeds.
