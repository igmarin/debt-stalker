defmodule DebtStalker.CredoChecks.NoIOInspect do
  @moduledoc """
  Custom Credo check that forbids `IO.inspect/1,2` calls in project code.

  Catches direct calls and piped usage. Test files and this check's own
  source are excluded to avoid false positives.
  """
  use Credo.Check,
    id: "EX9003",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      `IO.inspect` calls must not be committed. Use structured logging
      via `Logger` with proper metadata instead (AGENTS.md §6).
      """
    ]

  @doc false
  @impl true
  @spec run(Credo.SourceFile.t(), list()) :: list()
  def run(%Credo.SourceFile{} = source_file, _params) do
    filename = source_file.filename

    if skip_file?(filename) do
      []
    else
      source_file
      |> Credo.SourceFile.source()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_no} ->
        check_line(source_file, line, line_no)
      end)
    end
  end

  defp skip_file?(filename) do
    test_path?(filename) or String.contains?(filename, "credo_checks")
  end

  defp test_path?(filename) do
    String.contains?(filename, "/test/") or String.starts_with?(filename, "test/")
  end

  defp check_line(source_file, line, line_no) do
    trimmed = String.trim(line)

    cond do
      String.starts_with?(trimmed, "#") -> []
      String.starts_with?(trimmed, "@moduledoc") -> []
      String.starts_with?(trimmed, "@doc") -> []
      contains_io_inspect_call?(line) -> [issue_for(source_file, line_no)]
      true -> []
    end
  end

  defp contains_io_inspect_call?(line) do
    Regex.match?(~r/\bIO\.inspect\s*\(/, line) or
      Regex.match?(~r/\|>\s*IO\.inspect/, line)
  end

  defp issue_for(source_file, line_no) do
    format_issue(
      source_file,
      message: "IO.inspect found — use Logger with structured metadata instead.",
      line_no: line_no
    )
  end
end
