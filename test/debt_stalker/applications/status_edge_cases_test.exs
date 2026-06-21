defmodule DebtStalker.Applications.StatusEdgeCasesTest do
  @moduledoc """
  Edge case tests for status transitions including terminal states,
  cancellation paths, and country-specific transition validation.
  """
  use DebtStalker.DataCase, async: true

  alias DebtStalker.Applications

  @valid_es_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  @valid_mx_attrs %{
    country: "MX",
    full_name: "Maria Lopez",
    identity_document: "GARC850101HDFRRL09",
    requested_amount: Decimal.new("8000"),
    monthly_income: Decimal.new("2000")
  }

  describe "terminal states cannot transition" do
    test "cannot transition from approved" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")
      {:ok, _} = Applications.update_status(app.id, "approved", "system")

      assert {:error, :invalid_transition} =
               Applications.update_status(app.id, "pending_risk", "system")

      assert {:error, :invalid_transition} =
               Applications.update_status(app.id, "submitted", "system")

      assert {:error, :invalid_transition} =
               Applications.update_status(app.id, "rejected", "system")
    end

    test "cannot transition from rejected" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")
      {:ok, _} = Applications.update_status(app.id, "rejected", "system")

      assert {:error, :invalid_transition} =
               Applications.update_status(app.id, "approved", "system")

      assert {:error, :invalid_transition} =
               Applications.update_status(app.id, "pending_risk", "system")
    end

    test "cannot transition from cancelled" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, _} = Applications.update_status(app.id, "cancelled", "system")

      assert {:error, :invalid_transition} =
               Applications.update_status(app.id, "pending_risk", "system")

      assert {:error, :invalid_transition} =
               Applications.update_status(app.id, "approved", "system")
    end
  end

  describe "cancellation paths" do
    test "can cancel from submitted" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      assert {:ok, updated} = Applications.update_status(app.id, "cancelled", "user")
      assert updated.status == "cancelled"
    end

    test "can cancel from pending_risk" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")
      assert {:ok, updated} = Applications.update_status(app.id, "cancelled", "user")
      assert updated.status == "cancelled"
    end

    test "cannot cancel from additional_review" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")
      {:ok, _} = Applications.update_status(app.id, "additional_review", "system")

      assert {:error, :invalid_transition} =
               Applications.update_status(app.id, "cancelled", "user")
    end
  end

  describe "country-specific transitions" do
    test "ES transitions are validated against country module" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      # submitted → pending_risk is valid for ES
      assert {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")
    end

    test "MX transitions are validated against country module" do
      {:ok, app} = Applications.create_application(@valid_mx_attrs)
      # submitted → pending_risk is valid for MX
      assert {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")
    end

    test "provider_error can transition to pending_risk (retry)" do
      # Use document that triggers provider_error
      attrs = Map.put(@valid_es_attrs, :identity_document, "00000000T")
      {:ok, app} = Applications.create_application(attrs)
      assert app.status == "provider_error"

      assert {:ok, updated} = Applications.update_status(app.id, "pending_risk", "system")
      assert updated.status == "pending_risk"
    end

    test "provider_error can transition to rejected" do
      attrs = Map.put(@valid_es_attrs, :identity_document, "00000000T")
      {:ok, app} = Applications.create_application(attrs)
      assert app.status == "provider_error"

      assert {:ok, updated} = Applications.update_status(app.id, "rejected", "system")
      assert updated.status == "rejected"
    end
  end

  describe "same-status transitions" do
    test "cannot transition to same status" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      assert {:error, :invalid_transition} =
               Applications.update_status(app.id, "submitted", "system")
    end
  end
end
