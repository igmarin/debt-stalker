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

    :telemetry.execute(
      [:debt_stalker, :provider, :fetch, :stop],
      %{count: 1, duration: nil},
      metadata
    )

    :ok
  end
end
