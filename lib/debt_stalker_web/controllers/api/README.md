# API Controllers (`lib/debt_stalker_web/controllers/api/`)

This subfolder contains the JSON API controllers under the `/api` scope. Each controller is mapped in `lib/debt_stalker_web/router.ex` and uses the `:api` pipeline.

## Responsibilities

- Implement health, auth, application, and webhook endpoints.
- Return JSON responses and HTTP status codes matching the API contract.
- Validate params and authentication before delegating to contexts.

## Key modules

| Module | Purpose |
| ------ | ------- |
| `health_controller.ex` | `/api/health`, `/api/health/live`, `/api/health/ready`. |
| `auth_controller.ex` | `/api/auth/token`. |
| `application_controller.ex` | `/api/applications` CRUD and status update. |
| `webhook_controller.ex` | `/api/webhooks/provider-confirmations`. |

## API contract overview

All endpoints under `/api` accept and return JSON. Dates are ISO 8601; decimals are strings. Identity documents are redacted to last-4 in responses. Full names are returned in plain text on authorized surfaces.

### Authentication

Include `Authorization: Bearer <token>` where the token is obtained from `POST /api/auth/token` with `{"role": "read"}` or `{"role": "update"}`.

### Roles

- `read` — `GET /api/applications`, `GET /api/applications/:id`.
- `update` — includes `read` plus `POST /api/applications` and `PATCH /api/applications/:id/status`.

### Rate limiting

- `POST /api/auth/token` — limited by `auth_token` config (default 10 requests per IP per minute).
- `POST /api/webhooks/provider-confirmations` — limited by `webhook` config (default 20 requests per IP per minute).

### Error shapes

- `401` — `{"error": "unauthorized"}` (invalid or missing JWT).
- `403` — `{"error": "forbidden"}` (insufficient role).
- `404` — `{"error": "not_found"}`.
- `422` — `{"error": "invalid_transition"}` or `{"errors": %{field: [message]}}` for changeset errors.
- `429` — `{"error": "rate_limit_exceeded"}` with `Retry-After` header.

## Where to look next

- `lib/debt_stalker_web/router.ex` — API routes and pipeline.
- `lib/debt_stalker_web/auth/` — JWT verification and role enforcement.
- `lib/debt_stalker_web/plugs/rate_limit.ex` — rate-limit implementation.
- `docs/postman/debt-stalker.json` — Postman collection (may need updates, see audit notes).
