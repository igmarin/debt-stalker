# LiveViews (`lib/debt_stalker_web/live/`)

This folder contains Phoenix LiveViews for the browser UI. LiveViews are organized into two personas: **applicant** (apply for credit, track status) and **admin** (dashboard, list, detail). All LiveViews call domain contexts and subscribe to PubSub for real-time updates.

## Responsibilities

- Render interactive, real-time HTML for applicants and admins.
- Validate form input and delegate persistence to `DebtStalker.Applications`.
- Subscribe to PubSub topics so the UI updates when application status changes.
- Enforce persona roles via `DebtStalkerWeb.Live.RoleAuth`.

## Key modules

| Module | Purpose |
| ------ | ------- |
| `role_auth.ex` | LiveView `on_mount` hook that enforces browser persona roles. |
| `apply/application_form_live.ex` | Applicant-facing credit application form. |
| `apply/application_confirmation_live.ex` | Submission confirmation and status tracker. |
| `admin/dashboard_live.ex` | Admin dashboard with KPIs, charts, and recent applications. |
| `admin/applications_live.ex` | Admin list of applications with filters, sorting, and pagination. |
| `admin/application_detail_live.ex` | Admin detail page with summary, provider data, audit trail, and status update. |

## Public API

### `DebtStalkerWeb.Live.RoleAuth`

#### `on_mount(required_role :: atom(), _params, session, socket) :: {:cont, socket} | {:halt, socket}`

- `:applicant` — allows only `"applicant"` session role; redirects to `/` otherwise.
- `:admin` — allows only `"admin"` session role; redirects to `/admin/login` otherwise.
- `:any` — requires a role to be set but does not restrict it.

## Important notes

- **Role enforcement**: every LiveView in this folder declares `on_mount {DebtStalkerWeb.Live.RoleAuth, :applicant}` or `:admin`.
- **PubSub subscriptions**: list views subscribe to `applications:list`; detail and confirmation views subscribe to `applications:<id>`.
- **URL as state**: admin filters and pagination are stored in query parameters via `push_patch/2`; `DebtStalkerWeb.Admin.FilterParams` parses and serializes them.
- **Form validation**: `ApplicationFormLive` uses `Ecto.Changeset` action `:validate` for real-time feedback and `:insert` on submit.
- **No business logic**: status transitions and risk evaluation are delegated to `DebtStalker.Applications`; LiveViews only render results and flash messages.

## Where to look next

- `lib/debt_stalker_web/live/admin/` — admin LiveViews and `FilterParams`.
- `lib/debt_stalker_web/live/apply/` — applicant LiveViews.
- `lib/debt_stalker_web/components/` — UI components consumed by LiveViews.
- `lib/debt_stalker/applications.ex` — context used by all LiveViews.
