# Authentication (`lib/debt_stalker_web/auth/`)

This folder contains the authentication modules for both the API (JWT) and the browser companion UI (session-based persona roles).

## Responsibilities

- Verify JWT tokens for API requests and assign a `current_role` claim.
- Enforce role-based access on API controllers (`read` vs `update`).
- Provide token generation for development/demo use.
- Assign browser persona roles (`applicant`, `admin`) from the session.

## Key modules

| Module | Purpose |
| ------ | ------- |
| `auth_plug.ex` | Plug that verifies the `Authorization: Bearer <jwt>` header. |
| `require_role_plug.ex` | Plug that halts with 403 unless the request has the required role. |
| `token.ex` | Joken configuration: token generation, verification, and role validation. |

## Public API

### `DebtStalkerWeb.Auth.AuthPlug`

#### `init/1` for `AuthPlug`

Plug init callback.

#### `call(conn :: Plug.Conn.t(), _opts :: keyword()) :: Plug.Conn.t()`

Extracts the JWT from the `Authorization` header, verifies it, and assigns `conn.assigns[:current_role]`. On failure, returns 401 and halts the connection.

### `DebtStalkerWeb.Auth.RequireRolePlug`

#### `init/1` for `RequireRolePlug`

Expects `role: "read"` or `role: "update"`.

#### `call(conn :: Plug.Conn.t(), opts :: keyword()) :: Plug.Conn.t()`

Returns 403 if `conn.assigns[:current_role]` does not satisfy the required role. The `update` role implies `read`.

### `DebtStalkerWeb.Auth.Token`

#### `token_config() :: Joken.token_config()`

Joken callback. Adds a custom `role` claim validated against `valid_role?/1` and default expiry of 3600 seconds.

#### `generate_token(role :: String.t()) :: {:ok, String.t()} | {:error, term()}`

Generates a signed HS256 JWT for the given role (`"read"` or `"update"`).

#### `verify_token(token :: String.t()) :: {:ok, map()} | {:error, term()}`

Verifies the signature and claim validity of a token.

## Important notes

- **JWT secret**: production uses the `JWT_SECRET` environment variable; dev/test use a hardcoded placeholder.
- **Token generation endpoint**: `POST /api/auth/token` is intentionally rate-limited and intended for development/demo only.
- **Session roles**: `DebtStalkerWeb.Plugs.AssignRole` sets the browser persona from the session. LiveViews enforce the role via `DebtStalkerWeb.Live.RoleAuth`.
- **No real user model**: the companion UI uses a single shared admin password (`ADMIN_PASSWORD`) and a public applicant selection. This is acceptable for the challenge but not a production identity provider.

## Where to look next

- `lib/debt_stalker_web/plugs/assign_role.ex` — session role assignment.
- `lib/debt_stalker_web/live/role_auth.ex` — LiveView role enforcement.
- `lib/debt_stalker_web/controllers/api/auth_controller.ex` — token generation endpoint.
- `lib/debt_stalker_web/controllers/page_controller.ex` — admin login/logout.
