# Page HTML Templates (`lib/debt_stalker_web/controllers/page_html/`)

This folder contains HEEx templates rendered by `DebtStalkerWeb.PageController` for the browser companion UI: the marketing home page, admin login form, and static pages.

## Responsibilities

- Render HTML pages that do not require a LiveView process.
- Provide the admin login form and applicant selection page.
- Include shared components from `DebtStalkerWeb.CoreComponents`.

## Key templates

| Template | Controller action | Purpose |
| -------- | ----------------- | ------- |
| `home.html.heex` | `PageController.home/2` | Marketing landing page with applicant/admin entry points. |
| `login.html.heex` | `PageController.login/2` | Admin password login form. |

## Important notes

- These templates are plain HEEx, not LiveView. They render once per request and do not maintain server state.
- The login form submits to `POST /admin/login` handled by `PageController.do_login/2`.
- The home page links to `/apply?role=applicant` (persona selection) and `/admin/login`.

## Where to look next

- `lib/debt_stalker_web/controllers/page_controller.ex` — the controller that renders these templates.
- `lib/debt_stalker_web/components/core_components.ex` — shared components used in the templates.
- `lib/debt_stalker_web/router.ex` — routes for `/`, `/admin/login`, and `/apply`.
