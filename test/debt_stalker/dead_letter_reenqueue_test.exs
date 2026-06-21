defmodule DebtStalker.DeadLetterReEnqueueTest do
  # async: false because the concurrency test needs serialized sandbox access
  # to properly test row-level locking with concurrent tasks.
  use DebtStalker.DataCase, async: false

  alias DebtStalker.DeadLetter

  defp make_job(id, args, worker, error_text) do
    %Oban.Job{
      id: id,
      args: args,
      worker: worker,
      queue: "events",
      max_attempts: 3,
      attempt: 3,
      errors: [
        %{
          "at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "attempt" => 3,
          "error" => error_text
        }
      ]
    }
  end

  describe "get/1" do
    test "returns a dead-letter entry by ID" do
      job =
        make_job(
          100,
          %{"application_id" => "app-get"},
          "DebtStalker.Workers.RiskEvaluationWorker",
          "error"
        )

      {:ok, entry} = DeadLetter.capture(job)

      assert DeadLetter.get(entry.id).id == entry.id
    end

    test "returns nil for non-existent ID" do
      assert DeadLetter.get(999_999) == nil
    end
  end

  describe "reenqueue/1" do
    test "creates a new Oban job from a dead-letter entry" do
      job =
        make_job(
          200,
          %{"application_id" => "app-reenq", "event_type" => "application.created"},
          "DebtStalker.Workers.RiskEvaluationWorker",
          "error"
        )

      {:ok, entry} = DeadLetter.capture(job)

      {:ok, new_job} = DeadLetter.reenqueue(entry.id)

      assert new_job.worker == "DebtStalker.Workers.RiskEvaluationWorker"
      assert new_job.args["application_id"] == "app-reenq"
      assert new_job.args["event_type"] == "application.created"
      assert new_job.state == "available"
    end

    test "marks the dead-letter entry as re-enqueued" do
      job =
        make_job(
          201,
          %{"application_id" => "app-mark"},
          "DebtStalker.Workers.RiskEvaluationWorker",
          "error"
        )

      {:ok, entry} = DeadLetter.capture(job)

      {:ok, _new_job} = DeadLetter.reenqueue(entry.id)

      updated = DeadLetter.get(entry.id)
      assert updated.reenqueued_at != nil
    end

    test "prevents double re-enqueue — returns {:error, :already_reenqueued}" do
      job =
        make_job(
          202,
          %{"application_id" => "app-double"},
          "DebtStalker.Workers.RiskEvaluationWorker",
          "error"
        )

      {:ok, entry} = DeadLetter.capture(job)

      {:ok, _first} = DeadLetter.reenqueue(entry.id)
      {:error, :already_reenqueued} = DeadLetter.reenqueue(entry.id)
    end

    test "returns {:error, :not_found} for non-existent entry" do
      {:error, :not_found} = DeadLetter.reenqueue(999_999)
    end

    test "returns {:error, :unknown_worker} for unresolvable worker module" do
      job = make_job(203, %{"application_id" => "app-unknown"}, "NonExistent.Worker", "error")
      {:ok, entry} = DeadLetter.capture(job)

      {:error, :unknown_worker} = DeadLetter.reenqueue(entry.id)
    end

    test "re-enqueued job preserves safe args only (no PII)" do
      job_args = %{
        "application_id" => "app-safe",
        "identity_document" => "12345678A",
        "full_name" => "John Doe",
        "event_type" => "application.created"
      }

      job = make_job(204, job_args, "DebtStalker.Workers.RiskEvaluationWorker", "error")
      {:ok, entry} = DeadLetter.capture(job)

      {:ok, new_job} = DeadLetter.reenqueue(entry.id)

      # Safe keys preserved
      assert new_job.args["application_id"] == "app-safe"
      assert new_job.args["event_type"] == "application.created"
      # PII was redacted at capture time, so it's not in the new job
      refute new_job.args["identity_document"] =~ "12345678"
      refute new_job.args["full_name"] =~ "John"
    end
  end

  describe "reenqueue/1 concurrency" do
    test "concurrent reenqueue calls do not create duplicate Oban jobs" do
      job =
        make_job(
          400,
          %{"application_id" => "app-concurrent"},
          "DebtStalker.Workers.RiskEvaluationWorker",
          "error"
        )

      {:ok, entry} = DeadLetter.capture(job)

      # The Ecto sandbox owns the connection for this test.
      # We must allow child tasks to use the same connection.
      parent = self()

      tasks =
        Enum.map(1..5, fn _ ->
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.allow(DebtStalker.Repo, parent, self())
            DeadLetter.reenqueue(entry.id)
          end)
        end)

      results = Task.await_many(tasks, 5000)

      # Exactly one should succeed, the rest should be :already_reenqueued
      successes = Enum.count(results, fn r -> match?({:ok, _}, r) end)
      already = Enum.count(results, fn r -> match?({:error, :already_reenqueued}, r) end)

      assert successes == 1
      assert already == 4
    end
  end

  describe "reenqueue_many/1" do
    test "re-enqueues multiple pending dead-letter entries" do
      job1 =
        make_job(
          300,
          %{"application_id" => "app-batch-1"},
          "DebtStalker.Workers.RiskEvaluationWorker",
          "error"
        )

      job2 =
        make_job(
          301,
          %{"application_id" => "app-batch-2"},
          "DebtStalker.Workers.RiskEvaluationWorker",
          "error"
        )

      {:ok, entry1} = DeadLetter.capture(job1)
      {:ok, entry2} = DeadLetter.capture(job2)

      {:ok, count} = DeadLetter.reenqueue_pending()

      assert count == 2

      assert DeadLetter.get(entry1.id).reenqueued_at != nil
      assert DeadLetter.get(entry2.id).reenqueued_at != nil
    end

    test "skips already re-enqueued entries" do
      job1 =
        make_job(
          302,
          %{"application_id" => "app-skip-1"},
          "DebtStalker.Workers.RiskEvaluationWorker",
          "error"
        )

      job2 =
        make_job(
          303,
          %{"application_id" => "app-skip-2"},
          "DebtStalker.Workers.RiskEvaluationWorker",
          "error"
        )

      {:ok, entry1} = DeadLetter.capture(job1)
      {:ok, entry2} = DeadLetter.capture(job2)

      {:ok, _} = DeadLetter.reenqueue(entry1.id)

      {:ok, count} = DeadLetter.reenqueue_pending()

      assert count == 1
      assert DeadLetter.get(entry2.id).reenqueued_at != nil
    end
  end
end
