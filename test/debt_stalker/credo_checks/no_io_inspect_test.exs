defmodule DebtStalker.CredoChecks.NoIOInspectTest do
  use Credo.Test.Case

  alias DebtStalker.CredoChecks.NoIOInspect

  @described_check NoIOInspect

  setup_all do
    Application.ensure_all_started(:credo)
    :ok
  end

  test "flags IO.inspect direct call" do
    source = """
    defmodule DebtStalker.SomeModule do
      def debug(data) do
        IO.inspect(data)
      end
    end
    """

    source
    |> to_source_file("lib/debt_stalker/some_module.ex")
    |> run_check(@described_check)
    |> assert_issue()
  end

  test "flags piped IO.inspect" do
    source = """
    defmodule DebtStalker.SomeModule do
      def debug(data) do
        data |> IO.inspect()
      end
    end
    """

    source
    |> to_source_file("lib/debt_stalker/some_module.ex")
    |> run_check(@described_check)
    |> assert_issue()
  end

  test "does NOT flag test files" do
    source = """
    defmodule DebtStalker.SomeTest do
      def debug(data) do
        IO.inspect(data)
      end
    end
    """

    source
    |> to_source_file("test/debt_stalker/some_test.exs")
    |> run_check(@described_check)
    |> refute_issues()
  end

  test "does NOT flag comments mentioning IO.inspect" do
    source = """
    defmodule DebtStalker.SomeModule do
      # Do not use IO.inspect(x) here
      def clean_code, do: :ok
    end
    """

    source
    |> to_source_file("lib/debt_stalker/some_module.ex")
    |> run_check(@described_check)
    |> refute_issues()
  end

  test "does NOT flag code without IO.inspect" do
    source = """
    defmodule DebtStalker.SomeModule do
      def clean_code, do: :ok
    end
    """

    source
    |> to_source_file("lib/debt_stalker/some_module.ex")
    |> run_check(@described_check)
    |> refute_issues()
  end
end
