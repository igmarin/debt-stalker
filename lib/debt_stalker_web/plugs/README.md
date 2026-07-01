# Plugs (`lib/debt_stalker_web/plugs/`)

This folder contains custom `Plug` modules that run in the HTTP request pipeline. They handle cross-cutting concerns: rate limiting, locale, session role assignment, and preserving the raw request body for webhook verification.

## Responsibilities

- Apply per-IP rate limiting for token generation and webhook ingestion.
- Set the default Gettext locale for browser requests.
- Assign the browser persona role from the session.
- Preserve the raw request body so `Plug.Parsers` does not consume it before HMAC verification.

## Key modules

| Module | Purpose |
| ------ | ------- |
| `rate_limit.ex` | Hammer-backed rate limiting with sliding windows per client IP. |
| `set_locale.ex` | Sets the default Gettext locale to `es` for browser requests. |
| `assign_role.ex` | Reads `"role"` from the session and assigns `:current_role`. |
| `raw_body_reader.ex` | Body reader that stores the raw body in `conn.assigns[:raw_body]`. |

## Public API

### `DebtStalkerWeb.Plugs.RateLimit`

#### `init(opts :: keyword()) :: keyword()`

Validates that `opts` contains `:key` (e.g. `:auth_token` or `:webhook`).

#### `call/2` for `RateLimit`

Looks up the limit config under `Application.get_env(:debt_stalker, :rate_limit)[key]`, checks the rate for the client IP via `Hammer.check_rate/3`, and either continues or halts with 429 and a `Retry-After` header.

#### `get_client_ip(conn :: Plug.Conn.t()) :: String.t()`

Resolves the client IP from the `X-Forwarded-For` header or `conn.remote_ip`, falling back to `"unknown"`.

### `DebtStalkerWeb.Plugs.SetLocale`

#### `call/2` for `SetLocale`

Sets `Gettext.put_locale(DebtStalkerWeb.Gettext, "es")` for the request process. The default locale is Spanish for Spain and Mexico.

### `DebtStalkerWeb.Plugs.AssignRole`

#### `call/2` for `AssignRole`

Reads `"role"` from the session, validates it is `"applicant"` or `"admin"`, and assigns `:current_role`. Does not enforce access; enforcement is done by `Live.RoleAuth` or controller-specific plugs.

### `DebtStalkerWeb.Plugs.RawBodyReader`

#### `read_body(conn :: Plug.Conn.t(), opts :: keyword()) :: {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()} | {:error, term()}`

Reads the request body and stores the full body in `conn.assigns[:raw_body]`. Used by `Plug.Parsers` in `endpoint.ex` so the webhook controller can verify the HMAC signature against the original bytes.

## Important notes

- **Rate limit configuration**: see `config/config.exs` and `config/runtime.exs` for `auth_token` and `webhook` limits. They are configurable via environment variables in production.
- **X-Forwarded-For handling**: the plug takes the leftmost IP in the header. This is correct when the app is behind a trusted proxy; otherwise it can be spoofed. Production ingress should sanitize this header.
- **Raw body memory**: `RawBodyReader` keeps the entire body in memory. For very large payloads, consider a streaming approach or a max body size guard.
- **Locale default**: the app currently defaults to Spanish for all browser requests; there is no language selector.

## Where to look next

- `lib/debt_stalker_web/router.ex` — where the plugs are piped.
- `lib/debt_stalker_web/endpoint.ex` — `Plug.Parsers` configuration using `RawBodyReader`.
- `lib/debt_stalker_web/auth/` — JWT and role enforcement plugs.
- `lib/debt_stalker_web/controllers/api/webhook_controller.ex` — consumer of `raw_body`.
- `config/config.exs` and `config/runtime.exs` — rate limit config.
