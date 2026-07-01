# Admin Query Helpers (`lib/debt_stalker_web/admin/`)

This folder contains helper modules used by the admin LiveViews to keep URL query parameters as the single source of truth for filters, sorting, and pagination.

## Responsibilities

- Parse URL query parameters into a validated filter map.
- Serialize filter maps back into query strings for `push_patch/2`.
- Define allowed sort fields and default sort direction.
- Format dates for HTML date inputs.

## Key modules

| Module | Purpose |
| ------ | ------- |
| `filter_params.ex` | Parses and serializes admin filter query parameters. |

## Public API

### `DebtStalkerWeb.Admin.FilterParams`

#### `from_params(params :: map()) :: map()`

Builds a filter map from URL or form parameters. Fields include:

- `country` (string)
- `status` (string)
- `date_from` / `date_to` (`Date`)
- `sort_by` (string from allowed list)
- `sort_dir` (`"asc"` or `"desc"`)
- `cursor` (string, for cursor pagination)
- `limit` / `page` / `per_page` (positive integers)

Invalid or blank values are dropped.

#### `to_query(filters :: map()) :: map()`

Serializes a filter map into a query string map suitable for `push_patch/2`. Dates are formatted as ISO 8601; nil/blank values are omitted.

#### `format_date_for_input(date :: Date.t() | nil) :: String.t() | nil`

Formats a date for HTML `<input type="date">`.

#### `toggle_sort(filters :: map(), field :: String.t()) :: map()`

Returns a new filter map with the sort field set to `field` and direction toggled. If the current field is already `field` and direction is `"desc"`, switches to `"asc"`; otherwise defaults to `"desc"`. Also clears `cursor` and `page` to restart pagination.

#### `allowed_sort_fields() :: [String.t()]`

Returns the list of sortable columns: `application_date`, `full_name`, `requested_amount`, `country`, `status`.

## Important notes

- **URL as state**: every admin list interaction (filter, sort, paginate) updates the URL via `push_patch/2`. This makes filters shareable and the back button work correctly.
- **Validation**: `from_params/1` drops unknown sort fields, positive-int parsing rejects negative or non-numeric values, and date parsing rejects invalid ISO dates.
- **Cursor vs offset**: `DashboardLive` and `ApplicationsLive` use different pagination strategies; `FilterParams` supports both but callers choose which keys to use.

## Where to look next

- `lib/debt_stalker_web/live/admin/dashboard_live.ex` — uses `FilterParams` for dashboard filters.
- `lib/debt_stalker_web/live/admin/applications_live.ex` — uses `FilterParams` for list filters, sorting, and pagination.
- `lib/debt_stalker_web/components/admin_filters.ex` — renders the filter form bound to `FilterParams` state.
