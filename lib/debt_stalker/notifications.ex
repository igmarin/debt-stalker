defmodule DebtStalker.Notifications do
  @moduledoc """
  Context for inbound webhooks and outbound notification attempts.

  This module centralizes all webhook/notification persistence so that controllers
  and workers do not reach directly into the database.
  """

  import Ecto.Query

  alias DebtStalker.Notifications.NotificationAttempt
  alias DebtStalker.Notifications.WebhookEvent
  alias DebtStalker.Repo

  @doc """
  Records a verified inbound webhook event.

  Only the payload hash is stored; the raw provider payload is never persisted.
  """
  @spec record_webhook_event(map()) :: {:ok, WebhookEvent.t()} | {:error, Ecto.Changeset.t()}
  def record_webhook_event(attrs) do
    %WebhookEvent{}
    |> WebhookEvent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns whether a webhook event with the given payload hash already exists.
  """
  @spec webhook_event_exists?(String.t()) :: boolean()
  def webhook_event_exists?(payload_hash) when is_binary(payload_hash) do
    WebhookEvent
    |> where([w], w.payload_hash == ^payload_hash)
    |> Repo.exists?()
  end

  @doc """
  Records an outbound notification attempt.
  """
  @spec record_notification_attempt(map()) ::
          {:ok, NotificationAttempt.t()} | {:error, Ecto.Changeset.t()}
  def record_notification_attempt(attrs) do
    %NotificationAttempt{}
    |> NotificationAttempt.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Checks whether a notification of the given type has already been recorded for
  the application. Used by workers to avoid duplicate notifications.
  """
  @spec notification_exists?(Ecto.UUID.t(), String.t()) :: boolean()
  def notification_exists?(application_id, notification_type)
      when is_binary(application_id) and is_binary(notification_type) do
    NotificationAttempt
    |> where(
      [n],
      n.application_id == ^application_id and n.notification_type == ^notification_type
    )
    |> Repo.exists?()
  end
end
