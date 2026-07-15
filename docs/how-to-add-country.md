# How to Add a New Country

Step-by-step recipe for integrating a new country into Debt Stalker.
Each step is self-contained and testable. The backend process is **additive** --
no controller, persistence, or worker changes required. The current LiveView country
selects are still static, so add the country there until those selects are registry-backed.

> **Existing examples:** `Countries.ES` (Spain/DNI), `Countries.MX` (Mexico/CURP), and `Countries.PL` (Poland/PESEL).
> This guide uses **Portugal (PT)** as a hypothetical walkthrough.

---

## Prerequisites

- Elixir 1.18.x / OTP 27.x running (`elixir --version`)
- Postgres up (`make up`)
- Tests green (`make test`)

---

## Step 1: Create the Country Module

Create `lib/debt_stalker/countries/pt.ex` implementing `Countries.Behaviour`:

```elixir
defmodule DebtStalker.Countries.PT do
  @moduledoc """
  Portugal (PT) country module.

  Implements NIF validation and financial threshold checks.
  """
  @behaviour DebtStalker.Countries.Behaviour

  # --- Document validation ---

  @doc "Validates a Portuguese NIF (9 digits with checksum)."
  @impl true
  @spec validate_document(String.t()) :: :ok | {:error, String.t()}
  def validate_document(document) do
    trimmed = String.trim(document)
    # Implement NIF validation rules here
    if String.match?(trimmed, ~r/^\d{9}$/) do
      :ok
    else
      {:error, "invalid NIF format: must be exactly 9 digits"}
    end
  end

  # --- Financial thresholds ---

  @doc "Checks financial thresholds for Portugal."
  @impl true
  @spec validate_financials(map()) :: %{
          additional_review_required: boolean(),
          reasons: [String.t()]
        }
  def validate_financials(%{requested_amount: amount, monthly_income: income}) do
    reasons = []
    # Add country-specific threshold checks
    reasons =
      if Decimal.gt?(amount, Decimal.mult(income, 10)),
        do: ["income_ratio_exceeded" | reasons],
        else: reasons

    %{additional_review_required: reasons != [], reasons: reasons}
  end

  # --- Provider summary ---

  @doc "Interprets a normalized provider summary for Portuguese risk evaluation."
  @impl true
  @spec interpret_provider_summary(map()) :: map()
  def interpret_provider_summary(summary), do: summary

  # --- Additional review ---

  @doc "Returns whether additional review is required."
  @impl true
  @spec additional_review_required?(map()) :: boolean()
  def additional_review_required?(params) do
    %{additional_review_required: required} = validate_financials(params)
    required
  end

  # --- Status transitions ---

  @doc "Returns the allowed status transitions for Portugal."
  @impl true
  @spec allowed_status_transitions() :: %{String.t() => [String.t()]}
  def allowed_status_transitions do
    %{
      "submitted" => ["pending_risk", "provider_error", "cancelled"],
      "pending_risk" => ["additional_review", "approved", "rejected", "cancelled"],
      "additional_review" => ["approved", "rejected"],
      "provider_error" => ["pending_risk", "rejected"]
    }
  end

  # --- Risk score ---

  @doc "Returns whether the provider summary indicates an acceptable risk score."
  @impl true
  @spec acceptable_risk_score?(map() | nil) :: boolean()
  def acceptable_risk_score?(%{"risk_indicators" => %{"credit_score" => score}})
      when is_integer(score) do
    score >= 620
  end

  def acceptable_risk_score?(_), do: false

  # --- Optional callbacks ---

  @doc "Returns a short document hint for Portuguese forms."
  @impl true
  @spec document_hint() :: String.t()
  def document_hint, do: "123456789 (NIF)"
end
```

### Required Behaviour Callbacks

| Callback | Purpose | Example (ES) |
| --- | --- | --- |
|----------|---------|-------------|
| `validate_document/1` | Document format + checksum | DNI: 8 digits + letter |
| `validate_financials/1` | Financial threshold flags | Amount > 15000, income ratio |
| `interpret_provider_summary/1` | Normalize provider data | Pass-through |
| `additional_review_required?/1` | Review decision | Delegates to `validate_financials` |
| `allowed_status_transitions/0` | Status machine narrowing | Shared set (can restrict) |

### Optional Callbacks

| Callback | Purpose |
| --- | --- |
|----------|---------|
| `acceptable_risk_score?/1` | Provider score check; missing callback routes to `additional_review` fail-safe |
| `document_hint/0` | UI placeholder for document input |

---

## Step 2: Create the Provider Adapter

Create `lib/debt_stalker/providers/pt_adapter.ex` implementing `Providers.Behaviour`:

