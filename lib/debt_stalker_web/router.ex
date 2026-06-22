defmodule DebtStalkerWeb.Router do
  @moduledoc """
  HTTP router for DebtStalker.

  Defines browser and API pipelines, LiveView routes, REST endpoints,
  and dev-only tooling such as LiveDashboard.
  """

  use DebtStalkerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DebtStalkerWeb.Layouts, :root}
    plug DebtStalkerWeb.Plugs.AssignRole
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", DebtStalkerWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/set-role", PageController, :set_role

    get "/admin/login", PageController, :login
    post "/admin/login", PageController, :do_login
    get "/admin/logout", PageController, :logout

    # Legacy routes — redirect to the new persona-aware paths
    get "/applications", PageController, :redirect_applications
    get "/applications/new", PageController, :redirect_new_application
    get "/applications/:id", PageController, :redirect_application_detail

    live "/apply", Apply.ApplicationFormLive
    live "/apply/:id/confirmation", Apply.ApplicationConfirmationLive

    live "/admin", Admin.DashboardLive
    live "/admin/applications", Admin.ApplicationsLive
    live "/admin/applications/:id", Admin.ApplicationDetailLive
  end

  scope "/api", DebtStalkerWeb.Api do
    pipe_through :api

    get "/health", HealthController, :index

    post "/auth/token", AuthController, :create

    get "/applications", ApplicationController, :index
    get "/applications/:id", ApplicationController, :show
    post "/applications", ApplicationController, :create
    patch "/applications/:id/status", ApplicationController, :update_status

    post "/webhooks/provider-confirmations", WebhookController, :receive_webhook
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
