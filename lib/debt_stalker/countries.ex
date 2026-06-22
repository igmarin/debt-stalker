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

  @doc """
  Generates a random identity document for `country_code` suitable for demo/seed data.

  Returns `nil` for unknown countries or countries that do not implement the
  optional `random_identity_document/0` callback.
  """
  @spec random_identity_document(String.t()) :: String.t() | nil
  def random_identity_document(country_code) when is_binary(country_code) do
    case Registry.lookup(country_code) do
      {:ok, module} ->
        if Code.ensure_loaded?(module) and
             function_exported?(module, :random_identity_document, 0) do
          module.random_identity_document()
        else
          nil
        end

      {:error, :unsupported_country} ->
        nil
    end
  end
end
