defmodule DebtStalker.Applications.PiiEncryptionAtRestTest do
  @moduledoc """
  Verifies that PII (identity_document) is encrypted at rest in the database.

  This test exercises the full encryption pipeline:
  - identity_document is ciphertext when queried via raw SQL
  - identity_document_hash lookup still works (SHA-256)
  - API responses show last-4 only (redacted)
  - Logs do not contain raw identity_document values
  """

  use DebtStalker.DataCase, async: false

  alias DebtStalker.Applications
  alias DebtStalker.Applications.CreditApplication
  alias DebtStalker.Repo

  @valid_attrs %{
    country: "ES",
    full_name: "Jane Doe",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000.00"),
    monthly_income: Decimal.new("3000.00")
  }

  describe "identity_document ciphertext at rest" do
    test "raw SQL query returns ciphertext, not plaintext" do
      {:ok, app} = Applications.create_application(@valid_attrs)

      # Query the raw column value directly, bypassing Ecto/Cloak decryption
      [raw_value] =
        Repo.query!(
          "SELECT identity_document FROM credit_applications WHERE id = $1",
          [Ecto.UUID.dump!(app.id)]
        ).rows
        |> Enum.map(fn [row] -> row end)

      # The raw value should NOT contain the plaintext document
      refute raw_value =~ "12345678Z"

      # The raw value should be a non-empty binary (ciphertext)
      assert is_binary(raw_value)
      assert byte_size(raw_value) > 0
    end

    test "identity_document_hash is stored as SHA-256 hex" do
      {:ok, app} = Applications.create_application(@valid_attrs)

      [raw_hash] =
        Repo.query!(
          "SELECT identity_document_hash FROM credit_applications WHERE id = $1",
          [Ecto.UUID.dump!(app.id)]
        ).rows
        |> Enum.map(fn [row] -> row end)

      expected_hash = CreditApplication.hash_document("12345678Z")
      assert raw_hash == expected_hash
      assert String.length(raw_hash) == 64
    end

    test "hash lookup works without decryption" do
      {:ok, _app} = Applications.create_application(@valid_attrs)

      hash = CreditApplication.hash_document("12345678Z")

      # Lookup by hash directly (no decryption needed)
      found =
        Repo.get_by(
          CreditApplication,
          identity_document_hash: hash
        )

      assert found != nil
      assert found.full_name == "Jane Doe"
    end
  end

  describe "API response redaction" do
    test "redact_document shows last-4 only" do
      assert CreditApplication.redact_document("12345678Z") == "****678Z"
    end

    test "redact_document does not expose full document" do
      redacted = CreditApplication.redact_document("12345678Z")
      refute redacted =~ "12345"
    end
  end

  describe "log redaction" do
    import ExUnit.CaptureLog

    test "application creation log does not contain raw identity_document" do
      logs =
        capture_log(fn ->
          {:ok, _app} = Applications.create_application(@valid_attrs)
        end)

      # The log should not contain the raw identity document
      refute logs =~ "12345678Z"
    end
  end
end
