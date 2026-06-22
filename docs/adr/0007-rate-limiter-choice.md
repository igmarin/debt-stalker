# ADR-0007: Rate Limiter Choice (Hammer)

## Status

Accepted

## Context

Phase 2 (US-13) requires rate limiting on auth token issuance and webhook endpoints (AC13.1, AC13.2). The limiter must:

- Rate-limit per client IP
- Return `429` with a `Retry-After` header when exceeded
- Be configurable via environment variables
- Integrate cleanly with Phoenix plugs
- Require no external infrastructure (Redis, etc.) for the single-region deployment

## Decision

Use **Hammer** (v6.x) with the ETS backend.

Hammer is a mature Elixir rate limiter that provides a simple `check_rate/3` API with a sliding window algorithm. The ETS backend requires no external dependencies (no Redis, no Postgres) and is sufficient for a single-node deployment. The backend can be swapped to Redis (`Hammer.Backend.Redis`) for multi-node deployments in Phase 4 without changing the plug code.

A thin Plug wrapper (`DebtStalkerWeb.Plugs.RateLimit`) encapsulates the Hammer calls and reads limits from application config, making the limits configurable via env vars in `runtime.exs`.

### Alternatives considered

| Option | Rejected because |
|--------|-----------------|
| `plug_attack` | Less maintained, no sliding window, simpler but less flexible |
| Custom ETS-based limiter | Reinvents the wheel; Hammer is battle-tested and well-maintained |
| Redis-based limiter | Requires Redis infrastructure not present in Phase 2; deferred to Phase 4 multi-node |

## Consequences

### Positive

- No external infrastructure needed (ETS backend)
- Simple `check_rate(bucket, window, limit)` API
- Configurable per-endpoint limits via env vars
- Backend swappable to Redis for multi-node without plug changes
- Well-maintained, hex.pm package with stable API

### Negative

- ETS backend is per-node; rate limits are not shared across multiple instances (acceptable for Phase 2 single-region; Phase 4 can switch to Redis backend)
- Adds `hammer` + `poolboy` as dependencies

### Neutral

- Rate limit state is in-memory and resets on restart (acceptable for rate limiting)
