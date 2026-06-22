defmodule DebtStalkerWeb.Admin.FilterParams do
  @moduledoc """
  Parses and serializes admin filter query parameters for LiveView routes.

  Keeps URL state as the single source of truth for country, status, date range,
  sorting, and pagination. Supports both cursor pagination (used by the full
  applications list) and offset pagination (used by the dashboard preview).
  """

  @allowed_sort_fields ~w(application_date full_name requested_amount country status)
  @default_sort_by "application_date"
  @default_sort_dir "desc"

  @doc "Builds a filter map from URL or form parameters."
  @spec from_params(map()) :: map()
  def from_params(params) when is_map(params) do
    %{
      country: blank_to_nil(params["country"]),
      status: blank_to_nil(params["status"]),
      date_from: parse_date(params["date_from"]),
      date_to: parse_date(params["date_to"]),
      sort_by: valid_sort_by(params["sort_by"]),
      sort_dir: valid_sort_dir(params["sort_dir"]),
      cursor: blank_to_nil(params["cursor"]),
      limit: parse_positive_int(params["limit"]),
      page: parse_positive_int(params["page"]),
      per_page: parse_positive_int(params["per_page"])
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @doc "Serializes filters into a query string map for `push_patch`."
  @spec to_query(map()) :: map()
  def to_query(filters) when is_map(filters) do
    %{}
    |> put_query("country", Map.get(filters, :country))
    |> put_query("status", Map.get(filters, :status))
    |> put_query("date_from", format_date(Map.get(filters, :date_from)))
    |> put_query("date_to", format_date(Map.get(filters, :date_to)))
    |> put_query("sort_by", Map.get(filters, :sort_by))
    |> put_query("sort_dir", Map.get(filters, :sort_dir))
    |> put_query("cursor", Map.get(filters, :cursor))
    |> put_query("limit", Map.get(filters, :limit))
    |> put_query("page", Map.get(filters, :page))
    |> put_query("per_page", Map.get(filters, :per_page))
  end

  @doc "Formats a date for HTML date inputs."
  @spec format_date_for_input(Date.t() | nil) :: String.t() | nil
  def format_date_for_input(nil), do: nil
  def format_date_for_input(%Date{} = date), do: Date.to_iso8601(date)

  @doc "Toggles sort direction when the same column is selected again."
  @spec toggle_sort(map(), String.t()) :: map()
  def toggle_sort(filters, field) when field in @allowed_sort_fields do
    current_by = Map.get(filters, :sort_by, @default_sort_by)
    current_dir = Map.get(filters, :sort_dir, @default_sort_dir)

    next_dir =
      if current_by == field and current_dir == "desc" do
        "asc"
      else
        "desc"
      end

    filters
    |> Map.put(:sort_by, field)
    |> Map.put(:sort_dir, next_dir)
    |> Map.delete(:cursor)
    |> Map.delete(:page)
  end

  def toggle_sort(filters, _field), do: filters

  @doc "Returns the list of allowed sort fields."
  @spec allowed_sort_fields() :: [String.t()]
  def allowed_sort_fields, do: @allowed_sort_fields

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp blank_to_nil(value), do: value

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp parse_date(%Date{} = date), do: date
  defp parse_date(_), do: nil

  defp valid_sort_by(field) when field in @allowed_sort_fields, do: field
  defp valid_sort_by(_), do: nil

  defp valid_sort_dir("asc"), do: "asc"
  defp valid_sort_dir("desc"), do: "desc"
  defp valid_sort_dir(_), do: nil

  defp parse_positive_int(nil), do: nil
  defp parse_positive_int(""), do: nil

  defp parse_positive_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp parse_positive_int(value) when is_integer(value) and value > 0, do: value
  defp parse_positive_int(_), do: nil

  defp format_date(nil), do: nil
  defp format_date(%Date{} = date), do: Date.to_iso8601(date)
  defp format_date(value), do: value

  defp put_query(query, _key, nil), do: query
  defp put_query(query, _key, ""), do: query
  defp put_query(query, key, value), do: Map.put(query, key, to_string(value))
end
