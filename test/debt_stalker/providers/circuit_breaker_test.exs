defmodule DebtStalker.Providers.CircuitBreakerTest do
  use ExUnit.Case, async: true

  alias DebtStalker.Providers.CircuitBreaker

  setup do
    # Start a fresh circuit breaker for each test
    config = %{
      failure_threshold: 3,
      cooldown_ms: 1000,
      retry_budget: 3,
      base_backoff_ms: 10
    }

    {:ok, pid} = CircuitBreaker.start_link(config)
    CircuitBreaker.set_adapter(pid, {DebtStalker.Providers.Behaviour, :fetch, ["ES"]})

    on_exit(fn ->
      try do
        GenServer.stop(pid, :normal)
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, pid: pid}
  end

  describe "circuit breaker states" do
    test "starts in closed state", %{pid: pid} do
      assert CircuitBreaker.state(pid) == :closed
    end

    test "opens after threshold of consecutive failures", %{pid: pid} do
      # Simulate 3 failures (threshold)
      Enum.each(1..3, fn _ ->
        CircuitBreaker.call(pid, fn -> {:error, :timeout} end)
      end)

      assert CircuitBreaker.state(pid) == :open
    end

    test "resets failure count on success", %{pid: pid} do
      # 2 failures (below threshold)
      CircuitBreaker.call(pid, fn -> {:error, :timeout} end)
      CircuitBreaker.call(pid, fn -> {:error, :timeout} end)

      assert CircuitBreaker.state(pid) == :closed

      # Success resets the counter
      CircuitBreaker.call(pid, fn -> {:ok, :data} end)

      # Now 2 more failures should not open the circuit
      CircuitBreaker.call(pid, fn -> {:error, :timeout} end)
      CircuitBreaker.call(pid, fn -> {:error, :timeout} end)

      assert CircuitBreaker.state(pid) == :closed
    end

    test "open circuit fails fast with {:error, :circuit_open}", %{pid: pid} do
      # Open the circuit
      Enum.each(1..3, fn _ ->
        CircuitBreaker.call(pid, fn -> {:error, :timeout} end)
      end)

      assert CircuitBreaker.state(pid) == :open

      # Next call should fail fast without calling the function
      result = CircuitBreaker.call(pid, fn -> {:ok, :should_not_be_called} end)
      assert result == {:error, :circuit_open}
    end
  end

  describe "retry budget" do
    test "retries transient errors with exponential backoff", %{pid: pid} do
      attempts = :atomics.new(1, [])

      result =
        CircuitBreaker.call(pid, fn ->
          count = :atomics.add_get(attempts, 1, 1)
          if count < 3, do: {:error, :timeout}, else: {:ok, :data}
        end)

      assert result == {:ok, :data}
      assert :atomics.get(attempts, 1) == 3
    end

    test "budget exhaustion returns last error", %{pid: pid} do
      result =
        CircuitBreaker.call(pid, fn -> {:error, :timeout} end)

      assert result == {:error, :timeout}
      assert CircuitBreaker.state(pid) == :closed
    end

    test "budget exhaustion after threshold failures opens circuit", %{pid: pid} do
      # Each call exhausts the retry budget (3 retries), and each exhaustion
      # counts as one failure. After 3 failures, circuit opens.
      Enum.each(1..3, fn _ ->
        CircuitBreaker.call(pid, fn -> {:error, :timeout} end)
      end)

      assert CircuitBreaker.state(pid) == :open
    end
  end

  describe "half-open concurrency" do
    test "half-open state allows only one concurrent trial call" do
      # Short cooldown so the circuit transitions open -> half_open quickly.
      config = %{
        failure_threshold: 2,
        cooldown_ms: 10,
        retry_budget: 1,
        base_backoff_ms: 1
      }

      {:ok, pid} = CircuitBreaker.start_link(config)
      CircuitBreaker.set_adapter(pid, {DebtStalker.Providers.Behaviour, :fetch, ["ES"]})

      on_exit(fn ->
        try do
          GenServer.stop(pid, :normal)
        catch
          :exit, _ -> :ok
        end
      end)

      # Open the circuit with 2 failures (threshold).
      Enum.each(1..2, fn _ ->
        CircuitBreaker.call(pid, fn -> {:error, :timeout} end)
      end)

      assert CircuitBreaker.state(pid) == :open

      # Wait for cooldown so the next check_access transitions to half_open.
      Process.sleep(50)

      # Fire 5 concurrent calls. The trial function records its execution and
      # holds the slot briefly so concurrent callers arrive while the trial
      # is in-flight. Only ONE caller should execute the trial; the rest must
      # fail fast with {:error, :circuit_open}.
      #
      # Uses spawn + explicit message passing (not Task.async) so a caller
      # crash is reported as a result tuple rather than killing the test
      # process via the link.
      test_pid = self()
      execution_count = :atomics.new(1, [])
      caller_ref = make_ref()

      callers =
        Enum.map(1..5, fn _ ->
          spawn(fn ->
            result =
              try do
                CircuitBreaker.call(pid, fn ->
                  :atomics.add_get(execution_count, 1, 1)
                  send(test_pid, {:trial_started, caller_ref})
                  # Hold the trial slot long enough for concurrent callers to
                  # hit check_access while the trial is in-flight.
                  Process.sleep(30)
                  {:ok, :data}
                end)
              catch
                kind, reason -> {:error, {:caller_crashed, kind, reason}}
              end

            send(test_pid, {:caller_result, caller_ref, result})
          end)
        end)

      # At least one trial must have started.
      assert_receive {:trial_started, ^caller_ref}, 200

      # Give the remaining callers time to hit check_access while the trial
      # is still in-flight (the trial holds the slot for 30ms).
      Process.sleep(10)

      # Collect all 5 results.
      results =
        Enum.map(callers, fn _ ->
          assert_receive {:caller_result, ^caller_ref, result}, 1000
          result
        end)

      # Exactly one trial executed the function.
      assert :atomics.get(execution_count, 1) == 1

      # One caller succeeded; the other four were rejected while the trial
      # was in-flight.
      successes = Enum.count(results, &(&1 == {:ok, :data}))
      rejected = Enum.count(results, &(&1 == {:error, :circuit_open}))

      assert successes == 1
      assert rejected == 4
    end

    test "trial slot is released when the caller crashes before reporting" do
      config = %{
        failure_threshold: 2,
        cooldown_ms: 10,
        retry_budget: 1,
        base_backoff_ms: 1
      }

      {:ok, pid} = CircuitBreaker.start_link(config)
      CircuitBreaker.set_adapter(pid, {DebtStalker.Providers.Behaviour, :fetch, ["ES"]})

      on_exit(fn ->
        try do
          GenServer.stop(pid, :normal)
        catch
          :exit, _ -> :ok
        end
      end)

      # Open the circuit.
      Enum.each(1..2, fn _ ->
        CircuitBreaker.call(pid, fn -> {:error, :timeout} end)
      end)

      assert CircuitBreaker.state(pid) == :open

      # Wait for cooldown.
      Process.sleep(50)

      # Spawn a caller that gets the trial slot and then is killed before
      # it can call report_result. This simulates a process crash.
      trial_holder = spawn(fn -> CircuitBreaker.call(pid, fn -> Process.sleep(5000) end) end)

      # Give the caller time to acquire the trial slot via check_access.
      Process.sleep(20)

      # Kill the caller — it will never call report_result.
      Process.exit(trial_holder, :kill)

      # The GenServer should receive the :DOWN message and reset the slot,
      # transitioning back to :open so the circuit is not permanently stuck.
      Process.sleep(50)

      assert CircuitBreaker.state(pid) == :open

      # After another cooldown, the circuit should allow a new trial —
      # proving the slot was released and the circuit recovered.
      Process.sleep(50)

      result = CircuitBreaker.call(pid, fn -> {:ok, :recovered} end)
      assert result == {:ok, :recovered}
      assert CircuitBreaker.state(pid) == :closed
    end
  end

  describe "telemetry" do
    test "emits telemetry event when circuit opens" do
      # Attach a telemetry handler to capture the event
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        {:circuit_open_test, ref},
        [:debt_stalker, :circuit_breaker, :open],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:circuit_open, metadata})
        end,
        %{}
      )

      config = %{
        failure_threshold: 2,
        cooldown_ms: 1000,
        retry_budget: 1,
        base_backoff_ms: 1
      }

      {:ok, pid} = CircuitBreaker.start_link(config)
      CircuitBreaker.set_adapter(pid, {DebtStalker.Providers.Behaviour, :fetch, ["ES"]})

      Enum.each(1..2, fn _ ->
        CircuitBreaker.call(pid, fn -> {:error, :timeout} end)
      end)

      assert_received {:circuit_open, %{country: "ES", from_state: :closed, to_state: :open}}

      :telemetry.detach({:circuit_open_test, ref})

      GenServer.stop(pid, :normal)
    end

    test "emits telemetry event when circuit closes" do
      config = %{
        failure_threshold: 2,
        cooldown_ms: 10,
        retry_budget: 1,
        base_backoff_ms: 1
      }

      {:ok, pid} = CircuitBreaker.start_link(config)
      CircuitBreaker.set_adapter(pid, {DebtStalker.Providers.Behaviour, :fetch, ["ES"]})

      # Open the circuit
      Enum.each(1..2, fn _ ->
        CircuitBreaker.call(pid, fn -> {:error, :timeout} end)
      end)

      assert CircuitBreaker.state(pid) == :open

      # Wait for cooldown
      Process.sleep(50)

      # Attach handler for close event
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        {:circuit_close_test, ref},
        [:debt_stalker, :circuit_breaker, :close],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:circuit_close, metadata})
        end,
        %{}
      )

      # Successful call should close the circuit
      result = CircuitBreaker.call(pid, fn -> {:ok, :data} end)
      assert result == {:ok, :data}

      assert_received {:circuit_close,
                       %{country: "ES", from_state: :half_open, to_state: :closed}}

      :telemetry.detach({:circuit_close_test, ref})

      GenServer.stop(pid, :normal)
    end
  end
end
