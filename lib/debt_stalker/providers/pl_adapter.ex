defmodule DebtStalker.Providers.PLAdapter do
  @moduledoc """
  Simulated provider adapter for Poland (PL).

  Returns deterministic normalized data based on the PESEL input.
  No raw payloads are stored or returned.
  """
  @behaviour DebtStalker.Providers.Behaviour

  alias DebtStalker.Providers.ProviderSummary

  @doc "Fetches and normalizes simulated provider data for Poland."
  @impl true
  @spec fetch(String.t(), map()) :: {:ok, ProviderSummary.t()} | {:error, atom()}
  def fetch("PL", %{identity_document: document} = _params) do
    case simulate_provider_response(document) do
      {:ok, raw} -> {:ok, normalize(raw)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp simulate_provider_response(document) do
    cond do
      String.starts_with?(document, "000") ->
        {:error, :unavailable}

      String.starts_with?(document, "999") ->
        {:error, :timeout}

      true ->
        {:ok,
         %{
           bik_score: 650 + rem(:erlang.phash2(document), 200),
           existing_debt: Decimal.new("#{rem(:erlang.phash2(document, 99), 80_000)}"),
           active_loans: rem(:erlang.phash2(document, 42), 6),
           bank_name: "Bank Symulowany PL",
           monthly_payment: Decimal.new("#{200 + rem(:erlang.phash2(document, 7), 800)}")
         }}
    end
  end

  defp normalize(raw) do
    ProviderSummary.new(%{
      provider_status: "active",
      risk_indicators: %{
        "bik_score" => raw.bik_score,
        "existing_debt" => Decimal.to_string(raw.existing_debt),
        "active_loans" => raw.active_loans
      },
      normalized_data: %{
        "bank_name" => raw.bank_name,
        "monthly_payment" => Decimal.to_string(raw.monthly_payment)
      }
    })
  end
end
