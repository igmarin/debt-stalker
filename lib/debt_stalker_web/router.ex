defmodule DebtStalkerWeb.Router do
  use DebtStalkerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DebtStalkerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", DebtStalkerWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/applications", ApplicationsLive
    live "/applications/new", ApplicationCreateLive
    live "/applications/:id", ApplicationDetailLive
  end

  scope "/api", DebtStalkerWeb.Api do
    pipe_through :api

    post "/auth/token", AuthController, :create

    get "/applications", ApplicationController, :index
    get "/applications/:id", ApplicationController, :show
    post "/applications", ApplicationController, :create
    patch "/applications/:id/status", ApplicationController, :update_status

    post "/webhooks/provider", WebhookController, :receive_webhook
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:debt_stalker, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DebtStalkerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