```elixir
defmodule DebtStalker.Providers.PTAdapter do
  @moduledoc """
  Simulated provider adapter for Portugal (PT).

  Returns deterministic normalized data based on document input.
  No raw payloads are stored or returned.
  """
  @behaviour DebtStalker.Providers.Behaviour

  alias DebtStalker.Providers.ProviderSummary

  @doc "Fetches and normalizes simulated provider data for Portugal."
  @impl true
  @spec fetch(String.t(), map()) :: {:ok, ProviderSummary.t()} | {:error, atom()}
  def fetch("PT", %{identity_document: document} = _params) do
    case simulate_provider_response(document) do
      {:ok, raw} -> {:ok, normalize(raw)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp simulate_provider_response(document) do
    cond do
      String.starts_with?(document, "000000000") ->
        {:error, :unavailable}

      String.starts_with?(document, "999999999") ->
        {:error, :timeout}

      true ->
        {:ok,
         %{
           credit_score: 620 + rem(:erlang.phash2(document), 180),
           active_loans: rem(:erlang.phash2(document, 42), 4),
           bank_name: "Banco Simulado PT",
           monthly_payment: Decimal.new("#{150 + rem(:erlang.phash2(document, 7), 600)}")
         }}
    end
  end

  defp normalize(raw) do
    ProviderSummary.new(%{
      provider_status: "active",
      risk_indicators: %{
        "credit_score" => raw.credit_score,
        "active_loans" => raw.active_loans
      },
      normalized_data: %{
        "bank_name" => raw.bank_name,
        "monthly_payment" => Decimal.to_string(raw.monthly_payment)
      }
    })
  end
end
```

**Key rules:**
- The first argument to `fetch/2` MUST match your country code (`"PT"`).
- Always return `{:ok, ProviderSummary.t()}` or `{:error, atom()}`.
- Never persist or expose raw provider payloads.
- Use `ProviderSummary.new/1` for normalization.

---

## Step 3: Register in Both Registries

### Country Registry

Edit `lib/debt_stalker/countries/registry.ex`, add to `default_countries/0`:

```elixir
defp default_countries do
  [
    {"ES", DebtStalker.Countries.ES},
    {"MX", DebtStalker.Countries.MX},
    {"PT", DebtStalker.Countries.PT}    # <-- add
  ]
end
```

### Provider Registry

Edit `lib/debt_stalker/providers/registry.ex`, add to `default_providers/0`:

```elixir
defp default_providers do
  [
    {"ES", DebtStalker.Providers.ESAdapter},
    {"MX", DebtStalker.Providers.MXAdapter},
    {"PT", DebtStalker.Providers.PTAdapter}    # <-- add
  ]
end
```

Both registries use ETS for O(1) lookups. No config files or env vars needed --
just add the tuple to the list.

---

## Step 4: Add Seed Data (Optional)

Add sample applications to `priv/repo/seeds.exs`:

```elixir
pt_applications = [
  %{
    country: "PT",
    full_name: "Joao Silva Santos",
    identity_document: "123456789",
    requested_amount: Decimal.new("8000"),
    monthly_income: Decimal.new("1800")
  }
]

for attrs <- pt_applications do
  case Applications.create_application(attrs) do
    {:ok, app} ->
      IO.puts("  Created PT app: #{app.id} (#{app.full_name})")
    {:error, changeset} ->
      IO.puts("  Failed: #{inspect(changeset.errors)}")
  end
end
```

---

## Step 5: Write Tests

### Country Module Tests

Create `test/debt_stalker/countries/pt_test.exs`:

```elixir
defmodule DebtStalker.Countries.PTTest do
  use ExUnit.Case, async: true

  alias DebtStalker.Countries.PT

  describe "validate_document/1" do
    test "accepts valid NIF" do
      assert :ok = PT.validate_document("123456789")
    end

    test "rejects NIF with wrong length" do
      assert {:error, _} = PT.validate_document("12345678")
    end

    test "rejects NIF with letters" do
      assert {:error, _} = PT.validate_document("12345678A")
    end
  end

  describe "validate_financials/1" do
    test "no review when under thresholds" do
      params = %{
        requested_amount: Decimal.new("5000"),
        monthly_income: Decimal.new("2000")
      }

      assert %{additional_review_required: false, reasons: []} =
               PT.validate_financials(params)
    end

    test "flags income ratio exceeded" do
      params = %{
        requested_amount: Decimal.new("50000"),
        monthly_income: Decimal.new("2000")
      }

      result = PT.validate_financials(params)
      assert result.additional_review_required
      assert "income_ratio_exceeded" in result.reasons
    end
  end

  describe "acceptable_risk_score?/1" do
    test "returns true when score meets threshold" do
      assert PT.acceptable_risk_score?(%{
               "risk_indicators" => %{"credit_score" => 700}
             })
    end

    test "returns false when score below threshold" do
      refute PT.acceptable_risk_score?(%{
               "risk_indicators" => %{"credit_score" => 500}
             })
    end

    test "returns false when no score present" do
      refute PT.acceptable_risk_score?(nil)
    end
  end

  describe "allowed_status_transitions/0" do
    test "returns valid transition map" do
      transitions = PT.allowed_status_transitions()
      assert is_map(transitions)
      assert Map.has_key?(transitions, "submitted")
      assert "pending_risk" in transitions["submitted"]
    end
  end
end
```

