defmodule DebtStalkerWeb.Api.WebhookController do
  @moduledoc """
  Webhook receiver for provider status confirmations.

  Verifies HMAC-SHA256 signature, stores event, and enqueues processing.
  """
  use DebtStalkerWeb, :controller

  import Ecto.Query
  require Logger

  alias DebtStalker.Repo

  @doc "Receives, verifies, and enqueues a provider webhook event."
  @spec receive_webhook(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def receive_webhook(conn, params) do
    with :ok <- verify_signature(conn, params),
         :ok <- check_idempotency(params) do
      store_and_process(conn, params)
    else
      {:error, :invalid_signature} ->
        conn |> put_status(401) |> json(%{error: "invalid_signature"})

      {:error, :duplicate} ->
        conn |> put_status(200) |> json(%{status: "already_processed"})
    end
  end

  defp verify_signature(conn, _params) do
    signature = get_req_header(conn, "x-webhook-signature") |> List.first()
    webhook_secret = Application.get_env(:debt_stalker, :webhook_secret, "dev-webhook-secret")

    if signature do
      body = conn.assigns[:raw_body] || ""
      expected = :crypto.mac(:hmac, :sha256, webhook_secret, body) |> Base.encode16(case: :lower)

      if Plug.Crypto.secure_compare(signature, expected) do
        :ok
      else
        {:error, :invalid_signature}
      end
    else
      # In dev/test without signature, allow passthrough
      if Application.get_env(:debt_stalker, :require_webhook_signature, false) do
        {:error, :invalid_signature}
      else
        :ok
      end
    end
  end

  defp check_idempotency(params) do
    payload_hash = :crypto.hash(:sha256, Jason.encode!(params)) |> Base.encode16(case: :lower)

    exists =
      from(w in "webhook_events",
        where: w.payload_hash == ^payload_hash
      )
      |> Repo.exists?()

    if exists, do: {:error, :duplicate}, else: :ok
  end

  defp store_and_process(conn, params) do
    app_id = params["application_id"]
    payload_hash = :crypto.hash(:sha256, Jason.encode!(params)) |> Base.encode16(case: :lower)

    Logger.info("Webhook received",
      application_id: app_id,
      status: params["status"]
    )

    # Only store webhook_events row if application_id is present (NOT NULL constraint)
    if app_id do
      Repo.insert_all("webhook_events", [
        %{
          id: Ecto.UUID.bingenerate(),
          application_id: Ecto.UUID.dump!(app_id),
          source: params["source"] || "provider",
          payload_hash: payload_hash,
          verified: true,
          processed: false,
          raw_payload: params,
          inserted_at: DateTime.utc_now()
        }
      ])
    end

    # Enqueue processing if application_id + status provided
    if app_id && params["status"] do
      %{
        application_id: app_id,
        status: params["status"],
        triggered_by: "webhook"
      }
      |> DebtStalker.Workers.WebhookProcessingWorker.new()
      |> Oban.insert()
    end

    conn |> put_status(200) |> json(%{received: true})
  end
end
