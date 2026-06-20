defmodule DebtStalkerWeb.Api.ApplicationController do
  @moduledoc """
  API controller for credit applications.

  All endpoints require JWT authentication.
  - GET /api/applications: list (read role)
  - GET /api/applications/:id: get (read role)
  - POST /api/applications: create (update role)
  - PATCH /api/applications/:id/status: update status (update role)
  """
  use DebtStalkerWeb, :controller

  alias DebtStalker.Applications
  alias DebtStalker.Applications.CreditApplication

  plug DebtStalkerWeb.Auth.AuthPlug

  plug DebtStalkerWeb.Auth.RequireRolePlug,
       [role: "update"] when action in [:create, :update_status]

  plug DebtStalkerWeb.Auth.RequireRolePlug, [role: "read"] when action in [:index, :show]

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    filters = build_filters(params)
    result = Applications.list_applications(filters)

    conn
    |> put_status(200)
    |> json(%{
      data: Enum.map(result.entries, &serialize_application/1),
      cursor: result.cursor
    })
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    case Applications.get_application(id) do
      {:ok, app} ->
        conn
        |> put_status(200)
        |> json(%{data: serialize_application(app)})

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "not_found"})
    end
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    attrs = %{
      country: params["country"],
      full_name: params["full_name"],
      identity_document: params["identity_document"],
      requested_amount: to_decimal(params["requested_amount"]),
      monthly_income: to_decimal(params["monthly_income"])
    }

    case Applications.create_application(attrs) do
      {:ok, app} ->
        conn
        |> put_status(201)
        |> json(%{data: serialize_application(app)})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(422)
        |> json(%{errors: format_changeset_errors(changeset)})
    end
  end

  @spec update_status(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update_status(conn, %{"id" => id, "status" => new_status}) do
    triggered_by = conn.assigns[:current_role] || "api"

    case Applications.update_status(id, new_status, triggered_by) do
      {:ok, app} ->
        conn
        |> put_status(200)
        |> json(%{data: serialize_application(app)})

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "not_found"})

      {:error, :invalid_transition} ->
        conn
        |> put_status(422)
        |> json(%{error: "invalid_transition"})
    end
  end

  # Private

  defp build_filters(params) do
    %{}
    |> maybe_put(:country, params["country"])
    |> maybe_put(:status, params["status"])
    |> maybe_put(:limit, parse_int(params["limit"]))
    |> maybe_put(:cursor, params["cursor"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_int(nil), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp to_decimal(nil), do: nil
  defp to_decimal(value) when is_binary(value), do: Decimal.new(value)
  defp to_decimal(value) when is_number(value), do: Decimal.from_float(value * 1.0)

  defp serialize_application(%CreditApplication{} = app) do
    %{
      id: app.id,
      country: app.country,
      full_name: app.full_name,
      identity_document: CreditApplication.redact_document(app.identity_document),
      requested_amount: Decimal.to_string(app.requested_amount),
      monthly_income: Decimal.to_string(app.monthly_income),
      application_date: app.application_date,
      status: app.status,
      additional_review_required: app.additional_review_required,
      provider_summary: app.provider_summary,
      inserted_at: app.inserted_at
    }
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
