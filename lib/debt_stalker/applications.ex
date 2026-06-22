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

            Phoenix.PubSub.broadcast(
              DebtStalker.PubSub,
              "applications:list",
              {:application_created, app}
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

      {:error, reason} ->
        # Cache unavailable — log and fall back to DB.
        Logger.warning("Cachex error during get_application: #{inspect(reason)}")
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
        # Cache-aside: populate cache after DB read. The TTL (default 60s)
        # bounds staleness if a concurrent update invalidates between the
        # DB read and this Cachex.put. The explicit Cachex.del in
        # update_status/3 handles the normal invalidation path.
        ttl = Application.get_env(:debt_stalker, :app_cache_ttl_ms, :timer.seconds(60))
        Cachex.put(:app_cache, cache_key, app, ttl: ttl)
        {:ok, app}
    end
  end

  @doc """
  Counts applications matching the given filters.

  Supported filters: `:country`, `:status`, `:date_from`, `:date_to`.
  """
  @spec count_applications(map()) :: non_neg_integer()
  def count_applications(filters) do
    filters
    |> normalize_filters()
    |> filtered_query()
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Counts status transitions that ended in `approved` or `rejected` today.

  Applies dashboard filters (`:country`, `:date_from`, `:date_to`) via a join
  to the application. The `:status` filter is ignored because decisions are
  always terminal statuses.
  """
  @spec count_decided_today(map()) :: non_neg_integer()
  def count_decided_today(filters \\ %{}) do
    filters =
      filters
      |> normalize_filters()
      |> Map.delete(:status)

    today = Date.utc_today()
    start_dt = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(today, ~T[23:59:59], "Etc/UTC")

    DebtStalker.Applications.StatusTransition
    |> join(:inner, [t], a in CreditApplication, on: t.application_id == a.id)
    |> where([t], t.to_status in ["approved", "rejected"])
    |> where([t], t.inserted_at >= ^start_dt and t.inserted_at <= ^end_dt)
    |> apply_joined_application_filters(filters)
    |> Repo.aggregate(:count, :id)
  end

  @default_sort_by "application_date"
  @default_sort_dir "desc"

  @doc """
  Lists applications with optional filtering, sorting, and pagination.

  **Cursor mode** (API): pass `:limit` and optional `:cursor`.
  **Page mode** (admin UI): pass `:page` and optional `:per_page`.

  Supported filters: `:country`, `:status`, `:date_from`, `:date_to`.
  Sorting (page mode): `:sort_by`, `:sort_dir` (`asc` | `desc`).

  Returns a map with `:entries` and either cursor or page metadata.
  """
  @spec list_applications(map()) :: %{
          entries: [CreditApplication.t()],
          cursor: String.t() | nil,
          page: pos_integer() | nil,
          per_page: pos_integer() | nil,
          total_count: non_neg_integer() | nil,
          total_pages: non_neg_integer() | nil
        }
  def list_applications(filters) do
    filters = normalize_filters(filters)

    if Map.has_key?(filters, :page) do
      list_applications_by_page(filters)
    else
      list_applications_by_cursor(filters)
    end
  end

  @doc """
  Returns dashboard analytics for the admin overview.

  Includes filtered KPI stats, status/country breakdowns, and a daily timeline.
  """
  @spec dashboard_analytics(map()) :: %{
          stats: map(),
          status_breakdown: [%{status: String.t(), count: non_neg_integer()}],
          by_country: [%{country: String.t(), count: non_neg_integer()}],
          timeline: [%{date: Date.t(), count: non_neg_integer()}]
        }
  def dashboard_analytics(filters) do
    filters = normalize_filters(filters)
    breakdown = status_breakdown(filters)

    %{
      stats: stats_from_breakdown(breakdown, filters),
      status_breakdown: breakdown,
      by_country: applications_by_country(filters),
      timeline: applications_timeline(filters, 7)
    }
  end

  @doc "Returns filtered KPI stats for the admin dashboard."
  @spec dashboard_stats(map()) :: %{
          total: non_neg_integer(),
          pending_risk: non_neg_integer(),
          additional_review: non_neg_integer(),
          provider_errors: non_neg_integer(),
          decided_today: non_neg_integer()
        }
  def dashboard_stats(filters) do
    filters = normalize_filters(filters)
    stats_from_breakdown(status_breakdown(filters), filters)
  end

  # Private — pagination

  defp list_applications_by_cursor(filters) do
    limit = Map.get(filters, :limit, 20)

    query =
      filters
      |> filtered_query()
      |> apply_sort(%{sort_by: @default_sort_by, sort_dir: @default_sort_dir})
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

    %{
      entries: entries,
      cursor: cursor,
      page: nil,
      per_page: nil,
      total_count: nil,
      total_pages: nil
    }
  end

  defp list_applications_by_page(filters) do
    per_page = filters |> Map.get(:per_page, 20) |> clamp_per_page()
    page = filters |> Map.get(:page, 1) |> max(1)

    base_query = filtered_query(filters) |> apply_sort(filters)
    total_count = Repo.aggregate(base_query, :count, :id)
    total_pages = max(div(total_count + per_page - 1, per_page), 1)
    page = min(page, total_pages)
    offset = (page - 1) * per_page

    entries =
      base_query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    %{
      entries: entries,
      cursor: nil,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  # Private — analytics

  defp stats_from_breakdown(breakdown, filters) do
    counts_by_status = Map.new(breakdown, &{&1.status, &1.count})

    %{
      total: Enum.sum(Enum.map(breakdown, & &1.count)),
      pending_risk: Map.get(counts_by_status, "pending_risk", 0),
      additional_review: Map.get(counts_by_status, "additional_review", 0),
      provider_errors: Map.get(counts_by_status, "provider_error", 0),
      decided_today: count_decided_today(filters)
    }
  end

  defp status_breakdown(filters) do
    filters
    |> filtered_query()
    |> group_by([a], a.status)
    |> select([a], %{status: a.status, count: count(a.id)})
    |> order_by([a], desc: count(a.id))
    |> Repo.all()
  end

  defp applications_by_country(filters) do
    filters
    |> filtered_query()
    |> group_by([a], a.country)
    |> select([a], %{country: a.country, count: count(a.id)})
    |> order_by([a], desc: count(a.id))
    |> Repo.all()
  end

  defp applications_timeline(filters, days) when is_integer(days) and days > 0 do
    today = Date.utc_today()
    start_date = Date.add(today, -(days - 1))
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")

    counts =
      filters
      |> filtered_query()
      |> where([a], a.application_date >= ^start_dt)
      |> group_by([a], fragment("?::date", a.application_date))
      |> select([a], {fragment("?::date", a.application_date), count(a.id)})
      |> Repo.all()
      |> Map.new()

    Enum.map(Date.range(start_date, today), fn date ->
      %{date: date, count: Map.get(counts, date, 0)}
    end)
  end

  # Private — query building

  defp filtered_query(filters) do
    CreditApplication
    |> maybe_filter_country(filters)
    |> maybe_filter_status(filters)
    |> maybe_filter_date_range(filters)
  end

  defp apply_joined_application_filters(query, filters) do
    query
    |> maybe_filter_country_joined(filters)
    |> maybe_filter_date_range_joined(filters)
  end

  defp maybe_filter_country_joined(query, %{country: country}) when is_binary(country) do
    where(query, [t, a], a.country == ^country)
  end

  defp maybe_filter_country_joined(query, _filters), do: query

  defp maybe_filter_date_range_joined(query, filters) do
    query =
      case Map.get(filters, :date_from) do
        nil ->
          query

        date_from ->
          from_dt = DateTime.new!(date_from, ~T[00:00:00], "Etc/UTC")
          where(query, [t, a], a.application_date >= ^from_dt)
      end

    case Map.get(filters, :date_to) do
      nil ->
        query

      date_to ->
        to_dt = DateTime.new!(date_to, ~T[23:59:59], "Etc/UTC")
        where(query, [t, a], a.application_date <= ^to_dt)
    end
  end

  defp normalize_filters(filters) when is_map(filters) do
    filters
    |> Map.new(fn {key, value} -> {key, normalize_filter_value(value)} end)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_filter_value(""), do: nil

  defp normalize_filter_value(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp normalize_filter_value(value), do: value

  defp maybe_filter_country(query, %{country: country}) when is_binary(country) do
    where(query, [a], a.country == ^country)
  end

  defp maybe_filter_country(query, _filters), do: query

  defp maybe_filter_status(query, %{status: status}) when is_binary(status) do
    where(query, [a], a.status == ^status)
  end

  defp maybe_filter_status(query, _filters), do: query

  defp apply_sort(query, filters) do
    sort_by = Map.get(filters, :sort_by, @default_sort_by)
    sort_dir = if Map.get(filters, :sort_dir, @default_sort_dir) == "asc", do: :asc, else: :desc
    tie_breaker = if sort_dir == :asc, do: :asc, else: :desc

    case sort_by do
      "full_name" ->
        order_by(query, [a], [{^sort_dir, a.full_name}, {^tie_breaker, a.id}])

      "requested_amount" ->
        order_by(query, [a], [{^sort_dir, a.requested_amount}, {^tie_breaker, a.id}])

      "country" ->
        order_by(query, [a], [{^sort_dir, a.country}, {^tie_breaker, a.id}])

      "status" ->
        order_by(query, [a], [{^sort_dir, a.status}, {^tie_breaker, a.id}])

      "application_date" ->
        order_by(query, [a], [{^sort_dir, a.application_date}, {^tie_breaker, a.id}])

      _ ->
        order_by(query, [a], desc: a.application_date, desc: a.id)
    end
  end

  defp clamp_per_page(value) when is_integer(value), do: value |> max(1) |> min(100)
  defp clamp_per_page(_), do: 20

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

  defp validate_document(country_module, attrs) when is_map(attrs) do
    document = Map.get(attrs, :identity_document) || Map.get(attrs, "identity_document")

    if is_nil(document) or String.trim(to_string(document)) == "" do
      {:error, :invalid_document, "is required"}
    else
      birth_date = parse_optional_birth_date(attrs)

      case country_module.validate_document(document, birth_date: birth_date) do
        :ok ->
          :ok

        {:error, reason} when is_atom(reason) ->
          {:error, :invalid_document, error_message_for(reason)}
      end
    end
  end

  defp parse_optional_birth_date(%{birth_date: %Date{} = d}), do: d
  defp parse_optional_birth_date(%{"birth_date" => val}), do: parse_date_value(val)
  defp parse_optional_birth_date(_), do: nil

  defp parse_date_value(%Date{} = d), do: d

  defp parse_date_value(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp parse_date_value(_), do: nil

  defp error_message_for(:invalid_length), do: "has invalid length for the document type"
  defp error_message_for(:regex_mismatch), do: "has invalid format"
  defp error_message_for(:invalid_date), do: "contains an invalid date of birth"
  defp error_message_for(:invalid_gender), do: "has invalid gender code"
  defp error_message_for(:invalid_state_code), do: "has invalid state code"
  defp error_message_for(:invalid_century_code), do: "has invalid century code"
  defp error_message_for(:bad_control_digit), do: "has invalid control/check digit"
  defp error_message_for(:birth_date_mismatch), do: "does not match the provided birth date"
  defp error_message_for(_), do: "is invalid"

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
