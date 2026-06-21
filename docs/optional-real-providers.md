# Optional Real Providers & Document Validation Services

**Status:** Reference document (future decision input)  
**Created:** 2026-06-21  
**Related:** `docs/requirements.md`, `docs/master-plan.md`, Phase 1/2 implementation (simulated providers + local validation)

## Purpose

This document collects researched options for **real** (non-simulated) services that could be used for:

- CURP validation / enrichment (Mexico)
- DNI validation / enrichment (Spain)
- Real banking / credit data providers (instead of or in addition to simulated adapters)

**Important context:**
- The current implementation (Phase 1 + active Phase 2) deliberately uses **local document validation** + **fully simulated provider adapters**.
- This choice is documented in the master plan (Decision D11) and satisfies all reproducibility, testing, and "< 5 minute setup" requirements.
- **No current or Phase 2 code is being changed.** This document is forward-looking reference material.

Real services should only be considered **after current phases complete**, via a future review gate (possible new "optional providers" enhancement track).

## 1. CURP Validation (Mexico)

### Official / Free (manual)
- **gob.mx CURP portal**: https://www.gob.mx/curp/  
  Free web lookup by CURP or personal details. Excellent for manual verification. Not designed as an automation API.

### Commercial / Low-cost APIs (talk to RENAPO)
All of these connect to the official Mexican government registry (RENAPO) and return structured identity data.

| Service | Free Tier / Cost | Notes | Link |
|---------|------------------|-------|------|
| Didit | 500 free verifications / month; $0.20 per conclusive after | Sandbox available, SDKs | https://business.didit.me |
| Argos Identity CURP Verifier | Pay-per-use | Direct RENAPO integration | https://developers.argosidentity.com/en/verify/curp_verifier/overview |
| Veriff CURP Database Verification | Configured integration | API + web/native SDKs | https://devdocs.veriff.com/docs/curp-database-verification |
| Verifik | Pay-per-use | Returns name, DOB, nationality etc. | https://docs.verifik.co/identity/mexico |
| Tlaloc.sh | ~0.25 MXN per lookup (prepaid, no monthly fees) | Very low cost, direct RENAPO | https://www.tlaloc.sh/en/services/curp.html |
| MetaMap GovChecks | Pay-per-use | RENAPO match | https://docs.metamap.com/reference/govchecks-mexico-curp |
| Trinsic | Part of identity network | Enrichment focused | https://docs.trinsic.id/docs/mexico-curp |

### Local / Offline Validation
- The 18-character structure can be validated without any external call (4 letters + 6 digits + ...).
- Check digit + date/state/word blacklist logic exists in open source (e.g. Node `validate-curp`).
- Current implementation performs basic format validation only (documented simplification).

**Future consideration:** Local format+checksum + optional paid lookup for full name/DOB confirmation.

## 2. DNI Validation (Spain)

### Local Validation (Current Implementation)
The current `DebtStalker.Countries.ES` module implements the official mod-23 checksum algorithm using the exact public string:

```
TRWAGMYFPDXBNJZSQVHLCKE
```

This is the standard and complete format + checksum check for Spanish DNI (8 digits + control letter). It is fast, deterministic, requires no external calls or secrets, and works perfectly for the "document verifications" requirement in `requirements.md`.

### External / Real-name Verification
- No widely available **free public government API** for "does this DNI exist and belong to this name" (data protection reasons).
- Government reference calculators exist (e.g. interior.gob.es), but they are not bulk/automated services.
- Paid options exist in the KYC/identity verification space (Veridas, eIDAS-based providers, OCR services for the physical DNI card).

**Conclusion for current scope:** The local implementation is sufficient and correct. Stronger real-name binding would be a future KYC integration decision.

## 3. Bank / Credit Data Test Sandboxes (Providers)

All "free" options are **developer sandboxes** with dummy data. They require (free) registration and are the standard way to test real provider integrations without using production data.

### Recommended Starting Points

