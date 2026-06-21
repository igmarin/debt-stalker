defmodule DebtStalker.Applications.UpdateStatusTest do
  use DebtStalker.DataCase, async: true

  alias DebtStalker.Applications
  alias Ecto.Adapters.SQL

  @valid_es_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  setup do
    {:ok, app} = Applications.create_application(@valid_es_attrs)
    %{app: app}
  end

  describe "update_status/3" do
    test "valid transition updates status", %{app: app} do
      assert {:ok, updated} = Applications.update_status(app.id, "pending_risk", "system")
      assert updated.status == "pending_risk"
    end

    test "invalid transition returns error", %{app: app} do
      assert {:error, :invalid_transition} =
               Applications.update_status(app.id, "approved", "system")
    end

    test "creates transition row", %{app: app} do
      {:ok, _updated} = Applications.update_status(app.id, "pending_risk", "system")

      {:ok, uuid_binary} = Ecto.UUID.dump(app.id)

      {:ok, %{rows: rows}} =
        SQL.query(
          DebtStalker.Repo,
          "SELECT from_status, to_status, triggered_by FROM application_status_transitions WHERE application_id = $1",
          [uuid_binary]
        )

      assert length(rows) == 1
      [[from, to, triggered_by]] = rows
      assert from == "submitted"
      assert to == "pending_risk"
      assert triggered_by == "system"
    end

    test "creates audit log row", %{app: app} do
      {:ok, _updated} = Applications.update_status(app.id, "pending_risk", "system")

      {:ok, uuid_binary} = Ecto.UUID.dump(app.id)

      {:ok, %{rows: rows}} =
        SQL.query(
          DebtStalker.Repo,
          "SELECT action, actor FROM audit_logs WHERE application_id = $1",
          [uuid_binary]
        )

      assert rows != []
      assert Enum.any?(rows, fn [action, _actor] -> action == "status_changed" end)
    end

    test "broadcasts PubSub event", %{app: app} do
      Phoenix.PubSub.subscribe(DebtStalker.PubSub, "applications:#{app.id}")
      {:ok, _updated} = Applications.update_status(app.id, "pending_risk", "system")

      assert_receive {:status_changed, %{from: "submitted", to: "pending_risk"}}, 1000
    end

    test "broadcasts PubSub event to applications:list topic", %{app: app} do
      Phoenix.PubSub.subscribe(DebtStalker.PubSub, "applications:list")
      {:ok, _updated} = Applications.update_status(app.id, "pending_risk", "system")

      assert_receive {:status_changed, %{from: "submitted", to: "pending_risk"}}, 1000
    end

    test "unknown application returns not_found" do
      assert {:error, :not_found} =
               Applications.update_status(Ecto.UUID.generate(), "pending_risk", "system")
    end

    test "chained valid transitions work", %{app: app} do
      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")
      {:ok, updated} = Applications.update_status(app.id, "approved", "system")
      assert updated.status == "approved"
    end
  end
end
