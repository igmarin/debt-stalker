defmodule DebtStalker.Countries.DniNie do
  @moduledoc """
  Robust validator for Spanish DNI and NIE.

  - DNI: 8 digits (leading zeros allowed/padded) + control letter.
  - NIE: X/Y/Z + 7 digits + control letter.
  - Modulo 23 control digit using the official letter sequence.
  - Always returns structured error atoms.
  - Pure functions.

  ## Future hardening
  See https://github.com/igmarin/debt-stalker/issues/122 for ongoing work on
  hardening document rules while staying DRY + YAGNI and keeping the design
  extensible for other countries.
  """

  @dni_letters "TRWAGMYFPDXBNJZSQVHLCKE"

  @type error :: :invalid_length | :regex_mismatch | :bad_control_digit

  @doc """
  Validates a Spanish DNI or NIE string.

  ## Behavior
  - Always sanitizes input (trim + uppercase).
  - DNI: accepts 1-8 digits + letter; pads numeric portion to 8 digits before checksum.
  - NIE: X/Y/Z prefix + 7 digits + letter; maps prefix then treats as 8-digit block for mod 23.

  Returns `:ok` or `{:error, atom()}`.
  """
  @spec validate(String.t(), keyword()) :: :ok | {:error, error()}
  def validate(document, _opts \\ []) when is_binary(document) do
    sanitized = document |> String.trim() |> String.upcase()

    cond do
      dni?(sanitized) ->
        validate_dni(sanitized)

      nie?(sanitized) ->
        validate_nie(sanitized)

      true ->
        {:error, :regex_mismatch}
    end
  end

  defp dni?(s), do: String.match?(s, ~r/^[0-9]{1,8}[TRWAGMYFPDXBNJZSQVHLCKE]$/)
  defp nie?(s), do: String.match?(s, ~r/^[XYZ][0-9]{7}[TRWAGMYFPDXBNJZSQVHLCKE]$/)

  defp validate_dni(sanitized) do
    # Extract the letter and the digit string, pad to 8
    {digits_str, letter} = split_dni_or_nie(sanitized)

    padded = String.pad_leading(digits_str, 8, "0")

    if String.length(padded) != 8 do
      {:error, :invalid_length}
    else
      numeric = String.to_integer(padded)
      expected = String.at(@dni_letters, rem(numeric, 23))

      if letter == expected do
        :ok
      else
        {:error, :bad_control_digit}
      end
    end
  end

  defp validate_nie(sanitized) do
    prefix = String.at(sanitized, 0)
    # 7 digits + letter
    rest = String.slice(sanitized, 1, 8)

    numeric_prefix =
      case prefix do
        "X" -> 0
        "Y" -> 1
        "Z" -> 2
        _ -> 0
      end

    {digits_str, letter} = split_dni_or_nie(rest)
    eight_digit_str = Integer.to_string(numeric_prefix) <> String.pad_leading(digits_str, 7, "0")

    if String.length(eight_digit_str) != 8 do
      {:error, :invalid_length}
    else
      numeric = String.to_integer(eight_digit_str)
      expected = String.at(@dni_letters, rem(numeric, 23))

      if letter == expected do
        :ok
      else
        {:error, :bad_control_digit}
      end
    end
  end

  # Splits "12345678Z" or "2345678L" (after prefix removed for NIE) into {digits_str, letter}
  defp split_dni_or_nie(str) do
    len = String.length(str)
    digits = String.slice(str, 0, len - 1)
    letter = String.at(str, len - 1)
    {digits, letter}
  end
end
