# Admin LiveViews (`lib/debt_stalker_web/live/admin/`)

This folder contains the admin-facing LiveViews: dashboard, paginated application list, and detail page. These views require the `"admin"` browser persona and subscribe to real-time PubSub updates.

## Responsibilities

- Render the manager dashboard with KPIs, charts, and recent applications.
- Provide a filterable, sortable, paginated list of applications.
- Show a single application's details, provider summary, audit trail, and status transition control.
- Update in real time when applications are created or their status changes.

## Key modules

| Module | Purpose |
| ------ | ------- |
| `dashboard_live.ex` | Dashboard with stat cards, charts, and recent applications. |
| `applications_live.ex` | Paginated list with filters, sorting, and row highlighting. |
| `application_detail_live.ex` | Detail page with status update form and audit timeline. |

## Public API

### `DebtStalkerWeb.Admin.DashboardLive`

#### `mount/3` for `DashboardLive`

Subscribes to `applications:list`, loads country options, and sets the page title.

#### `handle_params/3` for `DashboardLive`

Parses URL filters via `FilterParams.from_params/1`, fetches `Applications.dashboard_analytics/1` and the 8 most recent applications.

#### `handle_event("filter", ...)` for `DashboardLive`

Updates the filter state and pushes a patched URL.

#### `handle_info/2` for `DashboardLive`

Reloads the dashboard data when a relevant PubSub event arrives.

### `DebtStalkerWeb.Admin.ApplicationsLive`

#### `mount/3` for `ApplicationsLive`

Subscribes to `applications:list`, sets page title, and initializes highlighted-row state.

#### `handle_params/3` for `ApplicationsLive`

Parses filters, applies default `page`/`per_page`, and calls `Applications.list_applications/1` with offset pagination.

#### `handle_event("filter", ...)` for `ApplicationsLive`

Resets pagination to page 1 and pushes the filtered URL.

#### `handle_event("paginate", ...)` for `ApplicationsLive`

Pushes a URL with the new page number.

#### `handle_event("sort", ...)` for `ApplicationsLive`

Toggles sort direction via `FilterParams.toggle_sort/2` and pushes the URL.

#### `handle_info/2` for `ApplicationsLive`

Refreshes the list and highlights the affected row for 2 seconds.

### `DebtStalkerWeb.Admin.ApplicationDetailLive`

#### `mount(%{"id" => id}, _session, socket)`

Loads the application, subscribes to `applications:<id>`, and redirects to the list if not found.

#### `handle_event("update_status", %{"status" => status}, socket)`

Calls `Applications.update_status/3` with `"admin"` as the actor and reloads the detail view.

#### `handle_info({:status_changed, _}, socket)`

Refreshes the application details when a status change is broadcast.

## Important notes

- **Authorization**: all admin LiveViews use `on_mount {DebtStalkerWeb.Live.RoleAuth, :admin}`.
- **Real-time updates**: list views subscribe to the global list topic; detail views subscribe to the per-application topic.
- **Row highlighting**: `ApplicationsLive` briefly highlights a newly created or updated row so the user notices the change.
- **Status transition gating**: `ApplicationDetailLive` only renders the status update form when `Applications.allowed_transitions/1` returns a non-empty list.

## Where to look next

- `lib/debt_stalker_web/admin/filter_params.ex` — URL filter parsing and serialization.
- `lib/debt_stalker_web/components/admin_filters.ex` — shared filter bar.
- `lib/debt_stalker_web/components/charts.ex` — dashboard charts.
- `lib/debt_stalker_web/components/pagination.ex` — page controls.
- `lib/debt_stalker/applications.ex` — context that provides data and status transitions.
