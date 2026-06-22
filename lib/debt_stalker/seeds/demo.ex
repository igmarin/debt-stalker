defmodule DebtStalker.Seeds.Demo do
  @moduledoc """
  Demo seed data for development and manual UI testing.

  Builds country-aware application attributes and supports two insertion modes:

  - **`:bulk`** — fast direct inserts with random statuses (good for volume/filters)
  - **`:realistic`** — uses `Applications.create_application/1` and status transitions
    so audit trails and timelines are populated
  - **`:mixed`** — realistic records first, then bulk for the remainder

  ## Examples

      # Default: 100 apps (5 realistic + 95 bulk)
      DebtStalker.Seeds.Demo.run()

      # Dashboard-friendly volume
      DebtStalker.Seeds.Demo.run(count: 50, scenario: :dashboard)

      # Only lifecycled records
      DebtStalker.Seeds.Demo.run(count: 10, mode: :realistic, countries: ["ES", "MX"])

  Environment variables (used by `priv/repo/seeds.exs`):

  - `SEED_COUNT` — total records (default: `100`)
  - `SEED_MODE` — `bulk`, `realistic`, or `mixed` (default: `mixed`)
  - `SEED_REALISTIC_COUNT` — realistic records in mixed mode (default: `5`)
  - `SEED_COUNTRIES` — comma-separated list, e.g. `ES,MX`
  - `SEED_SCENARIO` — `default` or `dashboard`
  """

  alias DebtStalker.Applications
  alias DebtStalker.Applications.CreditApplication
  alias DebtStalker.Countries
  alias DebtStalker.Repo
  alias DebtStalkerWeb.Auth.Token

  @default_count 100
  @default_realistic_count 5
  @default_countries ~w(ES MX)
  @default_scenario :default
  @seed_actor "seed"

  @first_names ~w(
    Juan Maria Carlos Ana Pedro Sofia Luis Lucia Roberto Fernando
    Diego Elena Miguel Isabel Jose Carmen Antonio Laura Francisco Pilar
  )

  @last_names ~w(
    Garcia Rodriguez Martinez Lopez Sanchez Perez Gomez Fernandez Torres Diaz
    Hernandez Ramirez Moreno Alvarez Jimenez Ruiz Vazquez Molina Castro Ortega
  )

  @dashboard_status_weights [
    {"submitted", 10},
    {"pending_risk", 25},
    {"additional_review", 20},
    {"approved", 15},
    {"rejected", 10},
    {"provider_error", 10},
    {"cancelled", 5}
  ]

  @realistic_targets ~w(approved rejected pending_risk additional_review)

  @type mode :: :bulk | :realistic | :mixed
  @type scenario :: :default | :dashboard

  @type option ::
          {:count, pos_integer()}
          | {:countries, [String.t()]}
          | {:mode, mode()}
          | {:realistic_count, pos_integer()}
          | {:scenario, scenario()}
          | {:quiet, boolean()}

  @type result :: %{
          created: non_neg_integer(),
          failed: non_neg_integer(),
          realistic: non_neg_integer(),
          bulk: non_neg_integer()
        }

  @doc "Builds attribute map for a single demo application."
  @spec build_attrs(keyword()) :: map()
  def build_attrs(opts \\ []) do
    countries = Keyword.get(opts, :countries, @default_countries)
    scenario = Keyword.get(opts, :scenario, @default_scenario)
    country = Keyword.get(opts, :country) || pick_country(countries)
    status = pick_status(scenario)

    %{
      country: country,
      full_name: random_name(),
      identity_document: Countries.random_identity_document(country),
      requested_amount: random_decimal(1_000, 100_000),
      monthly_income: random_decimal(1_000, 20_000),
      status: status,
      additional_review_required: additional_review_flag(status),
      application_date: random_application_date(),
      provider_summary: %{}
    }
  end

  @doc """
  Seeds demo applications.

  Returns a summary map with `:created`, `:failed`, `:realistic`, and `:bulk` counts.
  """
  @spec run(keyword()) :: result()
  def run(opts \\ []) do
    count = Keyword.get(opts, :count, @default_count)
    mode = Keyword.get(opts, :mode, :mixed)
    realistic_count = Keyword.get(opts, :realistic_count, @default_realistic_count)
    countries = Keyword.get(opts, :countries, @default_countries)
    scenario = Keyword.get(opts, :scenario, @default_scenario)
    quiet = Keyword.get(opts, :quiet, false)

    IO.puts("\n=== Seeding Demo Data ===\n")

    {realistic_target, bulk_target} = split_targets(count, mode, realistic_count)

    {realistic_created, realistic_failed} =
      seed_realistic(realistic_target, countries, quiet)

    bulk_opts = [countries: countries, scenario: scenario, quiet: quiet]
    {bulk_created, bulk_failed} = seed_bulk(bulk_target, bulk_opts)

    result = %{
      created: realistic_created + bulk_created,
      failed: realistic_failed + bulk_failed,
      realistic: realistic_created,
      bulk: bulk_created
    }

    print_summary(result)
    result
  end

  @doc """
  Creates one application through the real context and walks it to `target_status`.
  """
  @spec create_realistic(keyword()) :: {:ok, CreditApplication.t()} | {:error, term()}
  def create_realistic(opts \\ []) do
    countries = Keyword.get(opts, :countries, @default_countries)
    country = Keyword.get(opts, :country) || pick_country(countries)
    target_status = Keyword.get(opts, :target_status) || pick_realistic_target()

    attrs =
      build_attrs(country: country, scenario: :default)
      |> Map.drop([:status, :additional_review_required, :application_date, :provider_summary])

    with {:ok, app} <- Applications.create_application(attrs) do
      walk_to_status(app, target_status)
    end
  end

  @doc "Builds seed options from environment variables."
  @spec options_from_env() :: keyword()
  def options_from_env do
    []
    |> maybe_put_int_env(:count, "SEED_COUNT")
    |> maybe_put_mode_env()
    |> maybe_put_int_env(:realistic_count, "SEED_REALISTIC_COUNT")
    |> maybe_put_countries_env()
    |> maybe_put_scenario_env()
  end

  @doc "Prints demo credentials for the admin UI and API."
  @spec print_credentials() :: :ok
  def print_credentials do
    {:ok, read_token} = Token.generate_token("read")
    {:ok, update_token} = Token.generate_token("update")

    IO.puts("\n=== Demo Credentials ===\n")
    IO.puts("  Admin UI password: #{Application.fetch_env!(:debt_stalker, :admin_password)}")
    IO.puts("  READ API token:    #{read_token}")
    IO.puts("  UPDATE API token:  #{update_token}")
    IO.puts("")
    IO.puts("  Usage:")
    IO.puts("    curl -H 'Authorization: Bearer <token>' http://localhost:4000/api/applications")
    IO.puts("")
    IO.puts("=== Seeding Complete ===\n")
  end

  # Private — seeding

  defp seed_realistic(0, _countries, _quiet), do: {0, 0}

  defp seed_realistic(count, countries, quiet) do
    Enum.reduce(1..count, {0, 0}, fn index, counts ->
      country = Enum.at(countries, rem(index - 1, length(countries)))
      target_status = pick_realistic_target()

      create_realistic(country: country, target_status: target_status)
      |> tally_realistic(counts, quiet)
    end)
  end

  defp seed_bulk(0, _opts), do: {0, 0}

  defp seed_bulk(count, opts) do
    countries = Keyword.fetch!(opts, :countries)
    scenario = Keyword.get(opts, :scenario, @default_scenario)
    quiet = Keyword.get(opts, :quiet, false)

    Enum.reduce(1..count, {0, 0}, fn _index, counts ->
      build_attrs(countries: countries, scenario: scenario)
      |> insert_bulk()
      |> tally_bulk(counts, quiet)
    end)
  end

  defp tally_realistic({:ok, app}, {created, failed}, quiet) do
    log_created_if(app, :realistic, quiet)
    {created + 1, failed}
  end

  defp tally_realistic({:error, reason}, {created, failed}, quiet) do
    log_failure_if(:realistic, reason, quiet)
    {created, failed + 1}
  end

  defp tally_bulk({:ok, app}, {created, failed}, quiet) do
    log_created_if(app, :bulk, quiet)
    {created + 1, failed}
  end

  defp tally_bulk({:error, changeset}, {created, failed}, quiet) do
    log_failure_if(:bulk, changeset.errors, quiet)
    {created, failed + 1}
  end

  defp log_created_if(_app, _mode, true), do: :ok
  defp log_created_if(app, mode, false), do: log_created(app, mode)

  defp log_failure_if(_mode, reason, true), do: reason
  defp log_failure_if(mode, reason, false), do: IO.puts("  FAILED (#{mode}): #{inspect(reason)}")

  defp insert_bulk(attrs) do
    %CreditApplication{}
    |> CreditApplication.changeset(attrs)
    |> Repo.insert()
  end

  defp walk_to_status(%CreditApplication{status: status} = app, target_status)
       when status == target_status,
       do: {:ok, app}

  defp walk_to_status(app, target_status) do
    case next_status_step(app.status, target_status) do
      nil ->
        {:ok, app}

      next_status ->
        case Applications.update_status(app.id, next_status, @seed_actor) do
          {:ok, updated} -> walk_to_status(updated, target_status)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp next_status_step(current, target) do
    path = status_path(target)

    case Enum.find_index(path, &(&1 == current)) do
      nil -> nil
      index -> Enum.at(path, index + 1)
    end
  end

  defp status_path("pending_risk"), do: ["submitted", "pending_risk"]
  defp status_path("additional_review"), do: ["submitted", "pending_risk", "additional_review"]
  defp status_path("approved"), do: ["submitted", "pending_risk", "approved"]
  defp status_path("rejected"), do: ["submitted", "pending_risk", "rejected"]
  defp status_path(_), do: ["submitted", "pending_risk", "approved"]

  # Private — random data

  defp pick_country(countries) when is_list(countries) and countries != [] do
    Enum.random(countries)
  end

  defp pick_country(_), do: Enum.random(@default_countries)

  defp pick_status(:default), do: Enum.random(CreditApplication.valid_statuses())

  defp pick_status(:dashboard) do
    @dashboard_status_weights
    |> Enum.flat_map(fn {status, weight} -> List.duplicate(status, weight) end)
    |> Enum.random()
  end

  defp pick_realistic_target, do: Enum.random(@realistic_targets)

  defp random_name do
    "#{Enum.random(@first_names)} #{Enum.random(@last_names)} #{Enum.random(@last_names)}"
  end

  defp random_decimal(min, max) do
    Decimal.new(Integer.to_string(Enum.random(min..max)))
  end

  defp random_application_date do
    now = DateTime.utc_now() |> DateTime.to_unix()
    ninety_days = 90 * 24 * 60 * 60
    seconds_ago = Enum.random(0..ninety_days)
    DateTime.from_unix!(now - seconds_ago, :second)
  end

  defp additional_review_flag("additional_review"), do: true
  defp additional_review_flag(_), do: Enum.random([true, false, false])

  defp split_targets(count, :bulk, _realistic_count), do: {0, count}
  defp split_targets(count, :realistic, _realistic_count), do: {count, 0}

  defp split_targets(count, :mixed, realistic_count) do
    realistic = min(realistic_count, count)
    {realistic, count - realistic}
  end

  defp log_created(app, mode) do
    IO.puts(
      "  Created (#{mode}): #{app.country} | #{app.full_name} | #{app.status} | amount=#{app.requested_amount}"
    )
  end

  defp print_summary(%{created: created, realistic: realistic, bulk: bulk, failed: failed}) do
    IO.puts("\nCreated #{created} demo applications (#{realistic} realistic, #{bulk} bulk)")

    if failed > 0 do
      IO.puts("Skipped #{failed} records due to validation or transition errors")
    end
  end

  # Private — env parsing

  defp maybe_put_int_env(opts, key, env_key) do
    case System.get_env(env_key) do
      nil -> opts
      "" -> opts
      value -> Keyword.put(opts, key, String.to_integer(value))
    end
  end

  defp maybe_put_mode_env(opts) do
    case System.get_env("SEED_MODE") do
      "bulk" -> Keyword.put(opts, :mode, :bulk)
      "realistic" -> Keyword.put(opts, :mode, :realistic)
      "mixed" -> Keyword.put(opts, :mode, :mixed)
      _ -> opts
    end
  end

  defp maybe_put_countries_env(opts) do
    case System.get_env("SEED_COUNTRIES") do
      nil ->
        opts

      "" ->
        opts

      value ->
        countries =
          value
          |> String.split(",", trim: true)
          |> Enum.map(&String.upcase/1)

        Keyword.put(opts, :countries, countries)
    end
  end

  defp maybe_put_scenario_env(opts) do
    case System.get_env("SEED_SCENARIO") do
      "dashboard" -> Keyword.put(opts, :scenario, :dashboard)
      _ -> opts
    end
  end
end
