defmodule DebtStalker.Seeds.DemoTest do
  use DebtStalker.DataCase, async: false

  alias DebtStalker.Applications.CreditApplication
  alias DebtStalker.Repo
  alias DebtStalker.Seeds.Demo

  describe "build_attrs/1" do
    test "returns a map with required fields" do
      attrs = Demo.build_attrs(country: "ES")

      assert attrs.country == "ES"
      assert is_binary(attrs.full_name)
      assert is_binary(attrs.identity_document)
      assert %Decimal{} = attrs.requested_amount
      assert %Decimal{} = attrs.monthly_income
      assert is_binary(attrs.status)
      assert %DateTime{} = attrs.application_date
    end

    test "picks a country from the list when not specified" do
      attrs = Demo.build_attrs(countries: ["MX"])
      assert attrs.country == "MX"
    end

    test "generates dashboard-weighted statuses" do
      attrs = Demo.build_attrs(scenario: :dashboard)
      assert attrs.status in CreditApplication.valid_statuses()
    end

    test "sets additional_review_required to true for additional_review status" do
      # Test multiple times since status is random
      results =
        Enum.map(1..50, fn _ ->
          Demo.build_attrs(scenario: :dashboard)
        end)

      additional_review_attrs = Enum.filter(results, &(&1.status == "additional_review"))
      assert Enum.all?(additional_review_attrs, & &1.additional_review_required)
    end
  end

  describe "run/1" do
    test "creates applications in bulk mode" do
      result = Demo.run(count: 5, mode: :bulk, quiet: true)

      assert result.created == 5
      assert result.realistic == 0
      assert result.bulk == 5
      assert result.failed == 0
    end

    test "creates applications in realistic mode" do
      result = Demo.run(count: 3, mode: :realistic, quiet: true)

      assert result.created == 3
      assert result.realistic == 3
      assert result.bulk == 0
    end

    test "creates applications in mixed mode" do
      result = Demo.run(count: 10, mode: :mixed, realistic_count: 3, quiet: true)

      assert result.created == 10
      assert result.realistic == 3
      assert result.bulk == 7
    end

    test "respects country filter" do
      Demo.run(count: 5, mode: :bulk, countries: ["ES"], quiet: true)

      apps = Repo.all(CreditApplication)
      assert Enum.all?(apps, &(&1.country == "ES"))
    end

    test "handles zero count gracefully" do
      result = Demo.run(count: 0, mode: :mixed, quiet: true)

      assert result.created == 0
      assert result.realistic == 0
      assert result.bulk == 0
    end
  end

  describe "create_realistic/1" do
    test "creates an application and walks it to a target status" do
      assert {:ok, app} = Demo.create_realistic(country: "ES", target_status: "approved")

      assert app.status == "approved"
    end

    test "creates an application with pending_risk target" do
      assert {:ok, app} = Demo.create_realistic(country: "MX", target_status: "pending_risk")

      assert app.status == "pending_risk"
    end
  end

  describe "options_from_env/0" do
    test "returns empty list when no env vars are set" do
      # Clear env vars
      System.delete_env("SEED_COUNT")
      System.delete_env("SEED_MODE")
      System.delete_env("SEED_REALISTIC_COUNT")
      System.delete_env("SEED_COUNTRIES")
      System.delete_env("SEED_SCENARIO")

      assert Demo.options_from_env() == []
    end

    test "parses SEED_COUNT" do
      System.put_env("SEED_COUNT", "50")
      opts = Demo.options_from_env()
      System.delete_env("SEED_COUNT")

      assert Keyword.get(opts, :count) == 50
    end

    test "parses SEED_MODE" do
      System.put_env("SEED_MODE", "bulk")
      opts = Demo.options_from_env()
      System.delete_env("SEED_MODE")

      assert Keyword.get(opts, :mode) == :bulk
    end

    test "parses SEED_COUNTRIES" do
      System.put_env("SEED_COUNTRIES", "es,mx")
      opts = Demo.options_from_env()
      System.delete_env("SEED_COUNTRIES")

      assert Keyword.get(opts, :countries) == ["ES", "MX"]
    end

    test "parses SEED_SCENARIO" do
      System.put_env("SEED_SCENARIO", "dashboard")
      opts = Demo.options_from_env()
      System.delete_env("SEED_SCENARIO")

      assert Keyword.get(opts, :scenario) == :dashboard
    end

    test "ignores invalid SEED_MODE" do
      System.put_env("SEED_MODE", "invalid")
      opts = Demo.options_from_env()
      System.delete_env("SEED_MODE")

      refute Keyword.has_key?(opts, :mode)
    end
  end

  describe "print_credentials/0" do
    test "prints credentials without error" do
      output = ExUnit.CaptureIO.capture_io(fn -> Demo.print_credentials() end)

      assert output =~ "Demo Credentials"
      assert output =~ "Admin UI password"
      assert output =~ "READ API token"
      assert output =~ "UPDATE API token"
    end
  end
end
