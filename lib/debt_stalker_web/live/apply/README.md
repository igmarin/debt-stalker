# Applicant LiveViews (`lib/debt_stalker_web/live/apply/`)

This folder contains the applicant-facing LiveViews: the credit application form and the confirmation/tracker page. These views require the `"applicant"` browser persona and provide real-time status updates.

## Responsibilities

- Render a multi-step application form with country-aware document hints.
- Validate input as the user types and display errors before submission.
- Create the application via `DebtStalker.Applications.create_application/1`.
- Show a confirmation page with the reference ID and live status updates.

## Key modules

| Module | Purpose |
| ------ | ------- |
| `application_form_live.ex` | Multi-step form for creating a credit application. |
| `application_confirmation_live.ex` | Confirmation and status tracker for a submitted application. |

## Public API

### `DebtStalkerWeb.Apply.ApplicationFormLive`

#### `mount/3`

Initializes the form from URL params, loads country options, and sets the document hint for the pre-selected country.

#### `handle_event("validate", %{"application" => params}, socket)`

Builds a changeset with action `:validate` and updates the document hint based on the selected country.

#### `handle_event("save", %{"application" => params}, socket)`

Submits the form through `Applications.create_application/1`. On success, redirects to `/apply/<id>/confirmation`; on error, re-renders the form with the changeset.

### `DebtStalkerWeb.Apply.ApplicationConfirmationLive`

#### `mount(%{"id" => id}, _session, socket)`

Loads the application by id, subscribes to `applications:<id>`, and shows a confirmation card with the reference ID, status badge, and application summary.

#### `handle_info({:status_changed, _}, socket)`

Refreshes the application and shows a flash message with the new status.

## Important notes

- **Authorization**: both LiveViews use `on_mount {DebtStalkerWeb.Live.RoleAuth, :applicant}`.
- **Document hints**: the country select drives the placeholder text for the identity document field via `DebtStalker.Countries.get_document_hint/1`.
- **Decimal parsing**: string amounts are parsed into `Decimal` before validation; empty strings become `nil`.
- **Real-time tracking**: the confirmation page subscribes to the per-application PubSub topic so the applicant sees status changes without refreshing.
- **Copy-to-clipboard**: the confirmation page includes a button that dispatches a `phx:copy` event handled by a client hook in `assets/js/app.js`.

## Where to look next

- `lib/debt_stalker/countries.ex` — document hints and currency symbols.
- `lib/debt_stalker/applications/credit_application.ex` — changeset and validation rules.
- `lib/debt_stalker/applications.ex` — context that creates the application and triggers the async pipeline.
- `assets/js/app.js` — client hooks for copy-to-clipboard and charts.
