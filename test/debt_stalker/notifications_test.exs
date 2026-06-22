defmodule DebtStalker.NotificationsTest do
  use DebtStalker.DataCase, async: true

  alias DebtStalker.Applications
  alias DebtStalker.Notifications

  @valid_es_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  describe "record_webhook_event/1" do
    test "stores a webhook event without raw payload" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      assert {:ok, event} =
               Notifications.record_webhook_event(%{
                 application_id: app.id,
                 source: "provider_es",
                 payload_hash: "abc123",
                 verified: true,
                 processed: false
               })

      assert event.application_id == app.id
      assert event.source == "provider_es"
      assert event.payload_hash == "abc123"
      # Raw payloads are never persisted.
      refute Map.has_key?(event, :raw_payload)
    end

    test "returns error for missing required fields" do
      assert {:error, %Ecto.Changeset{}} =
               Notifications.record_webhook_event(%{
                 source: "provider_es",
                 payload_hash: "abc123"
               })
    end
  end

  describe "webhook_event_exists?/1" do
    test "returns true when payload hash exists" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      Notifications.record_webhook_event(%{
        application_id: app.id,
        source: "provider_es",
        payload_hash: "duplicate-hash",
        verified: true,
        processed: false
      })

      assert Notifications.webhook_event_exists?("duplicate-hash")
      refute Notifications.webhook_event_exists?("unknown-hash")
    end
  end

  describe "record_notification_attempt/1" do
    test "stores an outbound notification attempt" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      assert {:ok, attempt} =
               Notifications.record_notification_attempt(%{
                 application_id: app.id,
                 notification_type: "status_notification",
                 status: "simulated",
                 endpoint: "simulated://local",
                 response_code: 200,
                 response_body: "OK",
                 attempt_number: 1
               })

      assert attempt.application_id == app.id
      assert attempt.notification_type == "status_notification"
      assert attempt.status == "simulated"
    end
  end

  describe "notification_exists?/2" do
    test "returns true when a notification type was already recorded" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      Notifications.record_notification_attempt(%{
        application_id: app.id,
        notification_type: "status_notification",
        status: "simulated",
        attempt_number: 1
      })

      assert Notifications.notification_exists?(app.id, "status_notification")
      refute Notifications.notification_exists?(app.id, "other_notification")
    end
  end
end
