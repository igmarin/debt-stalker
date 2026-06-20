# ADR-0001: Use Phoenix single-app with Oban + Joken + Credo + Dialyzer stack

## Status

Accepted

## Context

We need to choose a technology stack for the Debt Stalker multi-country credit-application core. The system must handle:
- Multi-country credit applications with country-specific validation rules
- Asynchronous processing via database-triggered events
- Near-real-time frontend updates
- PII protection and JWT authentication
- Scalability to millions of applications

Three independent model analyses (grok, kimi, openAI/v1) were conducted and converged on nearly identical recommendations.

## Decision

We will use:

- **Elixir/Phoenix (single app, not umbrella)** — for concurrency, fault tolerance, and native PubSub
- **PostgreSQL 16** — primary data store with triggers for event generation
- **Oban** — Postgres-backed background job processing (durable, retryable, simple local setup)
- **Joken** — JWT authentication with read/update role separation
- **Cloak Ecto** — PII encryption at rest
- **LiveView** — near-real-time frontend via PubSub (no separate SPA needed)
- **Credo (strict)** — code quality enforcement
- **Dialyxir** — static type checking via success typing
- **ExDoc** — API documentation generation
- **Mox + StreamData** — testing (provider mocking + property-based tests)
- **logger_json** — structured JSON logging

Single-app (not umbrella) because the domain boundaries are enforced through contexts and behaviours, not compile-time project separation.

## Consequences

### Positive

- Three-model consensus provides high confidence in the choice
- Native concurrency (BEAM) handles async processing without external message brokers
- Oban on Postgres keeps infrastructure simple (no Redis/RabbitMQ needed)
- LiveView + PubSub delivers real-time UI with minimal moving parts
- Strong tooling ecosystem (Credo, Dialyzer) enforces code quality at compile time
- Single-app simplifies deployment and local development

### Negative

- Elixir talent pool is smaller than Node.js/Python
- Dialyzer PLT builds are slow (mitigated with CI caching)
- Single-app requires discipline to maintain context boundaries (mitigated with Credo checks)

### Neutral

- The architecture supports migrating to umbrella later if needed
- External SPA could consume the same API if LiveView proves insufficient
