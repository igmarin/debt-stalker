# ADR 0003 — Country Behaviour Pattern for Multi-Country Rules

## Status

Accepted

## Context

The system must support country-specific validation rules (document formats, financial thresholds) that vary significantly between countries. As more countries are added (PT, IT, CO, BR), the approach must scale without if/else chains.

Options considered:
- **Protocol-based dispatch**: Elixir protocols on a Country struct — elegant but requires instantiating a struct for each call.
- **Behaviour modules + ETS registry**: Each country implements a behaviour; an ETS-backed registry maps country codes to modules. O(1) lookup, compile-time contract enforcement.
- **Configuration-driven rules**: Store rules in config/DB — flexible but loses compile-time safety and makes testing harder.

## Decision

Use a **Behaviour** (`DebtStalker.Countries.Behaviour`) with an **ETS-backed GenServer registry** (`DebtStalker.Countries.Registry`). Each country is a module implementing the behaviour (e.g., `DebtStalker.Countries.ES`).

## Consequences

**Positive:**
- Compile-time enforcement of required callbacks
- O(1) dispatch via ETS lookup
- New countries added by creating a module + registering it
- Easy to test each country in isolation
- No branching outside the Countries context (per Code Organization Contract)

**Negative:**
- One more GenServer in the supervision tree
- Adding a country requires code deployment (not runtime config)

**Mitigations:**
- Registry starts before any code that needs country lookup
- Default countries loaded at boot; hot-reloading possible for dev
