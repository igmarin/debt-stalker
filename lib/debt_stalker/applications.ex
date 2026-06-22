defmodule DebtStalker.Applications do
  @moduledoc """
  Context for credit application operations.

  Provides create, get, list, and status update functions with:
  - Country-specific validation (document + financials)
  - Provider enrichment (simulated)
  - PII encryption at rest (Cloak)
  - Document redaction in responses
  """

  import Ecto.Query
  require Logger

  alias DebtStalker.Applications.CreditApplication
  alias DebtStalker.Countries.Registry, as: CountryRegistry
  alias DebtStalker.Providers.CircuitBreaker
  alias DebtStalker.Providers.CircuitBreakers
  alias DebtStalker.Providers.ProviderSummary
  alias DebtStalker.Providers.Registry, as: ProviderRegistry
  alias DebtStalker.Repo

  @doc """
  Creates a new credit application.

  Validates the identity document and financials for the requested country,
  fetches a provider summary, and inserts the application. Broadcasts
  `{:application_created, app}` on `applications:list` on success.
  """
  @spec create_application(map()) ::
          {:ok, CreditApplication.t()} | {:error, Ecto.Changeset.t() | atom()}
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

      result =
        %CreditApplication{}
        |> CreditApplication.changeset(insert_attrs)
        |> Repo.insert()

      case result do
        {:ok, app} ->
          Logger.info("Application created",
            application_id: app.id,
            country: app.country,
            status: app.status
          )

          DebtStalker.Telemetry.emit_application_created(app.id, app.country, app.status)

          Phoenix.PubSub.broadcast(
            DebtStalker.PubSub,
            "applications:list",
            {:application_created, app}
          )

          {:ok, app}

        error ->
          error
      end
    else
      {:error, :unsupported_country} ->
        Logger.warning("Application creation failed: unsupported country",
          country: Map.get(attrs, :country)
        )

        changeset =
          %CreditApplication{}
          |> CreditApplication.changeset(attrs)
          |> Ecto.Changeset.add_error(:country, "is not supported")

        {:error, changeset}

      {:error, :invalid_document, message} ->
        Logger.warning("Application creation failed: invalid document",
          country: Map.get(attrs, :country),
          reason: message
        )

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

        Ecto.Multi.new()
        |> Ecto.Multi.insert(
          :application,
          CreditApplication.changeset(%CreditApplication{}, insert_attrs)
        )
        |> Ecto.Multi.insert(:transition, fn %{application: app} ->
          __MODULE__.StatusTransition.changeset(
            %__MODULE__.StatusTransition{},
            %{
              application_id: app.id,
              from_status: "created",
              to_status: "provider_error",
              triggered_by: "provider"
            }
          )
        end)
        |> Ecto.Multi.insert(:audit, fn %{application: app} ->
          __MODULE__.AuditLog.changeset(
            %__MODULE__.AuditLog{},
            %{
              application_id: app.id,
              action: "status_changed",
              actor: "provider",
              metadata: %{"from" => "created", "to" => "provider_error"}
            }
          )
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{application: app}} ->
            Logger.error("Provider error during application creation",
              application_id: app.id,
              country: app.country,
              status: "provider_error"
            )

            {:ok, app}

          # Application insert failed — return its changeset so callers see
          # validation errors on the expected CreditApplication schema.
          {:error, :application, changeset, _changes} ->
            {:error, changeset}

          # Transition or audit insert failed — the application data was
          # valid but the audit trail could not be written. Return a
          # CreditApplication changeset with a system error so callers
          # always get a consistent error type.
          {:error, step, _changeset, %{application: app}} ->
            Logger.error("Provider error audit trail failed",
              application_id: app.id,
              country: app.country,
              step: step
            )

            changeset =
              app
              |> Ecto.Changeset.change()
              |> Ecto.Changeset.add_error(:base, "audit trail write failed")

            {:error, changeset}
        end
    end
  end

  @global_transitions %{
    "submitted" => ["pending_risk", "provider_error", "cancelled"],
    "pending_risk" => ["additional_review", "approved", "rejected", "cancelled"],
    "additional_review" => ["approved", "rejected"],
    "provider_error" => ["pending_risk", "rejected"]
  }

  @doc """
  Transitions an application to `new_status` if the transition is allowed.

  Records the transition and an audit log entry. Returns `:not_found`,
  `:invalid_transition`, or a changeset error on failure.
  """
  @spec update_status(String.t(), String.t(), String.t()) ::
          {:ok, CreditApplication.t()}
          | {:error, :not_found | :invalid_transition | Ecto.Changeset.t()}
  def update_status(id, new_status, triggered_by) do
    case Repo.get(CreditApplication, id) do
      nil ->
        {:error, :not_found}

      app ->
        if transition_allowed?(app, new_status) do
          perform_status_update(app, new_status, triggered_by)
        else
          {:error, :invalid_transition}
        end
    end
  end

  @doc """
  Returns the list of allowed status transitions for the given application.

  Intersects global transitions with country-specific transitions.
  """
  @spec allowed_transitions(CreditApplication.t()) :: [String.t()]
  def allowed_transitions(%CreditApplication{} = app) do
    global_allowed = Map.get(@global_transitions, app.status, [])

    country_allowed =
      case CountryRegistry.lookup(app.country) do
        {:ok, country_module} ->
          Map.get(country_module.allowed_status_transitions(), app.status, [])

        {:error, _} ->
          global_allowed
      end

    global_allowed -- (global_allowed -- country_allowed)
  end

  defp transition_allowed?(app, new_status) do
    global_allowed = Map.get(@global_transitions, app.status, [])

    country_allowed =
      case CountryRegistry.lookup(app.country) do
        {:ok, country_module} ->
          Map.get(country_module.allowed_status_transitions(), app.status, [])

        {:error, _} ->
          global_allowed
      end

    new_status in global_allowed and new_status in country_allowed
  end

  defp perform_status_update(app, new_status, triggered_by) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:application, Ecto.Changeset.change(app, status: new_status))
    |> Ecto.Multi.insert(:transition, fn _changes ->
      __MODULE__.StatusTransition.changeset(
        %__MODULE__.StatusTransition{},
        %{
          application_id: app.id,
          from_status: app.status,
          to_status: new_status,
          triggered_by: triggered_by
        }
      )
    end)
    |> Ecto.Multi.insert(:audit, fn _changes ->
      __MODULE__.AuditLog.changeset(
        %__MODULE__.AuditLog{},
        %{
          application_id: app.id,
          action: "status_changed",
          actor: triggered_by,
          metadata: %{"from" => app.status, "to" => new_status}
        }
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{application: updated}} ->
        Logger.info("Status transition completed",
          application_id: app.id,
          country: app.country,
          status: new_status,
          from_status: app.status
        )

        DebtStalker.Telemetry.emit_status_transition(
          app.id,
          app.country,
          app.status,
          new_status,
          triggered_by
        )

        Phoenix.PubSub.broadcast(
          DebtStalker.PubSub,
          "applications:#{app.id}",
          {:status_changed, %{from: app.status, to: new_status, application_id: app.id}}
        )

        Phoenix.PubSub.broadcast(
          DebtStalker.PubSub,
          "applications:list",
          {:status_changed, %{from: app.status, to: new_status, application_id: app.id}}
        )

        # Invalidate the cached application detail
        Cachex.del(:app_cache, "app:#{app.id}")

        {:ok, updated}

      {:error, _step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc "Fetches a single application by id (cache-backed)."
  @spec get_application(String.t()) :: {:ok, CreditApplication.t()} | {:error, :not_found}
  def get_application(id) do
    with {:ok, _} <- Ecto.UUID.cast(id),
         {:ok, app} <- fetch_from_cache(id) do
      {:ok, app}
    else
      :error -> {:error, :not_found}
      {:miss, id} -> fetch_from_db(id)
    end
  end

  @spec fetch_from_cache(String.t()) :: {:ok, CreditApplication.t()} | {:miss, String.t()}
  defp fetch_from_cache(id) do
    cache_key = "app:#{id}"

    case Cachex.get(:app_cache, cache_key) do
      {:ok, nil} ->
        emit_cache_miss(cache_key)
        {:miss, id}

      {:ok, app} ->
        emit_cache_hit(cache_key)
        {:ok, app}

      {:error, _reason} ->
        # Cache unavailable — treat as miss and fall back to DB.
        emit_cache_miss(cache_key)
        {:miss, id}
    end
  end

  @spec fetch_from_db(String.t()) :: {:ok, CreditApplication.t()} | {:error, :not_found}
  defp fetch_from_db(id) do
    cache_key = "app:#{id}"

    case Repo.get(CreditApplication, id) do
      nil ->
        {:error, :not_found}

      app ->
        Cachex.put(:app_cache, cache_key, app)
        {:ok, app}
    end
  end

  @doc """
  Lists applications with optional filtering and cursor pagination.

  Supported filters: `:country`, `:status`, `:date_from`, `:date_to`, `:limit`, `:cursor`.
  Returns `%{entries: [...], cursor: nil | binary()}`.
  """
  @spec list_applications(map()) :: %{entries: [CreditApplication.t()], cursor: String.t() | nil}
  def list_applications(filters) do
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
    where(query, [a], a.country == ^country)
  end

  defp maybe_filter_country(query, _filters), do: query

  defp maybe_filter_status(query, %{status: status}) do
    where(query, [a], a.status == ^status)
  end

  defp maybe_filter_status(query, _filters), do: query

  defp maybe_filter_date_range(query, filters) do
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
    CountryRegistry.lookup(country)
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
    amount = Map.get(attrs, :requested_amount)
    income = Map.get(attrs, :monthly_income)

    if is_nil(amount) or is_nil(income) do
      {:ok, %{additional_review_required: false, reasons: []}}
    else
      financials = country_module.validate_financials(attrs)
      {:ok, financials}
    end
  end

  defp fetch_provider(%{country: country, identity_document: document}) do
    with {:ok, adapter} <- ProviderRegistry.lookup(country),
         {:ok, breaker} <- CircuitBreakers.lookup(country) do
      breaker
      |> CircuitBreaker.call(fn -> adapter.fetch(country, %{identity_document: document}) end)
      |> handle_provider_result(country)
    else
      {:error, :unsupported_provider} ->
        DebtStalker.Telemetry.emit_provider_call(country, :error,
          error_reason: :unsupported_provider
        )

        {:error, :provider_error}
    end
  end

  defp handle_provider_result({:ok, summary}, country) do
    DebtStalker.Telemetry.emit_provider_call(country, :success)
    {:ok, summary}
  end

  defp handle_provider_result({:error, reason}, country) do
    DebtStalker.Telemetry.emit_provider_call(country, :error, error_reason: reason)
    {:error, :provider_error}
  end

  @spec emit_cache_hit(String.t()) :: :ok
  defp emit_cache_hit(key) do
    :telemetry.execute(
      [:debt_stalker, :cache, :hit],
      %{count: 1},
      %{key: key}
    )
  end

  @spec emit_cache_miss(String.t()) :: :ok
  defp emit_cache_miss(key) do
    :telemetry.execute(
      [:debt_stalker, :cache, :miss],
      %{count: 1},
      %{key: key}
    )
  end
end
