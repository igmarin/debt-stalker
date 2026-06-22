defmodule DebtStalker.CacheInvalidator do
  @moduledoc """
  Subscribes to application PubSub events and invalidates the
  corresponding cache entries.

  Listens for `{:status_changed, _}` messages on the
  `applications:list` topic and deletes the cached
  `get_application/1` entry for the affected application.

  ## PII Note

  The cache stores the full `CreditApplication` struct, which
  includes PII fields (`full_name`, `identity_document`). This is
  the same decrypted data that is already in process memory after
  `Repo.get/2` — Cloak decrypts at the Ecto layer. The encryption
  at rest requirement (invariant #3) applies to the database
  storage layer, not to in-memory caches. The cache is ephemeral,
  BEAM-isolated, and not accessible externally.
  """

  use GenServer

  @cache :app_cache
  @pubsub DebtStalker.PubSub
  @topic "applications:list"

  @doc "Starts the cache invalidator process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts) do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
    {:ok, %{}}
  end

  @impl GenServer
  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info({:status_changed, %{application_id: app_id}}, state) do
    # Targeted invalidation: delete only the affected app's cache entry.
    Cachex.del(@cache, "app:#{app_id}")
    {:noreply, state}
  end

  def handle_info({:status_changed, _payload}, state) do
    # Fallback: if app_id is not in the payload, clear all.
    Cachex.clear(@cache)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
