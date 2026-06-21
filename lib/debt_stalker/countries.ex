defmodule DebtStalker.Countries do
  @moduledoc """
  Public context for country-specific rules and lookups.

  This module wraps the country registry and behaviour implementations so that
  web and worker callers do not need to reach into individual country modules.
  """

  alias DebtStalker.Countries.Registry

  @doc """
  Returns a UI placeholder hint for the identity document field of `country_code`.

  Returns an empty string when the country is unknown, does not provide a hint,
  or has not implemented the optional `document_hint/0` callback.
  """
  @spec get_document_hint(String.t() | nil) :: String.t()
  def get_document_hint(nil), do: ""

  def get_document_hint(country_code) when is_binary(country_code) do
    case Registry.lookup(country_code) do
      {:ok, module} ->
        if Code.ensure_loaded?(module) and function_exported?(module, :document_hint, 0) do
          module.document_hint()
        else
          ""
        end

      {:error, :unsupported_country} ->
        ""
    end
  end
end
