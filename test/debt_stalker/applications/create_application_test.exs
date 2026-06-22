defmodule DebtStalker.Applications.CreateApplicationTest do
  use DebtStalker.DataCase, async: true

  alias DebtStalker.Applications
  alias DebtStalker.Applications.CreditApplication
  alias DebtStalker.Repo
  alias Ecto.Adapters.SQL

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

  describe "create_application/1" do
    test "valid ES application returns {:ok, app} with submitted status" do
      assert {:ok, %CreditApplication{} = app} = Applications.create_application(@valid_es_attrs)
      assert app.status == "submitted"
      assert app.country == "ES"
      assert app.full_name == "Juan Garcia"
    end

    test "valid MX application returns {:ok, app} with submitted status" do
      assert {:ok, %CreditApplication{} = app} = Applications.create_application(@valid_mx_attrs)
      assert app.status == "submitted"
      assert app.country == "MX"
    end

    test "application_date is server-set" do
      assert {:ok, app} = Applications.create_application(@valid_es_attrs)
      assert app.application_date != nil
      assert DateTime.diff(DateTime.utc_now(), app.application_date, :second) < 5
    end

    test "provider_summary is populated on success" do
      assert {:ok, app} = Applications.create_application(@valid_es_attrs)
      assert app.provider_summary != nil
      assert app.provider_summary["provider_status"] == "active"
    end

    test "identity_document is encrypted at rest" do
      assert {:ok, app} = Applications.create_application(@valid_es_attrs)

      # Read raw value from DB — it should NOT be the plaintext document
      {:ok, uuid_binary} = Ecto.UUID.dump(app.id)

      {:ok, %{rows: [[raw_doc]]}} =
        SQL.query(
          DebtStalker.Repo,
          "SELECT identity_document FROM credit_applications WHERE id = $1",
          [uuid_binary]
        )

      refute raw_doc == "12345678Z"
    end

    test "identity_document_hash is set" do
      assert {:ok, app} = Applications.create_application(@valid_es_attrs)
      assert app.identity_document_hash != nil
      assert String.length(app.identity_document_hash) == 64
    end

    test "invalid country returns changeset error" do
      attrs = Map.put(@valid_es_attrs, :country, "XX")
      assert {:error, changeset} = Applications.create_application(attrs)
      assert "is not supported" in errors_on(changeset).country
    end

    test "invalid ES document returns changeset error" do
      attrs = Map.put(@valid_es_attrs, :identity_document, "INVALID")
      assert {:error, changeset} = Applications.create_application(attrs)
      assert errors_on(changeset).identity_document != []
    end

    test "invalid MX document returns changeset error" do
      attrs = Map.put(@valid_mx_attrs, :identity_document, "invalid")
      assert {:error, changeset} = Applications.create_application(attrs)
      assert errors_on(changeset).identity_document != []
    end

    test "non-positive requested_amount returns changeset error" do
      attrs = Map.put(@valid_es_attrs, :requested_amount, Decimal.new("-1"))
      assert {:error, changeset} = Applications.create_application(attrs)
      assert errors_on(changeset).requested_amount != []
    end

    test "non-positive monthly_income returns changeset error" do
      attrs = Map.put(@valid_es_attrs, :monthly_income, Decimal.new("0"))
      assert {:error, changeset} = Applications.create_application(attrs)
      assert errors_on(changeset).monthly_income != []
    end

    test "ES amount > 15000 sets additional_review_required" do
      attrs = Map.put(@valid_es_attrs, :requested_amount, Decimal.new("20000"))
      assert {:ok, app} = Applications.create_application(attrs)
      assert app.additional_review_required == true
    end

    test "ES amount > 12x income sets additional_review_required" do
      attrs = Map.put(@valid_es_attrs, :requested_amount, Decimal.new("25000"))
      assert {:ok, app} = Applications.create_application(attrs)
      assert app.additional_review_required == true
    end

    test "provider failure stores with provider_error status" do
      # Use document that triggers :unavailable
      attrs = Map.put(@valid_es_attrs, :identity_document, "00000000T")
      assert {:ok, app} = Applications.create_application(attrs)
      assert app.status == "provider_error"
    end

    test "provider failure records status transition and audit log" do
      # Use document that triggers :unavailable
      attrs = Map.put(@valid_es_attrs, :identity_document, "00000000T")
      assert {:ok, app} = Applications.create_application(attrs)
      assert app.status == "provider_error"

      # app.id is a string UUID; the binary_id columns need a binary UUID.
      {:ok, app_uuid} = Ecto.UUID.dump(app.id)

      # Assert a status_transitions row exists for this application
      {:ok, %{rows: transition_rows}} =
        SQL.query(
          Repo,
          "SELECT from_status, to_status, triggered_by FROM application_status_transitions WHERE application_id = $1",
          [app_uuid]
        )

      assert length(transition_rows) == 1
      [[from_status, to_status, triggered_by]] = transition_rows
      assert from_status == "created"
      assert to_status == "provider_error"
      assert triggered_by == "provider"

      # Assert an audit_logs row exists for this application
      {:ok, %{rows: audit_rows}} =
        SQL.query(
          Repo,
          "SELECT action, actor FROM audit_logs WHERE application_id = $1",
          [app_uuid]
        )

      assert length(audit_rows) == 1
      [[action, actor]] = audit_rows
      assert action == "status_changed"
      assert actor == "provider"
    end
  end
end
