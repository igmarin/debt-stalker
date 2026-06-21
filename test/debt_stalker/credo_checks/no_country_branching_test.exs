defmodule DebtStalker.CredoChecks.NoCountryBranchingTest do
  use Credo.Test.Case

  alias DebtStalker.CredoChecks.NoCountryBranching

  @described_check NoCountryBranching

  setup_all do
    Application.ensure_all_started(:credo)
    :ok
  end

  test "does NOT flag branching inside countries module" do
    source = """
    defmodule DebtStalker.Countries.ES do
      def evaluate(country) do
        case country do
          "ES" -> :ok
        end
      end
    end
    """

    source
    |> to_source_file("lib/debt_stalker/countries/es.ex")
    |> run_check(@described_check)
    |> refute_issues()
  end

  test "does NOT flag branching inside providers module" do
    source = """
    defmodule DebtStalker.Providers.ESAdapter do
      def call(country) do
        if country == "ES", do: :ok
      end
    end
    """

    source
    |> to_source_file("lib/debt_stalker/providers/es_adapter.ex")
    |> run_check(@described_check)
    |> refute_issues()
  end

  test "flags country branching in domain modules" do
    source = """
    defmodule DebtStalker.Risk do
      def threshold(country) do
        case country do
          "ES" -> 650
        end
      end
    end
    """

    source
    |> to_source_file("lib/debt_stalker/risk.ex")
    |> run_check(@described_check)
    |> assert_issue()
  end

  test "flags branching with if on country code" do
    source = """
    defmodule DebtStalker.SomeModule do
      def check(country) do
        if country == "MX", do: :ok
      end
    end
    """

    source
    |> to_source_file("lib/debt_stalker/some_module.ex")
    |> run_check(@described_check)
    |> assert_issue()
  end

  test "does NOT flag when no country code in branching" do
    source = """
    defmodule DebtStalker.Risk do
      def check(status) do
        case status do
          "approved" -> :ok
          _ -> :error
        end
      end
    end
    """

    source
    |> to_source_file("lib/debt_stalker/risk.ex")
    |> run_check(@described_check)
    |> refute_issues()
  end
end
