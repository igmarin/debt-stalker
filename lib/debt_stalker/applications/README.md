# Applications Context (`lib/debt_stalker/applications/`)

This folder owns the lifecycle of a credit application: creation, listing, status transitions, audit logging, and dashboard analytics. It is the central orchestration context of the domain layer.

## Responsibilities

- Create and validate new credit applications.
- List and filter applications with cursor or offset pagination.
- Transition application status according to country-specific rules.
- Fetch provider summaries and evaluate risk.
- Cache per-application reads and broadcast changes over PubSub.
- Maintain an append-only audit trail of status changes.
- Compute dashboard KPIs and analytics.

## Key modules

| Module | Purpose |
| ------ | ------- |
| `applications.ex` | Public context for create/list/get/update/analytics. |
| `credit_application.ex` | Ecto schema for the `credit_applications` table. |
| `status_transition.ex` | Ecto schema for the `application_status_transitions` table. |
| `audit_log.ex` | Ecto schema for the `audit_logs` table. |

## Public API

### `DebtStalker.Applications`

#### `create_application(attrs :: map()) :: {:ok, CreditApplication.t()} | {:error, Ecto.Changeset.t()}`

Creates a new application. Validates the country via the country registry, validates the identity document using the country module, fetches the provider summary through the circuit breaker, evaluates risk, sets the server timestamp, and inserts the record. On success, broadcasts `{:application_created, app}` to `applications:list` and `applications:<id>`.

#### `list_applications(filters :: map()) :: %{entries: [CreditApplication.t()], cursor: String.t() | nil, ...}`

Returns a paginated list of applications. Supports filtering by `country`, `status`, `date_from`, `date_to`, `sort_by`, `sort_dir`, and `cursor` (cursor pagination) or `page`/`per_page` (offset pagination). Results are returned as a map with `entries`, `cursor`, `total_count`, `total_pages`, `page`, `per_page` when applicable.

#### `get_application(id :: Ecto.UUID.t()) :: {:ok, CreditApplication.t()} | {:error, :not_found}`

Fetches a single application by id, using Cachex for the happy path. Returns `{:error, :not_found}` when the id does not exist.

#### `update_status(id :: Ecto.UUID.t(), status :: String.t(), triggered_by :: String.t()) :: {:ok, CreditApplication.t()} | {:error, :not_found | :invalid_transition | Ecto.Changeset.t()}`

Transitions an application to a new status. Validates the transition against the country module's allowed list, inserts a status-transition row, writes an audit log, and broadcasts `{:status_changed, %{application_id: id, ...}}`. Returns `{:error, :invalid_transition}` when the country module rejects the move.

#### `allowed_transitions(app :: CreditApplication.t()) :: [String.t()]`

Returns the list of statuses the given application can move to next, according to its country rules.

#### `dashboard_analytics(filters :: map()) :: %{stats: map(), status_breakdown: [...], by_country: [...], timeline: [...]}`

Computes dashboard KPIs: total counts, pending risk, additional review, provider errors, decided today, status distribution, country breakdown, and a 7-day timeline.

#### `count_applications_by_status(filters :: map()) :: [{status :: String.t(), count :: integer()}]`

Counts applications grouped by status, respecting the same filters as the list.

## Schemas

### `CreditApplication`

Fields:

- `id` (binary id)
- `country` (string, validated against the country registry)
- `full_name` (string, plain on authorized surfaces)
- `identity_document` (encrypted binary via Cloak)
- `identity_document_hash` (string, for deduplication/lookup)
- `requested_amount` / `monthly_income` (`Decimal`)
- `application_date` (utc datetime, server-set)
- `status` (string, default `"submitted"`)
- `additional_review_required` (boolean)
- `provider_summary` (map, normalized provider data)
- `risk_result` (map, optional risk evaluation result)

Important functions:

- `changeset/2` — validates required fields, country support, document format, and decimal positivity.
- `redact_document/1` — returns the last four characters of the identity document (or `"****"` for short inputs).
- `redact_full_name/1` — returns first name + last initial.
- `valid_statuses/0` — returns the list of valid statuses.

### `StatusTransition`

Records every valid status change with `from_status`, `to_status`, `reason`, and `triggered_by`. No `updated_at` column; it is append-only.

### `AuditLog`

Records actions with `action`, `actor`, and `metadata` map. Written synchronously inside `update_status/3` via `Ecto.Multi`.

## Important notes

- **Country rules are delegated**: `create_application` calls `DebtStalker.Countries.Registry.lookup/1` and `DebtStalker.Providers.Registry.lookup/1`; there is no `if country == "ES"` logic in this context.
- **Provider errors are normalized**: provider failures are surfaced as `{:error, :provider_error}` to public callers, regardless of the underlying provider error atom.
- **Cache TTL**: reads are cached for 60 seconds (configurable via `:app_cache_ttl_ms`). The `CacheInvalidator` clears the cache on status changes.
- **Status broadcasting**: all successful updates publish `{:status_changed, details}` to `applications:list` and `applications:<id>` so LiveViews can refresh.

## Where to look next

- `lib/debt_stalker/countries/` — country-specific rules.
- `lib/debt_stalker/providers/` — provider adapters and circuit breakers.
- `lib/debt_stalker/risk.ex` — risk evaluation logic.
- `lib/debt_stalker/workers/` — Oban workers triggered by the outbox.
- Tests: `test/debt_stalker/applications_test.exs` and `test/debt_stalker/applications/`.
