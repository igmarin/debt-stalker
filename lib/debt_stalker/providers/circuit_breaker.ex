defmodule DebtStalker.Providers.CircuitBreaker do
  @moduledoc """
  Circuit breaker for provider calls with retry budget and exponential backoff.

  Tracks consecutive failures per circuit instance. After `failure_threshold`
  consecutive failures, the circuit opens and fails fast with `{:error, :circuit_open}`.

  After `cooldown_ms` in the open state, the circuit transitions to half-open,
  allowing a single trial call. If the trial succeeds, the circuit closes.
  If it fails, the circuit re-opens and the cooldown timer restarts.

  Transient errors (`:timeout`, `:unavailable`) are retried up to `retry_budget`
  times with exponential backoff before counting as a failure.

  State changes are emitted as telemetry events:
  - `[:debt_stalker, :circuit_breaker, :open]`
  - `[:debt_stalker, :circuit_breaker, :close]`

  ## Configuration

  - `:failure_threshold` — consecutive failures before opening (default: 5)
  - `:cooldown_ms` — time to wait before half-open trial (default: 30_000)
  - `:retry_budget` — max retries for transient errors (default: 3)
  - `:base_backoff_ms` — base backoff for exponential retry (default: 100)
  """

  use GenServer

  require Logger

  @type state :: :closed | :open | :half_open

  @type config :: %{
          failure_threshold: pos_integer(),
          cooldown_ms: pos_integer(),
          retry_budget: non_neg_integer(),
          base_backoff_ms: pos_integer()
        }

  @default_config %{
    failure_threshold: 5,
    cooldown_ms: 30_000,
    retry_budget: 3,
    base_backoff_ms: 100
  }

  @transient_errors [:timeout, :unavailable]

  # --- Client API ---

  @doc "Starts the circuit breaker with the given configuration."
  @spec start_link(config() | keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    config = Map.merge(@default_config, Map.new(opts))
    start_link(config)
  end

  def start_link(%{} = config) do
    GenServer.start_link(__MODULE__, config)
  end

  @doc "Sets the adapter metadata (module, function, args) for telemetry context."
  @spec set_adapter(pid(), {module(), atom(), [term()]}) :: :ok
  def set_adapter(pid, {module, function, args}) do
    GenServer.call(pid, {:set_adapter, module, function, args})
  end

  @doc "Returns the current circuit state."
  @spec state(pid()) :: state()
  def state(pid) do
    GenServer.call(pid, :state)
  end

  @doc """
  Executes a function through the circuit breaker.

  Returns the function result, `{:error, :circuit_open}` if the circuit is open,
  or the last error if the retry budget is exhausted.
  """
  @spec call(pid(), (-> {:ok, term()} | {:error, atom()})) ::
          {:ok, term()} | {:error, atom()}
  def call(pid, fun) when is_function(fun, 0) do
    GenServer.call(pid, {:call, fun}, :infinity)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(config) do
    state = %{
      config: config,
      circuit_state: :closed,
      failure_count: 0,
      opened_at: nil,
      adapter: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:set_adapter, module, function, args}, _from, state) do
    {:reply, :ok, %{state | adapter: {module, function, args}}}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, state.circuit_state, state}
  end

  @impl true
  def handle_call({:call, fun}, _from, state) do
    case maybe_transition_to_half_open(state) do
      {:circuit_open, state} ->
        {:reply, {:error, :circuit_open}, state}

      {:allowed, state} ->
        {result, new_state} = execute_with_retry(fun, state)
        {:reply, result, new_state}
    end
  end

  # --- Private: state transitions ---

  defp maybe_transition_to_half_open(%{circuit_state: :open, opened_at: opened_at} = state) do
    elapsed = System.monotonic_time(:millisecond) - opened_at

    if elapsed >= state.config.cooldown_ms do
      {:allowed, %{state | circuit_state: :half_open}}
    else
      {:circuit_open, state}
    end
  end

  defp maybe_transition_to_half_open(state), do: {:allowed, state}

  # --- Private: retry logic ---

  defp execute_with_retry(fun, state) do
    execute_with_retry(fun, state, state.config.retry_budget, nil)
  end

  defp execute_with_retry(_fun, state, 0, last_error) do
    new_state = record_failure(state)
    {{:error, last_error}, new_state}
  end

  defp execute_with_retry(fun, state, remaining, _last_error) do
    case fun.() do
      {:ok, data} ->
        new_state = record_success(state)
        {{:ok, data}, new_state}

      {:error, reason} ->
        if reason in @transient_errors and remaining > 0 do
          backoff =
            state.config.base_backoff_ms * :math.pow(2, state.config.retry_budget - remaining)

          Process.sleep(round(backoff))
          execute_with_retry(fun, state, remaining - 1, reason)
        else
          new_state = record_failure(state)
          {{:error, reason}, new_state}
        end
    end
  end

  # --- Private: failure/success recording ---

  defp record_success(%{circuit_state: :half_open} = state) do
    transition_to_closed(state)
  end

  defp record_success(state) do
    %{state | failure_count: 0}
  end

  defp record_failure(%{circuit_state: :half_open} = state) do
    transition_to_open(state)
  end

  defp record_failure(state) do
    new_count = state.failure_count + 1

    if new_count >= state.config.failure_threshold do
      transition_to_open(state)
    else
      %{state | failure_count: new_count}
    end
  end

  # --- Private: state transition helpers ---

  defp transition_to_open(state) do
    country = extract_country(state)

    Logger.warning("Circuit breaker opened",
      country: country,
      from_state: state.circuit_state,
      to_state: :open
    )

    :telemetry.execute(
      [:debt_stalker, :circuit_breaker, :open],
      %{count: 1},
      %{
        country: country,
        from_state: state.circuit_state,
        to_state: :open
      }
    )

    %{
      state
      | circuit_state: :open,
        failure_count: 0,
        opened_at: System.monotonic_time(:millisecond)
    }
  end

  defp transition_to_closed(state) do
    country = extract_country(state)

    Logger.info("Circuit breaker closed",
      country: country,
      from_state: state.circuit_state,
      to_state: :closed
    )

    :telemetry.execute(
      [:debt_stalker, :circuit_breaker, :close],
      %{count: 1},
      %{
        country: country,
        from_state: state.circuit_state,
        to_state: :closed
      }
    )

    %{state | circuit_state: :closed, failure_count: 0, opened_at: nil}
  end

  defp extract_country(%{adapter: {_, _, [country | _]}}), do: country
  defp extract_country(_), do: nil
end
