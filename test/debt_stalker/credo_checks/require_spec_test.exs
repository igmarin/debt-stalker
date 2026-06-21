defmodule DebtStalker.CredoChecks.RequireSpecTest do
  use Credo.Test.Case

  alias DebtStalker.CredoChecks.RequireSpec

  @described_check RequireSpec

  setup_all do
    Application.ensure_all_started(:credo)
    :ok
  end

  test "does NOT flag function with @spec" do
    source = """
    defmodule DebtStalker.SomeModule do
      @spec greet(String.t()) :: String.t()
      def greet(name), do: "Hello \#{name}"
    end
    """

    source
    |> to_source_file("lib/debt_stalker/some_module.ex")
    |> run_check(@described_check)
    |> refute_issues()
  end

  test "flags public function without @spec" do
    source = """
    defmodule DebtStalker.SomeModule do
      def greet(name), do: "Hello \#{name}"
    end
    """

    source
    |> to_source_file("lib/debt_stalker/some_module.ex")
    |> run_check(@described_check)
    |> assert_issue()
  end

  test "does NOT flag private functions" do
    source = """
    defmodule DebtStalker.SomeModule do
      defp internal(x), do: x
    end
    """

    source
    |> to_source_file("lib/debt_stalker/some_module.ex")
    |> run_check(@described_check)
    |> refute_issues()
  end

  test "does NOT flag test files" do
    source = """
    defmodule DebtStalker.SomeTest do
      def helper(x), do: x
    end
    """

    source
    |> to_source_file("test/debt_stalker/some_test.exs")
    |> run_check(@described_check)
    |> refute_issues()
  end

  test "does NOT flag OTP callbacks" do
    source = """
    defmodule DebtStalker.SomeServer do
      def init(opts), do: {:ok, opts}
      def handle_call(msg, _from, state), do: {:reply, msg, state}
    end
    """

    source
    |> to_source_file("lib/debt_stalker/some_server.ex")
    |> run_check(@described_check)
    |> refute_issues()
  end

  test "handles multi-clause functions with @spec on first clause" do
    source = """
    defmodule DebtStalker.SomeModule do
      @spec process(String.t()) :: :ok | :error
      def process("yes"), do: :ok
      def process(_), do: :error
    end
    """

    source
    |> to_source_file("lib/debt_stalker/some_module.ex")
    |> run_check(@described_check)
    |> refute_issues()
  end
end
