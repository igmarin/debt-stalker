defmodule DebtStalker.Telemetry do
  @moduledoc """
  Centralized telemetry event emission for Debt Stalker.

  Provides helper functions that wrap `:telemetry.execute/3` calls with
  consistent event names, measurements, and metadata for custom application
  events (status transitions, provider calls).

  Built-in events from Phoenix, Ecto, and Oban are emitted automatically
  by those libraries and are not wrapped here.
  """

  @doc """
  Emits a `[:debt_stalker, :status_transition, :stop]` telemetry event
  after a successful status transition.

  ## Measurements

  - `:count` — always 1 (for counter metrics)
  - `:duration` — monotonic time delta in native units (may be nil if not measured)

  ## Metadata

  - `:application_id` — the application UUID
  - `:country` — the country code
  - `:from_status` — the previous status
  - `:to_status` — the new status
  - `:triggered_by` — who or what triggered the transition
  """
  @spec emit_status_transition(String.t(), String.t(), String.t(), String.t(), map()) :: :ok
  def emit_status_transition(application_id, country, from_status, to_status, triggered_by) do
    :telemetry.execute(
      [:debt_stalker, :status_transition, :stop],
      %{count: 1, duration: nil},
      %{
        application_id: application_id,
        country: country,
        from_status: from_status,
        to_status: to_status,
        triggered_by: triggered_by
      }
    )

    :ok
  end

  @doc """
  Emits a `[:debt_stalker, :provider, :fetch, :stop]` telemetry event
  after a provider call completes (success or failure).

  ## Measurements

  - `:count` — always 1 (for counter metrics)
  - `:duration` — monotonic time delta in native units (may be nil if not measured)

  ## Metadata

  - `:country` — the country code
  - `:outcome` — `:success` or `:error`
  - `:error_reason` — the error atom (only present on failure)
  """
  @spec emit_provider_call(String.t(), :success | :error, keyword()) :: :ok
  def emit_provider_call(country, outcome, opts \\ []) do
    metadata = %{
      country: country,
      outcome: outcome
    }

    metadata =
      case Keyword.get(opts, :error_reason) do
        nil -> metadata
        reason -> Map.put(metadata, :error_reason, reason)
      end

    duration = Keyword.get(opts, :duration, 0)

    :telemetry.execute(
      [:debt_stalker, :provider, :fetch, :stop],
      %{count: 1, duration: duration},
      metadata
    )

    :telemetry.execute(
      [:debt_stalker, :provider, :latency],
      %{duration: duration},
      metadata
    )

    :ok
  end

  @doc """
  Emits a `[:debt_stalker, :application, :created]` telemetry event
  after a new credit application is created.

  ## Measurements

  - `:count` — always 1 (for counter metrics)

  ## Metadata

  - `:application_id` — the application UUID
  - `:country` — the country code
  - `:status` — the initial status
  """
  @spec emit_application_created(String.t(), String.t(), String.t()) :: :ok
  def emit_application_created(application_id, country, status) do
    :telemetry.execute(
      [:debt_stalker, :application, :created],
      %{count: 1},
      %{
        application_id: application_id,
        country: country,
        status: status
      }
    )

    :ok
  end

  @doc """
  Emits a `[:debt_stalker, :oban, :job, :stop]` telemetry event
  after an Oban job completes (success or failure).

  This wraps the built-in Oban telemetry events into a custom event
  with normalized metadata for business metrics.

  ## Measurements

  - `:count` — always 1 (for counter metrics)

  ## Metadata

  - `:worker` — the worker module name as a string
  - `:result` — `:success` or `:error`
  """
  @spec emit_oban_job(String.t(), :success | :error) :: :ok
  def emit_oban_job(worker, result) do
    :telemetry.execute(
      [:debt_stalker, :oban, :job, :stop],
      %{count: 1},
      %{
        worker: worker,
        result: result
      }
    )

    :ok
  end
end
