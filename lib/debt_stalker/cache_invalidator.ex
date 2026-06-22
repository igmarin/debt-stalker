defmodule DebtStalker.CacheInvalidator do
  @moduledoc """
  Subscribes to application PubSub events and invalidates the
  corresponding cache entries.

  Listens for `{:status_changed, _}` messages on the
  `applications:list` topic and clears the cached `get_application/1`
  entry for the affected application.
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
  def handle_info({:status_changed, _payload}, state) do
    # Invalidate all app cache entries on any status change.
    # A targeted approach (per-app-id) would require the app_id in
    # the broadcast metadata; since the broadcast on
    # "applications:list" doesn't include app_id, we clear all.
    # The per-app topic broadcast handles targeted invalidation
    # via the direct cache del in update_status/3.
    Cachex.clear(@cache)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
