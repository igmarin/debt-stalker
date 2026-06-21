defmodule DebtStalker.CredoChecks.NoCountryBranching do
  @moduledoc """
  Custom Credo check that prevents country/provider-specific branching
  outside of `DebtStalker.Countries` and `DebtStalker.Providers` contexts.

  The architecture contract (AGENTS.md §3.2) forbids patterns like
  `if country == "ES"` or `"ES" ->` case arms outside the designated modules.
  This check enforces that contract at lint time.
  """
  use Credo.Check,
    id: "EX9001",
    base_priority: :high,
    category: :design,
    param_defaults: [
      country_codes: ["ES", "MX", "PT", "IT", "CO", "BR"]
    ],
    explanations: [
      check: """
      Country/provider-specific branching must live in `DebtStalker.Countries`
      or `DebtStalker.Providers` modules. Branching on country codes or provider
      names elsewhere violates the Code Org Contract (AGENTS.md §3.2).
      """,
      params: [
        country_codes: "List of known country codes to detect in branching patterns."
      ]
    ]

  @doc false
  @impl true
  @spec run(Credo.SourceFile.t(), list()) :: list()
  def run(%Credo.SourceFile{} = source_file, params) do
    filename = source_file.filename

    if allowed_module?(filename) do
      []
    else
      country_codes = Params.get(params, :country_codes, __MODULE__)

      source_file
      |> Credo.SourceFile.source()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(&check_line(source_file, &1, country_codes))
    end
  end

  defp allowed_module?(filename) do
    String.contains?(filename, "countries") or
      String.contains?(filename, "providers") or
      String.contains?(filename, "credo_checks") or
      test_path?(filename)
  end

  defp test_path?(filename) do
    String.contains?(filename, "/test/") or String.starts_with?(filename, "test/")
  end

  defp check_line(source_file, {line, line_no}, country_codes) do
    trimmed = String.trim(line)

    if skip_line?(trimmed) do
      []
    else
      detect_country_branching(source_file, line, line_no, country_codes)
    end
  end

  defp skip_line?(line) do
    String.starts_with?(line, "#") or
      String.starts_with?(line, "@moduledoc") or
      String.starts_with?(line, "@doc")
  end

  defp detect_country_branching(source_file, line, line_no, country_codes) do
    country_codes
    |> Enum.filter(&country_code_in_branching_context?(&1, line))
    |> Enum.map(&issue_for(source_file, line_no, &1))
  end

  defp country_code_in_branching_context?(code, line) do
    quoted = "\"#{code}\""

    String.contains?(line, quoted) and branching_context?(line, quoted)
  end

  defp branching_context?(line, quoted) do
    Regex.match?(~r/(case|cond|if|when)\b/, line) or
      String.contains?(line, "#{quoted} ->") or
      String.contains?(line, "== #{quoted}") or
      String.contains?(line, "!= #{quoted}")
  end

  defp issue_for(source_file, line_no, country_code) do
    format_issue(
      source_file,
      message:
        "Country-specific branching on \"#{country_code}\" found outside Countries/Providers context.",
      line_no: line_no
    )
  end
end
