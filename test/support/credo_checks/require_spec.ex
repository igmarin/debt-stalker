defmodule DebtStalker.CredoChecks.RequireSpec do
  @moduledoc """
  Custom Credo check that requires `@spec` on every public function.

  The project convention (AGENTS.md §3.3) mandates that every public function
  has `@doc` and `@spec`. This check enforces the `@spec` requirement.

  Excludes OTP/Phoenix callbacks, test files, generated components,
  and support modules. Handles multi-clause functions correctly.
  """
  use Credo.Check,
    id: "EX9002",
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Every public function must have a `@spec` type annotation.
      This is required by the project convention (AGENTS.md §3.3).
      """
    ]

  @excluded_functions ~w(
    handle_call handle_cast handle_info handle_continue handle_event
    mount render update terminate init start_link child_spec perform
    translate_errors translate_error errors_on setup_sandbox
    flash modal button input header table list icon show hide
  )

  @non_function_defs ~w(defp defmodule defmacro defguard defdelegate defstruct defimpl defprotocol defoverridable defexception)

  @doc false
  @impl true
  @spec run(Credo.SourceFile.t(), list()) :: list()
  def run(%Credo.SourceFile{} = source_file, _params) do
    filename = source_file.filename

    if skip_file?(filename) do
      []
    else
      source = Credo.SourceFile.source(source_file)
      find_public_functions_without_spec(source_file, source)
    end
  end

  defp skip_file?(filename) do
    test_path?(filename) or
      String.contains?(filename, "core_components") or
      String.contains?(filename, "credo_checks")
  end

  defp test_path?(filename) do
    String.contains?(filename, "/test/") or String.starts_with?(filename, "test/")
  end

  defp find_public_functions_without_spec(source_file, source) do
    lines = String.split(source, "\n")
    spec_names = collect_spec_names(lines)

    lines
    |> Enum.with_index(1)
    |> Enum.reduce({MapSet.new(), []}, &process_line(&1, &2, source_file, spec_names))
    |> elem(1)
    |> Enum.reverse()
  end

  defp process_line({line, line_no}, {seen_names, issues}, source_file, spec_names) do
    trimmed = String.trim(line)

    if public_function_def?(trimmed) do
      check_function(trimmed, line_no, seen_names, issues, source_file, spec_names)
    else
      {seen_names, issues}
    end
  end

  defp check_function(trimmed, line_no, seen_names, issues, source_file, spec_names) do
    func_name = extract_function_name(trimmed)

    if skip_function?(func_name, spec_names, seen_names) do
      {MapSet.put(seen_names, func_name), issues}
    else
      issue = issue_for(source_file, line_no, func_name)
      {MapSet.put(seen_names, func_name), [issue | issues]}
    end
  end

  defp skip_function?(func_name, spec_names, seen_names) do
    func_name in @excluded_functions or
      func_name in spec_names or
      MapSet.member?(seen_names, func_name)
  end

  defp collect_spec_names(lines) do
    Enum.reduce(lines, MapSet.new(), &extract_spec_name/2)
  end

  defp extract_spec_name(line, acc) do
    trimmed = String.trim(line)

    case parse_spec_name(trimmed) do
      nil -> acc
      name -> MapSet.put(acc, name)
    end
  end

  defp parse_spec_name("@spec " <> rest) do
    case Regex.run(~r/^([a-z_][a-z0-9_?!]*)/, rest) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp parse_spec_name(_), do: nil

  defp public_function_def?(line) do
    String.match?(line, ~r/^def\s+[a-z_]/) and
      not Enum.any?(@non_function_defs, &String.starts_with?(line, &1))
  end

  defp extract_function_name(line) do
    case Regex.run(~r/def\s+([a-z_][a-z0-9_?!]*)/, line) do
      [_, name] -> name
      _ -> "unknown"
    end
  end

  defp issue_for(source_file, line_no, func_name) do
    format_issue(
      source_file,
      message: "Public function `#{func_name}` is missing a @spec annotation.",
      line_no: line_no
    )
  end
end
