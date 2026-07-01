# Controllers (`lib/debt_stalker_web/controllers/`)

This folder contains Phoenix controllers for browser pages and JSON API responses. Controllers validate input, call domain contexts, and render responses. They do not contain business rules.

## Responsibilities

- Render static marketing pages and the admin login flow.
- Serve API endpoints for health, auth, applications, and webhooks.
- Validate and transform params before passing them to contexts.
- Return appropriate HTTP status codes and JSON shapes.

## Key modules

| Module | Purpose |
| ------ | ------- |
| `page_controller.ex` | Home page, admin login/logout, role selection, legacy redirects. |
| `api/health_controller.ex` | Health, liveness, and readiness probes. |
| `api/auth_controller.ex` | JWT token generation endpoint for development. |
| `api/application_controller.ex` | REST endpoints for listing, getting, creating, and updating applications. |
| `api/webhook_controller.ex` | Receives, verifies, and enqueues provider webhook events. |

## Public API (selected)

### `DebtStalkerWeb.PageController`

#### `home/2`, `login/2`, `do_login/2`, `logout/2`

Marketing home page, login form, password check, and session logout. The admin password is read from `Application.fetch_env!(:debt_stalker, :admin_password)` and compared with `Plug.Crypto.secure_compare/2`.

#### `set_role/2`

Sets the browser persona to `applicant` and redirects to `/apply`. Rejects `role=admin` (admin must log in via password).

### `DebtStalkerWeb.Api.HealthController`

#### `index/2`, `liveness/2`, `readiness/2`

- `GET /api/health` — legacy endpoint returning `healthy`/`unhealthy` plus DB status.
- `GET /api/health/live` — liveness probe returning `alive`.
- `GET /api/health/ready` — readiness probe returning `ready` or `not_ready` based on DB reachability.

### `DebtStalkerWeb.Api.AuthController`

#### `create/2` for `AuthController`

`POST /api/auth/token` with `{"role": "read" | "update"}` returns a JWT. Rate-limited by `DebtStalkerWeb.Plugs.RateLimit`.

### `DebtStalkerWeb.Api.ApplicationController`

#### `index/2`

`GET /api/applications` — lists applications with filters and cursor pagination. Returns `%{data: [...], cursor: ...}`.

#### `show/2`

`GET /api/applications/:id` — returns a single application or 404.

#### `create/2` for `ApplicationController`

`POST /api/applications` — creates an application. Requires `update` role. Returns 201 on success or 422 with changeset errors.

#### `update_status/2`

`PATCH /api/applications/:id/status` — transitions status. Requires `update` role. Returns 200, 404, 422 (`invalid_transition`), or 422 (changeset errors).

### `DebtStalkerWeb.Api.WebhookController`

#### `receive_webhook/2`

`POST /api/webhooks/provider-confirmations` — verifies HMAC signature, deduplicates by payload hash, stores a `WebhookEvent` via `DebtStalker.Notifications`, and enqueues a `WebhookProcessingWorker`. Returns 200 `{"received": true}`, 401 for invalid signature, or 200 `{"status": "already_processed"}` for duplicates.

## Important notes

- **Authentication**: API controllers use `DebtStalkerWeb.Auth.AuthPlug` and `RequireRolePlug`. The browser controller uses session-based roles.
- **Rate limiting**: token generation and webhook ingestion are rate-limited per IP.
- **PII**: `ApplicationController.serialize_application/1` redacts the identity document to last-4. Full name is returned in plain text on authorized API surfaces.
- **Decimal parsing**: controllers parse string amounts into `Decimal` values before passing them to contexts.
- **Webhook raw body**: `Plug.Parsers` uses `DebtStalkerWeb.Plugs.RawBodyReader` to preserve the original body for HMAC verification.

## Where to look next

- `lib/debt_stalker_web/router.ex` — routes that dispatch to these controllers.
- `lib/debt_stalker_web/auth/` — JWT and role plugs.
- `lib/debt_stalker_web/plugs/` — rate limit and raw body reader.
- `lib/debt_stalker/applications.ex` — context called by the application controller.
- `lib/debt_stalker/notifications.ex` — context called by the webhook controller.
