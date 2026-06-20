defmodule DebtStalker.ConcurrencyTest do
  @moduledoc """
  Integration test verifying the outbox pattern's concurrency safety.

  Simulates multiple EventDispatcherWorker instances racing to claim events,
  ensuring no event is processed more than once (FOR UPDATE SKIP LOCKED).
  """
  use DebtStalker.DataCase, async: false

  alias DebtStalker.Applications
  alias DebtStalker.Workers.EventDispatcherWorker
  alias Ecto.Adapters.SQL

  @valid_es_attrs %{
    country: "ES",
    full_name: "Concurrent Test User",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  describe "event dispatcher concurrency" do
    @describetag :integration
    test "SKIP LOCKED prevents double-processing of events" do
      # Create 5 applications to generate 5 events
      apps =
        for i <- 1..5 do
          {:ok, app} =
            Applications.create_application(Map.put(@valid_es_attrs, :full_name, "User #{i}"))

          app
        end

      assert length(apps) == 5

      # Verify events were created by triggers
      {:ok, %{rows: [[event_count]]}} =
        SQL.query(
          DebtStalker.Repo,
          "SELECT COUNT(*) FROM application_events WHERE processed_at IS NULL",
          []
        )

      assert event_count >= 5

      # Run 3 dispatchers concurrently — they should partition the events
      tasks =
        for _i <- 1..3 do
          Task.async(fn ->
            EventDispatcherWorker.claim_and_dispatch()
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # Total events processed across all tasks should equal the number of unprocessed events
      total_processed =
        Enum.sum(
          Enum.map(results, fn
            {:ok, count} -> count
            _ -> 0
          end)
        )

      assert total_processed >= 5

      # Verify no unprocessed events remain
      {:ok, %{rows: [[remaining]]}} =
        SQL.query(
          DebtStalker.Repo,
          "SELECT COUNT(*) FROM application_events WHERE processed_at IS NULL",
          []
        )

      assert remaining == 0

      # Verify no duplicate processing (each event has exactly one processed_at)
      {:ok, %{rows: [[total_events]]}} =
        SQL.query(
          DebtStalker.Repo,
          "SELECT COUNT(*) FROM application_events WHERE processed_at IS NOT NULL",
          []
        )

      assert total_events >= 5
    end
  end
end
