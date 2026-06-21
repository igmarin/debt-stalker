defmodule DebtStalker.ObanTelemetryHandler do
  @moduledoc """
  Telemetry handler that bridges Oban's built-in job events to
  custom `[:debt_stalker, :oban, :job, :stop]` events for business metrics.

  Attaches to `[:oban, :job, :stop]` and `[:oban, :job, :exception]` events
  and emits a normalized event with `:worker` and `:result` metadata.

  Started as a supervised GenServer to ensure reliable attachment and
  automatic re-attachment on restart.
  """

  use GenServer

  @handler_id :debt_stalker_oban_business_metrics

  # --- Client API ---

  @doc "Starts the telemetry handler GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Attaches the telemetry handler to Oban job events.

  Idempotent — safe to call multiple times.
  """
  @spec attach() :: :ok | {:error, :already_exists}
  def attach do
    :telemetry.attach_many(
      @handler_id,
      [
        [:oban, :job, :stop],
        [:oban, :job, :exception]
      ],
      &__MODULE__.handle_event/4,
      %{}
    )
  end

  @doc """
  Detaches the telemetry handler.

  Safe to call even if the handler is not attached.
  """
  @spec detach() :: :ok
  def detach do
    :telemetry.detach(@handler_id)
    :ok
  end

  @doc false
  @spec handle_event(term(), map(), map(), map()) :: :ok
  def handle_event([:oban, :job, :stop], _measurements, metadata, _config) do
    worker = to_string(metadata.worker)
    result = classify_result(metadata.result)
    DebtStalker.Telemetry.emit_oban_job(worker, result)
  end

  def handle_event([:oban, :job, :exception], _measurements, metadata, _config) do
    worker = to_string(metadata.worker)
    DebtStalker.Telemetry.emit_oban_job(worker, :error)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    attach()
    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
    detach()
    :ok
  end

  # --- Private ---

  @spec classify_result(term()) :: :success | :error
  defp classify_result(:ok), do: :success
  defp classify_result({:ok, _}), do: :success
  defp classify_result(_), do: :error
end
