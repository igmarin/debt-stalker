defmodule DebtStalker.Providers.COAdapter do
  @moduledoc """
  Simulated provider adapter for Colombia (CO).

  Returns deterministic normalized data based on document input,
  simulating a Datacredito bureau query.

  No raw payloads are stored or returned.
  """
  @behaviour DebtStalker.Providers.Behaviour

  alias DebtStalker.Providers.ProviderSummary

  @doc "Fetches and normalizes simulated provider data for Colombia."
  @impl true
  @spec fetch(String.t(), map()) :: {:ok, ProviderSummary.t()} | {:error, atom()}
  def fetch("CO", %{identity_document: document} = _params) do
    case simulate_provider_response(document) do
      {:ok, raw} -> {:ok, normalize(raw)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp simulate_provider_response(document) do
    cond do
      String.starts_with?(document, "00000000") ->
        {:error, :unavailable}

      String.starts_with?(document, "99999999") ->
        {:error, :timeout}

      true ->
        {:ok,
         %{
           datacredito_score: 580 + rem(:erlang.phash2(document), 200),
           existing_debt: simulated_existing_debt(document),
           active_loans: rem(:erlang.phash2(document, 42), 5),
           institution: "Datacredito CO",
           payment_history:
             if(rem(:erlang.phash2(document, 3), 2) == 0, do: "good", else: "mixed")
         }}
    end
  end

  @spec simulated_existing_debt(String.t()) :: Decimal.t()
  defp simulated_existing_debt(document) do
    overrides = Application.get_env(:debt_stalker, :co_simulated_debt_overrides, %{})

    case Map.get(overrides, document) do
      amount when is_integer(amount) -> Decimal.new(amount)
      _ -> Decimal.new("#{rem(:erlang.phash2(document, 99), 50_000)}")
    end
  end

  defp normalize(raw) do
    ProviderSummary.new(%{
      provider_status: "active",
      risk_indicators: %{
        "datacredito_score" => raw.datacredito_score,
        "existing_debt" => Decimal.to_string(raw.existing_debt),
        "active_loans" => raw.active_loans,
        "payment_history" => raw.payment_history
      },
      normalized_data: %{
        "institution" => raw.institution
      }
    })
  end
end
