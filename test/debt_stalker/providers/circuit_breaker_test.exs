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
