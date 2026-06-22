defmodule DebtStalker.Countries.Curp do
  @moduledoc """
  Robust, self-contained validator for Mexican CURP (Clave Única de Registro de Población).

  Implements the full rules specified for pre-validation:
  - Exact 18 alphanumeric (after sanitization)
  - Official RENAPO regex for syntax
  - Position-by-position structural validation
  - Realistic calendar date from YYMMDD + century differentiator
  - Optional `birth_date` cross-validation (virtual attribute)
  - Returns structured error atoms for precise feedback.

  This is a pure library module — no side effects, no DB, no web.

  ## Future hardening
  See https://github.com/igmarin/debt-stalker/issues/122 for ongoing work on
  hardening document rules while staying DRY + YAGNI and keeping the design
  extensible for other countries.
  """

  @official_regex ~r/^[A-Z]{1}[AEIOUX]{1}[A-Z]{2}[0-9]{2}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])[HM]{1}(AS|BC|BS|CC|CH|CL|CM|CS|DF|DG|GR|GT|HG|JC|MC|MN|MS|NT|NL|OC|PL|QT|QR|SP|SL|SR|TC|TS|TL|VZ|YN|ZS|NE)[B-DF-HJ-NP-TV-Z]{3}[0-9A-Z]{1}[0-9]{1}$/

  @valid_states ~w(
    AS BC BS CC CH CL CM CS DF DG GR GT HG JC MC MN MS NT NL OC PL QT QR SP SL SR TC TS TL VZ YN ZS NE
  )

  @gender ~w(H M)

  @type error ::
          :invalid_length
          | :regex_mismatch
          | :invalid_date
          | :invalid_gender
          | :invalid_state_code
          | :birth_date_mismatch

  @doc """
  Validates a CURP string according to the strict business rules.

  ## Options
  - `:birth_date` — optional `Date.t()` supplied as a virtual attribute from forms/API
    to cross-validate the date of birth encoded in positions 5-10 + century code at 17.

  Returns `:ok` or `{:error, atom()}` (see `@type error`).

  This function is the single source of truth for CURP pre-validation before any
  provider call.
  """
  @spec validate(String.t(), keyword()) :: :ok | {:error, error()}
  def validate(document, opts \\ []) when is_binary(document) do
    sanitized = document |> String.trim() |> String.upcase()

    with :ok <- validate_length(sanitized),
         :ok <- validate_regex(sanitized),
         :ok <- validate_components(sanitized) do
      validate_birth_date_match(sanitized, Keyword.get(opts, :birth_date))
    end
  end

  # --- private ---

  defp validate_length(curp) do
    if String.length(curp) == 18 do
      :ok
    else
      {:error, :invalid_length}
    end
  end

  defp validate_regex(curp) do
    if String.match?(curp, @official_regex) do
      :ok
    else
      {:error, :regex_mismatch}
    end
  end

  defp validate_components(curp) do
    # Positions are 0-indexed in Elixir strings.
    # Note: century and final check digit are already enforced by @official_regex.
    # Only gender, state, and realistic date need explicit checks here for better error atoms.
    gender = String.at(curp, 10)
    state = String.slice(curp, 11, 2)

    with :ok <- validate_gender(gender),
         :ok <- validate_state(state) do
      validate_date_segment(curp)
    end
  end

  defp validate_gender(gender) when gender in @gender, do: :ok
  defp validate_gender(_), do: {:error, :invalid_gender}

  defp validate_state(state) do
    if state in @valid_states do
      :ok
    else
      {:error, :invalid_state_code}
    end
  end

  defp validate_date_segment(curp) do
    yy = String.slice(curp, 4, 2) |> String.to_integer()
    mm = String.slice(curp, 6, 2) |> String.to_integer()
    dd = String.slice(curp, 8, 2) |> String.to_integer()
    century_char = String.at(curp, 16)

    year =
      case century_char do
        <<c>> when c in ?0..?9 ->
          1900 + yy

        <<c>> when c in ?A..?Z ->
          2000 + yy

        # letter A-Z means 2000+ (spec); letter value itself ignored for year.

        _ ->
          1900 + yy
      end

    case Date.new(year, mm, dd) do
      {:ok, _date} -> :ok
      {:error, _} -> {:error, :invalid_date}
    end
  end

  defp validate_birth_date_match(_curp, nil), do: :ok

  defp validate_birth_date_match(curp, %Date{} = provided) do
    yy = String.slice(curp, 4, 2) |> String.to_integer()
    mm = String.slice(curp, 6, 2) |> String.to_integer()
    dd = String.slice(curp, 8, 2) |> String.to_integer()
    century_char = String.at(curp, 16)

    year =
      case century_char do
        <<c>> when c in ?0..?9 ->
          1900 + yy

        <<c>> when c in ?A..?Z ->
          2000 + yy

        # letter A-Z means 2000+ (spec); letter value itself ignored for year.

        _ ->
          1900 + yy
      end

    case Date.new(year, mm, dd) do
      {:ok, curp_date} ->
        if Date.compare(curp_date, provided) == :eq do
          :ok
        else
          {:error, :birth_date_mismatch}
        end

      {:error, _} ->
        {:error, :invalid_date}
    end
  end

  defp validate_birth_date_match(_, _), do: {:error, :birth_date_mismatch}
end
