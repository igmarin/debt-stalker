defmodule DebtStalkerWeb.Api.WebhookController do
  @moduledoc """
  Webhook receiver for provider status confirmations.

  Verifies HMAC-SHA256 signature, stores a metadata-only event record, and
  enqueues processing. Raw provider payloads are never persisted.
  """

  use DebtStalkerWeb, :controller

  require Logger

  alias DebtStalker.Notifications
  alias DebtStalker.Workers.WebhookProcessingWorker

  plug DebtStalkerWeb.Plugs.RateLimit, [key: :webhook] when action == :receive_webhook

  @doc "Receives, verifies, and enqueues a provider webhook event."
  @spec receive_webhook(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def receive_webhook(conn, params) do
    with :ok <- verify_signature(conn),
         :ok <- check_idempotency(params) do
      store_and_process(conn, params)
    else
      {:error, :invalid_signature} ->
        conn |> put_status(401) |> json(%{error: "invalid_signature"})

      {:error, :duplicate} ->
        conn |> put_status(200) |> json(%{status: "already_processed"})
    end
  end

  defp verify_signature(conn) do
    signature = get_req_header(conn, "x-webhook-signature") |> List.first()
    webhook_secret = Application.fetch_env!(:debt_stalker, :webhook_secret)

    if signature do
      body = conn.assigns[:raw_body] || ""
      expected = :crypto.mac(:hmac, :sha256, webhook_secret, body) |> Base.encode16(case: :lower)

      if Plug.Crypto.secure_compare(signature, expected) do
        :ok
      else
        {:error, :invalid_signature}
      end
    else
      if require_webhook_signature?() do
        {:error, :invalid_signature}
      else
        :ok
      end
    end
  end

  defp require_webhook_signature? do
    Application.get_env(:debt_stalker, :require_webhook_signature, false)
  end

  defp check_idempotency(params) do
    payload_hash = hash_payload(params)

    if Notifications.webhook_event_exists?(payload_hash) do
      {:error, :duplicate}
    else
      :ok
    end
  end

  defp store_and_process(conn, params) do
    app_id = params["application_id"]
    payload_hash = hash_payload(params)

    Logger.info("Webhook received",
      application_id: app_id,
      status: params["status"]
    )

    # General provider messages without an application_id are accepted but do
    # not create a webhook_events row (the table requires application_id) and do
    # not enqueue processing.
    case validate_optional_uuid(app_id) do
      {:error, :invalid_uuid} ->
        conn |> put_status(422) |> json(%{error: "invalid_application_id"})

      {:ok, validated_id} ->
        case record_event(validated_id, params, payload_hash) do
          {:error, %Ecto.Changeset{} = changeset} ->
            Logger.warning("Webhook event storage failed",
              error_message: inspect(changeset.errors)
            )

            conn |> put_status(422) |> json(%{error: "invalid_payload"})

          {:ok, _event} ->
            enqueue_processing(validated_id, params["status"])
            conn |> put_status(200) |> json(%{received: true})

          :ok ->
            enqueue_processing(validated_id, params["status"])
            conn |> put_status(200) |> json(%{received: true})
        end
    end
  end

  defp validate_optional_uuid(nil), do: {:ok, nil}

  defp validate_optional_uuid(app_id) when is_binary(app_id) do
    case Ecto.UUID.cast(app_id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_uuid}
    end
  end

  defp record_event(nil, _params, _payload_hash), do: :ok

  defp record_event(app_id, params, payload_hash) do
    Notifications.record_webhook_event(%{
      application_id: app_id,
      source: params["source"] || "provider",
      payload_hash: payload_hash,
      verified: true,
      processed: false
    })
  end

  defp enqueue_processing(nil, _status), do: :ok

  defp enqueue_processing(app_id, status) when is_binary(app_id) and is_binary(status) do
    %{application_id: app_id, status: status, triggered_by: "webhook"}
    |> WebhookProcessingWorker.new()
    |> Oban.insert()

    :ok
  end

  defp enqueue_processing(_app_id, _status), do: :ok

  defp hash_payload(params) do
    :crypto.hash(:sha256, Jason.encode!(params)) |> Base.encode16(case: :lower)
  end
end
