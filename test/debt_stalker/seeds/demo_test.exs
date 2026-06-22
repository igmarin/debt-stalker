defmodule DebtStalker.Seeds.DemoTest do
  use DebtStalker.DataCase, async: false

  alias DebtStalker.Applications.AuditLog
  alias DebtStalker.Applications.CreditApplication
  alias DebtStalker.Applications.StatusTransition
  alias DebtStalker.Repo
  alias DebtStalker.Seeds.Demo

  describe "build_attrs/1" do
    test "returns valid attrs for a supported country" do
      attrs = Demo.build_attrs(country: "ES")

      assert attrs.country == "ES"
      assert is_binary(attrs.full_name)
      assert is_binary(attrs.identity_document)
      assert %Decimal{} = attrs.requested_amount
      assert %Decimal{} = attrs.monthly_income
      assert attrs.status in CreditApplication.valid_statuses()
      assert %DateTime{} = attrs.application_date
    end

    test "picks country from the countries option" do
      attrs = Demo.build_attrs(countries: ["MX"])

      assert attrs.country == "MX"
    end

    test "dashboard scenario skews toward operational statuses" do
      statuses =
        for _ <- 1..50 do
          Demo.build_attrs(scenario: :dashboard).status
        end

      assert "pending_risk" in statuses
      assert "approved" in statuses
      refute statuses == List.duplicate("submitted", 50)
    end
  end

  describe "run/1" do
    test "bulk mode creates the requested number of applications" do
      result = Demo.run(count: 3, mode: :bulk, countries: ["ES"])

      assert result.created == 3
      assert result.failed == 0
      assert result.realistic == 0
      assert Repo.aggregate(CreditApplication, :count, :id) >= 3
    end

    test "realistic mode records status transitions and audit logs" do
      result = Demo.run(count: 1, mode: :realistic, countries: ["ES"])

      assert result.created == 1
      assert result.realistic == 1

      app = Repo.one!(CreditApplication)
      assert app.status in ["approved", "rejected", "pending_risk", "additional_review"]

      assert Repo.aggregate(StatusTransition, :count, :id) >= 1
      assert Repo.aggregate(AuditLog, :count, :id) >= 1
    end

    test "mixed mode creates realistic and bulk records" do
      result = Demo.run(count: 4, mode: :mixed, realistic_count: 2, countries: ["ES"])

      assert result.created == 4
      assert result.realistic == 2
      assert result.bulk == 2
    end
  end

  describe "create_realistic/1" do
    test "walks applications to the requested terminal status" do
      assert {:ok, app} = Demo.create_realistic(country: "ES", target_status: "approved")
      assert app.status == "approved"

      transitions =
        StatusTransition
        |> Repo.all()
        |> Enum.map(& &1.to_status)

      assert "pending_risk" in transitions
      assert "approved" in transitions
    end
  end

  describe "options_from_env/0" do
    test "reads count and mode from environment variables" do
      System.put_env("SEED_COUNT", "12")
      System.put_env("SEED_MODE", "mixed")
      System.put_env("SEED_REALISTIC_COUNT", "4")

      on_exit(fn ->
        System.delete_env("SEED_COUNT")
        System.delete_env("SEED_MODE")
        System.delete_env("SEED_REALISTIC_COUNT")
      end)

      opts = Demo.options_from_env()

      assert Keyword.get(opts, :count) == 12
      assert Keyword.get(opts, :mode) == :mixed
      assert Keyword.get(opts, :realistic_count) == 4
    end
  end
end