### Provider Adapter Tests

Create `test/debt_stalker/providers/pt_adapter_test.exs`:

```elixir
defmodule DebtStalker.Providers.PTAdapterTest do
  use ExUnit.Case, async: true

  alias DebtStalker.Providers.PTAdapter

  describe "fetch/2" do
    test "returns normalized summary for valid document" do
      assert {:ok, summary} =
               PTAdapter.fetch("PT", %{identity_document: "123456789"})

      assert summary.provider_status == "active"
      assert is_integer(summary.risk_indicators["credit_score"])
    end

    test "returns :unavailable for error document" do
      assert {:error, :unavailable} =
               PTAdapter.fetch("PT", %{identity_document: "000000000"})
    end

    test "returns :timeout for timeout document" do
      assert {:error, :timeout} =
               PTAdapter.fetch("PT", %{identity_document: "999999999"})
    end
  end
end
```

---

## Step 6: Run Quality Suite

```bash
# Format
mix format

# Compile (no warnings)
mix compile --warnings-as-errors

# Lint (strict mode -- custom checks will validate your code)
mix credo --strict

# Dialyzer (type checking)
mix dialyzer

# Tests
mix test
```

The standard quality suite verifies formatting, compilation, Credo, Dialyzer, and tests.
If the custom architecture Credo checks from issue #78 are present, they additionally verify:
- **NoCountryBranching**: Your new country code won't appear in branching outside `Countries`/`Providers`
- **RequireSpec**: All public functions have `@spec`
- **NoIOInspect**: No debug `IO.inspect` calls

---

## Step 7: Verify End-to-End

```bash
# Start the server
make run

# Create an application for the new country
TOKEN=$(curl -s -X POST http://localhost:4000/api/auth/token \
  -H 'Content-Type: application/json' \
  -d '{"role":"update"}' | jq -r .token)

curl -X POST http://localhost:4000/api/applications \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{
    "country": "PT",
    "full_name": "Joao Silva",
    "identity_document": "123456789",
    "requested_amount": "8000",
    "monthly_income": "1800"
  }'
```

Expected: `201` with the created application, status `"submitted"`, and
`identity_document` redacted to `"****6789"`.

---

## Checklist

Use this checklist to verify completeness:

- [ ] `lib/debt_stalker/countries/XX.ex` implements all `Countries.Behaviour` callbacks
- [ ] `lib/debt_stalker/providers/xx_adapter.ex` implements `Providers.Behaviour.fetch/2`
- [ ] `Countries.Registry.default_countries/0` includes `{"XX", Countries.XX}`
- [ ] `Providers.Registry.default_providers/0` includes `{"XX", Providers.XXAdapter}`
- [ ] `test/debt_stalker/countries/xx_test.exs` covers document validation, financials, status transitions, and optional risk score handling
- [ ] `test/debt_stalker/providers/xx_adapter_test.exs` covers fetch success + errors
- [ ] `mix format --check-formatted` passes
- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix credo --strict` passes (no country branching violations)
- [ ] `mix dialyzer` passes
- [ ] `mix test` passes (all existing + new tests green)
- [ ] Seed data added to `priv/repo/seeds.exs` (optional)
- [ ] API test: create application with new country returns 201

---

## What You Do NOT Need to Change

The backend architecture is designed so adding a country is mostly additive:

| Layer | Changes needed? |
| --- | --- |
|-------|----------------|
| Database schema / migrations | No |
| API controllers | No |
| LiveView UI | Yes, for current static ES/MX dropdown options; no domain logic changes |
| Oban workers | No |
| Status machine | No (country module narrows shared set) |
| Audit trail | No |
| PII encryption | No |
| Pagination / queries | No |

---

## Hypothetical Examples

For reference, here is what the other planned countries might look like:

| Country | Document | Key Financial Rule | Risk Score Field |
| --- | --- | --- | --- |
|---------|----------|--------------------|-----------------|
| PT (Portugal) | NIF (9 digits) | Income ratio (10x) | `credit_score` |
| IT (Italy) | Codice Fiscale (16 chars) | Debt-to-income | `credit_score` |
| CO (Colombia) | CC (6-10 digits) | Income ratio + amount cap | `score_crediticio` |
| BR (Brazil) | CPF (11 digits + checksum) | Income ratio + debt ratio | `score_serasa` |
