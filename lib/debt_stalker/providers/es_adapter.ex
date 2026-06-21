defmodule DebtStalker.Providers.ESAdapter do
  @moduledoc """
  Simulated provider adapter for Spain (ES).

  Returns deterministic normalized data based on document input.
  No raw payloads are stored or returned.
  """
  @behaviour DebtStalker.Providers.Behaviour

  alias DebtStalker.Providers.ProviderSummary

  @doc "Fetches and normalizes simulated provider data for Spain."
  @impl true
  @spec fetch(String.t(), map()) :: {:ok, ProviderSummary.t()} | {:error, atom()}
  def fetch("ES", %{identity_document: document} = _params) do
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
           credit_score: 700 + rem(:erlang.phash2(document), 150),
           active_loans: rem(:erlang.phash2(document, 42), 5),
           bank_name: "Banco Simulado ES",
           monthly_payment: Decimal.new("#{200 + rem(:erlang.phash2(document, 7), 800)}")
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
