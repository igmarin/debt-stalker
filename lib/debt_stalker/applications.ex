defmodule DebtStalker.Applications do
  @moduledoc """
  Context for credit application operations.

  Provides create, get, list, and status update functions with:
  - Country-specific validation (document + financials)
  - Provider enrichment (simulated)
  - PII encryption at rest (Cloak)
  - Document redaction in responses
  """

  alias DebtStalker.Applications.CreditApplication
  alias DebtStalker.Countries.Registry
  alias DebtStalker.Providers.ProviderSummary
  alias DebtStalker.Repo

  @provider_adapters %{
    "ES" => DebtStalker.Providers.ESAdapter,
    "MX" => DebtStalker.Providers.MXAdapter
  }

  @spec create_application(map()) :: {:ok, CreditApplication.t()} | {:error, Ecto.Changeset.t() | atom()}
  def create_application(attrs) do
    with {:ok, country_module} <- resolve_country(attrs),
         :ok <- validate_document(country_module, attrs),
         {:ok, financials} <- evaluate_financials(country_module, attrs),
         {:ok, provider_summary} <- fetch_provider(attrs) do
      insert_attrs =
        attrs
        |> Map.put(:status, "submitted")
        |> Map.put(:additional_review_required, financials.additional_review_required)
        |> Map.put(:provider_summary, ProviderSummary.to_map(provider_summary))

      %CreditApplication{}
      |> CreditApplication.changeset(insert_attrs)
      |> Repo.insert()
    else
      {:error, :unsupported_country} ->
        changeset =
          %CreditApplication{}
          |> CreditApplication.changeset(attrs)
          |> Ecto.Changeset.add_error(:country, "is not supported")

        {:error, changeset}

      {:error, :invalid_document, message} ->
        changeset =
          %CreditApplication{}
          |> CreditApplication.changeset(attrs)
          |> Ecto.Changeset.add_error(:identity_document, message)

        {:error, changeset}

      {:error, :provider_error} ->
        insert_attrs =
          attrs
          |> Map.put(:status, "provider_error")
          |> Map.put(:additional_review_required, false)

        %CreditApplication{}
        |> CreditApplication.changeset(insert_attrs)
        |> Repo.insert()

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # Private

  defp resolve_country(%{country: country}) do
    Registry.lookup(country)
  end

  defp resolve_country(_attrs), do: {:error, :unsupported_country}

  defp validate_document(country_module, %{identity_document: document}) do
    case country_module.validate_document(document) do
      :ok -> :ok
      {:error, message} -> {:error, :invalid_document, message}
    end
  end

  defp validate_document(_country_module, _attrs), do: :ok

  defp evaluate_financials(country_module, attrs) do
    financials = country_module.validate_financials(attrs)
    {:ok, financials}
  end

  defp fetch_provider(%{country: country, identity_document: document}) do
    adapter = Map.fetch!(@provider_adapters, country)

    case adapter.fetch(country, %{identity_document: document}) do
      {:ok, summary} -> {:ok, summary}
      {:error, _reason} -> {:error, :provider_error}
    end
  end
end
