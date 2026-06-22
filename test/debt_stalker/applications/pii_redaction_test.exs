defmodule DebtStalker.Applications.PiiRedactionTest do
  @moduledoc """
  Edge case tests for PII redaction of identity documents.
  """
  use ExUnit.Case, async: true

  alias DebtStalker.Applications.CreditApplication

  describe "redact_document/1" do
    test "nil returns ****" do
      assert CreditApplication.redact_document(nil) == "****"
    end

    test "empty string returns ****" do
      assert CreditApplication.redact_document("") == "****"
    end

    test "1-char document returns ****" do
      assert CreditApplication.redact_document("A") == "****"
    end

    test "2-char document returns ****" do
      assert CreditApplication.redact_document("AB") == "****"
    end

    test "3-char document returns ****" do
      assert CreditApplication.redact_document("ABC") == "****"
    end

    test "4-char document returns ****" do
      assert CreditApplication.redact_document("ABCD") == "****"
    end

    test "5-char document shows last 4" do
      assert CreditApplication.redact_document("12345") == "****2345"
    end

    test "DNI (9 chars) shows last 4" do
      assert CreditApplication.redact_document("12345678Z") == "****678Z"
    end

    test "CURP (18 chars) shows last 4" do
      assert CreditApplication.redact_document("GARC850101HDFRRL09") == "****RL09"
    end
  end

  describe "redact_full_name/1" do
    test "nil returns empty string" do
      assert CreditApplication.redact_full_name(nil) == ""
    end

    test "single name is unchanged" do
      assert CreditApplication.redact_full_name("Maria") == "Maria"
    end

    test "two names redacts to first + last initial" do
      assert CreditApplication.redact_full_name("Juan Garcia") == "Juan G."
    end

    test "three names redacts to first + last initial" do
      assert CreditApplication.redact_full_name("Juan Garcia Lopez") == "Juan L."
    end

    test "empty string returns empty string" do
      assert CreditApplication.redact_full_name("") == ""
    end
  end

  describe "hash_document/1" do
    test "produces consistent SHA-256 hex" do
      hash1 = CreditApplication.hash_document("12345678Z")
      hash2 = CreditApplication.hash_document("12345678Z")
      assert hash1 == hash2
      assert String.length(hash1) == 64
    end

    test "different documents produce different hashes" do
      hash1 = CreditApplication.hash_document("12345678Z")
      hash2 = CreditApplication.hash_document("87654321X")
      refute hash1 == hash2
    end
  end
end
