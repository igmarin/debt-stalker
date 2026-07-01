# Web Layer (`lib/debt_stalker_web/`)

This directory contains the **transport layer** of Debt Stalker: HTTP routing, controllers, LiveViews, plugs, components, and telemetry. It owns serialization, authentication, and UI rendering, but **no business logic**. All domain actions are delegated to contexts in `DebtStalker`.

## Responsibilities

- Accept HTTP requests and route them to controllers or LiveViews.
- Authenticate API requests via JWT and browser sessions via session-based personas.
- Validate input at the transport boundary (params, forms, headers) before calling contexts.
- Render JSON API responses and HTML/LiveView UI.
- Apply rate limiting and PII redaction before leaving the transport layer.
- Expose telemetry and health endpoints for operators.

## Top-level modules

| Module | Responsibility |
| ------ | -------------- |
| `debt_stalker_web.ex` | Macro dispatcher for controllers, LiveViews, HTML components, and routers. |
| `endpoint.ex` | Phoenix endpoint: sockets, static assets, parsers, session, telemetry, and router. |
| `router.ex` | HTTP route definitions for browser, API, and dev-only dashboards. |
| `telemetry.ex` | Telemetry supervisor and metrics definitions (Phoenix, DB, VM, custom). |
| `gettext.ex` | Gettext backend for i18n (default locale `es`). |
| `error_html.ex` / `error_json.ex` | Error rendering for HTML and JSON formats. |

## Public surfaces

- **Browser** (`/`): marketing/home page, admin login, applicant/admin LiveViews, dev dashboard.
- **API** (`/api`): JWT-protected REST endpoints for applications and status changes, plus health and webhooks.
- **Webhooks** (`/api/webhooks/provider-confirmations`): HMAC-verified provider push events.
- **Health** (`/api/health`, `/api/health/live`, `/api/health/ready`): liveness/readiness probes.

## Important notes

- **Web calls contexts only**: controllers and LiveViews call `DebtStalker.Applications`, `DebtStalker.Audit`, etc. They never reach into `DebtStalker.Countries.Registry` directly.
- **PII redaction**: identity documents are redacted before JSON serialization (`CreditApplication.redact_document/1`). Full names are displayed on authorized surfaces only.
- **Roles**:
  - API: `read` (list/get) and `update` (create/update status).
  - Browser: `applicant` (apply/confirm) and `admin` (dashboard/list/detail).
- **Rate limiting**: `DebtStalkerWeb.Plugs.RateLimit` applies per-IP sliding windows to token generation and webhook ingestion.

## Where to look next

- `auth/` — JWT verification and session persona plugs.
- `plugs/` — rate limiting, locale, role assignment, raw body reader.
- `controllers/` — page and API controllers.
- `live/` — LiveViews for applicants and admins.
- `components/` — shared UI components, filters, charts, pagination.
- `admin/` — query parameter parsing for admin filters.
