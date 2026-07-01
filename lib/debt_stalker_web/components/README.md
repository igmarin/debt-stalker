# Components (`lib/debt_stalker_web/components/`)

This folder contains shared Phoenix components used by the LiveViews and controllers. The components are thin markup functions built on top of Tailwind CSS and DaisyUI; they do not contain business logic.

## Responsibilities

- Render reusable UI pieces: inputs, tables, headers, badges, empty states, pagination.
- Build admin-specific components: filters, charts, pagination controls.
- Provide localization-aware formatting helpers for status, money, numbers, and datetimes.
- Keep styling consistent across the applicant and admin surfaces.

## Key modules

| Module | Purpose |
| ------ | ------- |
| `core_components.ex` | Default Phoenix core components: flash, button, input, table, list, icon, JS commands, error translation. |
| `ui.ex` | Application-specific UI: status badges, stat cards, empty states, skeletons, audit timeline, money/number formatting. |
| `admin_filters.ex` | Filter bar and active filter chips for admin LiveViews. |
| `charts.ex` | Chart.js canvas components for dashboard (status pie, timeline, country bar). |
| `pagination.ex` | Page-based pagination controls with prev/next and page summary. |
| `cursor_pagination.ex` | Cursor-based "Load more" pagination controls. |
| `layouts/` | Root and live layouts. |

## Public API (selected)

### `DebtStalkerWeb.Components.UI`

#### `status_badge(assigns :: %{status: String.t(), class: any()}) :: Phoenix.LiveView.Rendered.t()`

Renders a DaisyUI badge coloured by application status.

#### `format_money(amount :: Decimal.t() | nil, country :: String.t() | nil) :: String.t()`

Formats a decimal with the country currency symbol and thousand separators. Returns `""` for `nil`.

#### `format_number(integer() | nil) :: String.t()`

Formats an integer with thousand separators.

#### `format_status(atom() | String.t() | nil) :: String.t()`

Returns a localized, human-readable status label (e.g. `"Pending risk"`).

#### `status_options() :: [{String.t(), String.t()}]`

Returns options for a select input of all valid statuses.

#### `audit_timeline(assigns :: %{entries: [AuditLog.t()]}) :: Phoenix.LiveView.Rendered.t()`

Renders a vertical timeline of audit entries.

### `DebtStalkerWeb.Components.AdminFilters`

#### `filter_bar(assigns :: %{filters: map(), country_options: [String.t()], clear_path: String.t()})`

Renders a form bound to URL state for country, status, and date range filters.

#### `active_filter_chips(assigns :: %{filters: map()})`

Renders badges for the currently active filters.

### `DebtStalkerWeb.Components.Charts`

#### `status_pie_chart/1`, `timeline_chart/1`, `country_bar_chart/1`

Render `<canvas>` elements with `phx-hook="ChartHook"`. The client-side hook mounts Chart.js instances from the data attributes.

### `DebtStalkerWeb.Components.Pagination`

#### `pagination(assigns :: %{page: integer(), per_page: integer(), total_count: integer(), total_pages: integer()})`

Renders page controls with prev/next and a page-number range.

## Important notes

- **Components use Gettext**: strings are marked for translation; default locale is `es`.
- **Icons are Heroicons**: `icon/1` renders `<span class="hero-<name> ...">` classes, which are wired by the Heroicons/Tailwind plugin.
- **Charts are client-rendered**: the server sends JSON data attributes; the `ChartHook` in `assets/js/app.js` mounts the Chart.js canvas.
- **No business logic**: components format and display data provided by LiveViews; they do not call contexts or mutate state.

## Where to look next

- `lib/debt_stalker_web/live/admin/` — consumers of `AdminFilters`, `Charts`, `Pagination`, and `UI`.
- `assets/js/app.js` — client-side hooks including `ChartHook`.
- `lib/debt_stalker_web/components/layouts/` — root/live layouts.
