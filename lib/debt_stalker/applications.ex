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

  @global_transitions %{
    "submitted" => ["pending_risk", "provider_error", "cancelled"],
    "pending_risk" => ["additional_review", "approved", "rejected", "cancelled"],
    "additional_review" => ["approved", "rejected"],
    "provider_error" => ["pending_risk", "rejected"]
  }

  @spec update_status(String.t(), String.t(), String.t()) ::
          {:ok, CreditApplication.t()} | {:error, :not_found | :invalid_transition}
  def update_status(id, new_status, triggered_by) do
    case Repo.get(CreditApplication, id) do
      nil ->
        {:error, :not_found}

      app ->
        allowed = Map.get(@global_transitions, app.status, [])

        if new_status in allowed do
          perform_status_update(app, new_status, triggered_by)
        else
          {:error, :invalid_transition}
        end
    end
  end

  defp perform_status_update(app, new_status, triggered_by) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:application, Ecto.Changeset.change(app, status: new_status))
    |> Ecto.Multi.insert(:transition, fn _changes ->
      %DebtStalker.Applications.StatusTransition{}
      |> Ecto.Changeset.change(%{
        application_id: app.id,
        from_status: app.status,
        to_status: new_status,
        triggered_by: triggered_by
      })
    end)
    |> Ecto.Multi.insert(:audit, fn _changes ->
      %DebtStalker.Applications.AuditLog{}
      |> Ecto.Changeset.change(%{
        application_id: app.id,
        action: "status_changed",
        actor: triggered_by,
        metadata: %{"from" => app.status, "to" => new_status}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{application: updated}} ->
        Phoenix.PubSub.broadcast(
          DebtStalker.PubSub,
          "applications:#{app.id}",
          {:status_changed, %{from: app.status, to: new_status}}
        )

        {:ok, updated}

      {:error, _step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @spec get_application(String.t()) :: {:ok, CreditApplication.t()} | {:error, :not_found}
  def get_application(id) do
    case Repo.get(CreditApplication, id) do
      nil -> {:error, :not_found}
      app -> {:ok, app}
    end
  end

  @spec list_applications(map()) :: %{entries: [CreditApplication.t()], cursor: String.t() | nil}
  def list_applications(filters) do
    import Ecto.Query

    limit = Map.get(filters, :limit, 20)

    query =
      CreditApplication
      |> order_by([a], desc: a.application_date, desc: a.id)
      |> maybe_filter_country(filters)
      |> maybe_filter_status(filters)
      |> maybe_filter_date_range(filters)
      |> maybe_apply_cursor(filters)
      |> limit(^(limit + 1))

    results = Repo.all(query)

    {entries, cursor} =
      if length(results) > limit do
        page_entries = Enum.take(results, limit)
        last = List.last(page_entries)
        {page_entries, encode_cursor(last)}
      else
        {results, nil}
      end

    %{entries: entries, cursor: cursor}
  end

  # Private

  defp maybe_filter_country(query, %{country: country}) do
    import Ecto.Query
    where(query, [a], a.country == ^country)
  end

  defp maybe_filter_country(query, _filters), do: query

  defp maybe_filter_status(query, %{status: status}) do
    import Ecto.Query
    where(query, [a], a.status == ^status)
  end

  defp maybe_filter_status(query, _filters), do: query

  defp maybe_filter_date_range(query, filters) do
    import Ecto.Query

    query =
      case Map.get(filters, :date_from) do
        nil ->
          query

        date_from ->
          from_dt = DateTime.new!(date_from, ~T[00:00:00], "Etc/UTC")
          where(query, [a], a.application_date >= ^from_dt)
      end

    case Map.get(filters, :date_to) do
      nil ->
        query

      date_to ->
        to_dt = DateTime.new!(date_to, ~T[23:59:59], "Etc/UTC")
        where(query, [a], a.application_date <= ^to_dt)
    end
  end

  defp maybe_apply_cursor(query, %{cursor: cursor}) when is_binary(cursor) do
    import Ecto.Query

    case decode_cursor(cursor) do
      {:ok, {date, id}} ->
        where(
          query,
          [a],
          a.application_date < ^date or
            (a.application_date == ^date and a.id < ^id)
        )

      _ ->
        query
    end
  end

  defp maybe_apply_cursor(query, _filters), do: query

  defp encode_cursor(%CreditApplication{} = app) do
    data = %{date: DateTime.to_iso8601(app.application_date), id: app.id}
    Base.url_encode64(Jason.encode!(data))
  end

  defp decode_cursor(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor),
         {:ok, %{"date" => date_str, "id" => id}} <- Jason.decode(json),
         {:ok, date, _offset} <- DateTime.from_iso8601(date_str) do
      {:ok, {date, id}}
    else
      _ -> :error
    end
  end

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
