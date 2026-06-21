defmodule DebtStalker.Providers.CircuitBreakerIntegrationTest do
  @moduledoc """
  Integration tests for provider circuit breaker wiring through Applications.
  """
  use DebtStalker.DataCase, async: false

  alias DebtStalker.Applications
  alias DebtStalker.Providers.CircuitBreaker
  alias DebtStalker.Providers.CircuitBreakers

  @failing_es_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "99999999R",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  describe "create_application/1 provider fetch" do
    test "opens circuit after consecutive provider failures and returns provider_error" do
      {:ok, breaker} = CircuitBreakers.lookup("ES")
      CircuitBreaker.reset(breaker)

      # Drive the circuit open directly (test config uses a high threshold to avoid async pollution)
      for _ <- 1..100 do
        CircuitBreaker.call(breaker, fn -> {:error, :timeout} end)
      end

      assert CircuitBreaker.state(breaker) == :open

      assert {:ok, %{status: "provider_error"}} =
               Applications.create_application(@failing_es_attrs)
    end
  end
end
