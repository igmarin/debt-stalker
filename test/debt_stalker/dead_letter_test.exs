defmodule DebtStalker.DeadLetterTest do
  use DebtStalker.DataCase, async: true

  alias DebtStalker.DeadLetter

  defp make_job(id, args, worker, error_text) do
    %Oban.Job{
      id: id,
      args: args,
      worker: worker,
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

  describe "capture/1" do
    test "captures an exhausted job with application_id, job type, and last error" do
      job_args = %{"application_id" => "app-123", "event_type" => "application.created"}

      job =
        make_job(
          42,
          job_args,
          "DebtStalker.Workers.RiskEvaluationWorker",
          "[runtime_error] something went wrong"
        )

      {:ok, dlq_entry} = DeadLetter.capture(job)

      assert dlq_entry.application_id == "app-123"
      assert dlq_entry.worker == "DebtStalker.Workers.RiskEvaluationWorker"
      assert dlq_entry.job_id == 42
      assert dlq_entry.attempt == 3
      assert dlq_entry.last_error =~ "something went wrong"
      # Safe keys are preserved
      assert dlq_entry.args["application_id"] == "app-123"
      assert dlq_entry.args["event_type"] == "application.created"
    end

    test "is idempotent — capturing the same job twice does not create duplicates" do
      job =
        make_job(
          99,
          %{"application_id" => "app-456"},
          "DebtStalker.Workers.WebhookProcessingWorker",
          "[error] failed"
        )

      {:ok, _first} = DeadLetter.capture(job)
      {:ok, _second} = DeadLetter.capture(job)

      entries = DeadLetter.list()
      assert length(entries) == 1
    end

    test "captures job without application_id gracefully" do
      job =
        make_job(
          77,
          %{"some_key" => "some_value"},
          "DebtStalker.Workers.EventDispatcherWorker",
          "[error] no app id"
        )

      {:ok, dlq_entry} = DeadLetter.capture(job)

      assert dlq_entry.application_id == nil
      assert dlq_entry.worker == "DebtStalker.Workers.EventDispatcherWorker"
    end

    test "redacts sensitive keys (PII) from args before storage" do
      job_args = %{
        "application_id" => "app-pii",
        "identity_document" => "12345678A",
        "full_name" => "John Doe",
        "event_type" => "application.created"
      }

      job = make_job(88, job_args, "DebtStalker.Workers.RiskEvaluationWorker", "error")

      {:ok, dlq_entry} = DeadLetter.capture(job)

      # Sensitive keys are redacted
      assert dlq_entry.args["identity_document"] == "[REDACTED]"
      assert dlq_entry.args["full_name"] == "[REDACTED]"
      # Safe keys are preserved
      assert dlq_entry.args["application_id"] == "app-pii"
      assert dlq_entry.args["event_type"] == "application.created"
      # Raw PII is not stored
      refute dlq_entry.args["identity_document"] =~ "12345678"
      refute dlq_entry.args["full_name"] =~ "John"
    end
  end

  describe "list/1" do
    test "returns all dead-letter entries ordered by most recent first" do
      job1 =
        make_job(
          1,
          %{"application_id" => "app-1"},
          "DebtStalker.Workers.RiskEvaluationWorker",
          "error1"
        )

      job2 =
        make_job(
          2,
          %{"application_id" => "app-2"},
          "DebtStalker.Workers.ExternalNotificationWorker",
          "error2"
        )

      {:ok, _} = DeadLetter.capture(job1)
      Process.sleep(10)
      {:ok, _} = DeadLetter.capture(job2)

      entries = DeadLetter.list()
      assert length(entries) == 2
      assert hd(entries).application_id == "app-2"
    end

    test "supports cursor-based pagination with :before" do
      Enum.each(1..5, fn i ->
        job =
          make_job(
            i,
            %{"application_id" => "app-#{i}"},
            "DebtStalker.Workers.RiskEvaluationWorker",
            "error"
          )

        {:ok, _} = DeadLetter.capture(job)
      end)

      # First page (default limit 50, so all 5)
      page1 = DeadLetter.list()
      assert length(page1) == 5

      # Page before the last entry of page1
      cursor = List.last(page1).id
      page2 = DeadLetter.list(before: cursor)
      assert page2 == []
    end

    test "respects :limit option" do
      Enum.each(1..5, fn i ->
        job =
          make_job(
            i,
            %{"application_id" => "app-#{i}"},
            "DebtStalker.Workers.RiskEvaluationWorker",
            "error"
          )

        {:ok, _} = DeadLetter.capture(job)
      end)

      page = DeadLetter.list(limit: 2)
      assert length(page) == 2
    end
  end

  describe "count/0" do
    test "returns the total number of dead-letter entries" do
      job =
        make_job(
          55,
          %{"application_id" => "app-count"},
          "DebtStalker.Workers.RiskEvaluationWorker",
          "error"
        )

      assert DeadLetter.count() == 0

      {:ok, _} = DeadLetter.capture(job)

      assert DeadLetter.count() == 1
    end
  end
end
