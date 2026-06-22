# ADR-0008: Strict Document Validation Hardening for CURP/DNI (DRY/YAGNI + Extensibility)

## Status

Accepted

## Context

Phase 1 delivered basic document validation:
- MX: simple length + loose regex on CURP.
- ES: DNI checksum (mod 23) but no NIE support.

Master Plan explicitly called out "DNI/CURP checksum correctness" as a Medium risk requiring documented rules + property tests.

The `curp-dni` work replaced the loose checks with strict implementations matching the official business rules:
- CURP: full RENAPO regex, position semantics (vowels, gender, 32+NE states, consonants, century differentiator, check digit), realistic date validation, optional `birth_date` cross-check.
- DNI/NIE: proper prefix handling (X=0/Y=1/Z=2), padding for short DNI, mod-23 control.

Validation now lives in pure modules (`Countries.Curp`, `Countries.DniNie`) delegated by the country modules.

We need a decision record because:
- Return type changed from `{:error, String.t()}` to `{:error, atom()}` (structured errors).
- New 2-arity `validate_document/2` for options like `birth_date`.
- Future countries (PT, IT, CO, BR) will need similar rules.
- Must balance hardening with DRY and YAGNI.

## Decision

We adopt **dedicated pure validator modules per country** for document pre-validation:

- `DebtStalker.Countries.Curp` and `DebtStalker.Countries.DniNie` contain all format, structure, checksum, and cross-validation logic.
- Country modules (`MX`, `ES`) delegate and implement the `Behaviour`.
- All country/document logic stays inside the `DebtStalker.Countries` bounded context (enforced by custom Credo check).
- Sanitization (trim + uppercase) is performed at the entry of validators.
- Errors are returned as atoms (`:invalid_length`, `:regex_mismatch`, `:bad_control_digit`, `:invalid_date`, `:birth_date_mismatch`, etc.).
- The public API supports `validate_document(doc)` and `validate_document(doc, opts)` where `opts` can contain `:birth_date`.
- `birth_date` is treated strictly as a **virtual attribute** — never persisted.

This approach:
- Hardens the rules as required.
- Keeps concerns isolated per country for now.
- Allows easy extraction of shared helpers (e.g. mod-23) later if duplication appears.

## Consequences

### Positive
- Strong pre-validation before any provider call (reduces bad data reaching external systems).
- Structured errors improve logging, testing, and UX (better error messages in forms/API).
- Virtual `birth_date` enables accuracy checks without schema changes.
- Follows project invariants: no country branching outside `Countries`, `@spec` + `@doc` on public functions, domain error atoms.
- Sets a clear pattern for adding future countries without refactoring core app layers.

### Negative
- Slight increase in files (two new pure modules).
- Old tests and random generators had to be updated to produce/accept only strictly valid documents.
- The `validate_document/1` string-error contract in `Behaviour` and `how-to-add-country.md` examples became outdated (we updated the type but left examples for now).
- Random generators are now less "free-form" (they must satisfy complex rules).

### Neutral
- We chose **not** to implement the full weighted CURP check-digit algorithm yet (regex + structural checks + date validation suffice per current spec). This can be added later under the same ticket/ADR.
- Shared abstractions (e.g. a `DocumentValidator` behaviour or common checksum module) are deferred until YAGNI is violated when the next country is added.

## References
- GitHub Issue #122 (hardening rules discussion)
- GitHub Issue #123 (phase-2-refinement ticket)
- `lib/debt_stalker/countries/{curp.ex,dni_nie.ex}`
- Master Plan § "DNI/CURP checksum correctness" risk
- AGENTS.md §3 (Code Organization Contract) and TDD policy
