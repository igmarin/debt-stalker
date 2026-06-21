defmodule DebtStalker.Countries do
  @moduledoc """
  Public context for country-specific rules and lookups.

  This module wraps the country registry and behaviour implementations so that
  web and worker callers do not need to reach into individual country modules.
  """

  alias DebtStalker.Countries.Registry

  @doc """
  Returns a UI placeholder hint for the identity document field of `country_code`.

  Returns an empty string when the country is unknown or does not provide a hint.
  """
  @spec get_document_hint(String.t()) :: String.t()
  def get_document_hint(country_code) when is_binary(country_code) do
    case Registry.lookup(country_code) do
      {:ok, module} -> module.document_hint()
      {:error, :unsupported_country} -> ""
    end
  end
end
