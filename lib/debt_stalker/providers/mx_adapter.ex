defmodule DebtStalker.Providers.MXAdapter do
  @moduledoc """
  Simulated provider adapter for Mexico (MX).

  Returns deterministic normalized data based on document input.
  No raw payloads are stored or returned.
  """
  @behaviour DebtStalker.Providers.Behaviour

  alias DebtStalker.Providers.ProviderSummary

  @impl true
  @spec fetch(String.t(), map()) :: {:ok, ProviderSummary.t()} | {:error, atom()}
  def fetch("MX", %{identity_document: document} = _params) do
    case simulate_provider_response(document) do
      {:ok, raw} -> {:ok, normalize(raw)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp simulate_provider_response(document) do
    cond do
      String.starts_with?(document, "XXXX") ->
        {:error, :unavailable}

      String.starts_with?(document, "ZZZZ") ->
        {:error, :timeout}

      true ->
        {:ok,
         %{
           buro_score: 600 + rem(:erlang.phash2(document), 200),
           existing_debt: Decimal.new("#{rem(:erlang.phash2(document, 99), 50_000)}"),
           institution: "Bureau de Credito MX",
           payment_history:
             if(rem(:erlang.phash2(document, 3), 2) == 0, do: "good", else: "mixed")
         }}
    end
  end

  defp normalize(raw) do
    ProviderSummary.new(%{
      provider_status: "active",
      risk_indicators: %{
        "buro_score" => raw.buro_score,
        "existing_debt" => Decimal.to_string(raw.existing_debt),
        "payment_history" => raw.payment_history
      },
      normalized_data: %{
        "institution" => raw.institution
      }
    })
  end
end