| Provider / Aggregator | Relevant Countries | Sandbox Notes | Link |
|-----------------------|--------------------|---------------|------|
| **BBVA API Market** | ES (strong), MX | Excellent PSD2/open-banking sandbox. Account information, etc. Free dev access after signup. | https://www.bbvaapimarket.com |
| **Santander** | ES, MX (and others) | Developer portals + sandboxes. MX via apimarket.santander.com.mx. ES via Redsys/PSD2. Registration required. | https://apimarket.santander.com.mx<br>https://www.openbankingtracker.com/provider/banco-santander-es |
| **Belvo** | MX, CO, BR (and more) | Leading LatAm open finance aggregator. Free developer sandbox with named dummy institutions (`planet_mx_retail`, fiscal data, etc.). Banking + employment + fiscal. | https://developers.belvo.com (sandbox docs) |
| Enable Banking (aggregator) | ES + other EU | Can proxy multiple PSD2 bank sandboxes (including BBVA). | https://enablebanking.com |

### Other Mentions
- Many individual EU banks publish PSD2 sandboxes (CaixaBank, ING, Deutsche Bank, etc.).
- No anonymous, unlimited, zero-friction real bank data APIs exist (privacy + regulatory reasons).

**"Free test bank" recommendation:** Start with **BBVA** (ES/MX) and **Belvo** (MX and future LatAm countries). Santander is a natural brand-aligned option.

Current simulated adapters already produce the fields the risk rules need (`credit_score`/`buro_score`, `existing_debt`, active loans, payment history). Any real adapter would simply map sandbox responses into the same `ProviderSummary` shape.

## 4. SantanderAI and Other Alternatives

**SantanderAI** (https://github.com/SantanderAI)

Banco Santander's official open-source AI organization (Apache-2.0).

Focus areas (as of 2026):
- Responsible AI, MLOps, graph ML
- LLM guardrails and evaluation
- Synthetic data generation (e.g. `gen-fraud-graph` for 100M+ accounts)
- Causal perception / fairness in credit decisions
- Bayesian networks for tabular data
- Stressed datasets and robustness benchmarks

**Relevance:** Not useful for DNI/CURP format validation or raw banking data fetching. **Very relevant** for future risk, fraud, or fairness features in later phases.

### General Alternatives
- Use an **aggregator** (Belvo, etc.) rather than writing one adapter per bank.
- Local validation libraries (where they exist) + optional paid enrichment.
- For Elixir: just use `Req` + structured error handling when calling real services.

## 5. Integration Considerations (if we ever adopt)

- Must implement the exact `DebtStalker.Providers.Behaviour` (or a parallel validation behaviour).
- Raw provider payloads **must never** be persisted or returned (current contract).
- Real calls must be wrapped in the resilience patterns planned for Phase 2 (circuit breaker, retry budget, telemetry).
- Secrets (API keys) only via env / k8s secrets — never committed.
- Tests: simulated remains the default. Real/sandbox adapters exercised only with explicit opt-in (`LIVE_PROVIDERS=true` or equivalent) + recorded responses or sandbox accounts.
- PII flow: any external lookup must be justified, logged (redacted), and compliant with each country's rules.

## 6. Decision Criteria — "When Would It Be Worthy?"

Consider real services only when **multiple** of the following are true:

- Regulatory or compliance requirement for external verification/enrichment.
- Business decision that simulated data is no longer sufficient for demos, risk models, or audits.
- We have operational capacity for secrets management, monitoring of 3rd-party SLAs, and cost tracking.
- At least one free/low-cost tier still meaningfully reduces manual effort or increases trust in a target country.
- We are ready to maintain the extra test paths and fallback logic.

**Current (2026-06-21) assessment:** None of the above are true yet. The simulated + local approach is working well.

## Sources & Links (as of research date)

- gob.mx CURP: https://www.gob.mx/curp/
- Didit, Argos, Veriff, Verifik, Tlaloc, MetaMap, Trinsic (see tables above)
- BBVA API Market: https://www.bbvaapimarket.com
- Santander developer portals (via openbankingtracker and direct links)
- Belvo sandbox: https://developers.belvo.com
- SantanderAI: https://github.com/SantanderAI
- Various KYC/identity and PSD2/open-banking references from web research

---

**Next action for this document:** Revisit after current Phase 2 (and any subsequent phases) are complete, or when a specific trigger (regulatory, product, or scale) appears. At that point decide whether to turn any of these options into an implementation spike.