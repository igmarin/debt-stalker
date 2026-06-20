# Debt Stalker

Multi-country credit-application core for a fintech operating in 6 countries (ES, PT, IT, MX, CO, BR). Built with Elixir + Phoenix + PostgreSQL + Oban + LiveView.

## Quick Start

```bash
# Prerequisites: Elixir 1.18.x, Erlang/OTP 27.x, Docker

# Start Postgres
docker compose up -d

# Setup and run
make setup
make run
```

Visit [`localhost:4000`](http://localhost:4000).

## Development

```bash
make test       # Run test suite
make lint       # Credo strict
make dialyzer   # Type checking
make docs       # Generate ExDoc
make format     # Format code
```

## Documentation

- [Master Plan](docs/master-plan.md)
- [Requirements](docs/requirements.md)
- [Phase 0 — Foundation](docs/phases/phase-0.md)
- [Phase 1 — ES+MX Vertical](docs/phases/phase-1.md)
- [Phase 2 — Resilience](docs/phases/phase-2.md)
- [AGENTS.md](AGENTS.md) — Development conventions
- [ADRs](docs/adr/) — Architecture Decision Records

## License

See [LICENSE](LICENSE).
