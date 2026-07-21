defmodule GesttaltWeb.Router do
  use GesttaltWeb, :router

  import GesttaltWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GesttaltWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :tenant do
    plug GesttaltWeb.HostResolver
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: GesttaltWeb.API.Spec
  end

  pipeline :oauth_json do
    plug :accepts, ["json"]
  end

  pipeline :admin do
    plug :require_authenticated_user
  end

  pipeline :theme_preview do
    plug :put_secure_browser_headers
  end

  scope "/" do
    pipe_through :browser

    get "/docs", GesttaltWeb.PageController, :docs
    get "/legal-notice", GesttaltWeb.PageController, :legal_notice
    get "/privacy", GesttaltWeb.PageController, :privacy
    get "/terms", GesttaltWeb.PageController, :terms
    get "/withdrawal", GesttaltWeb.PageController, :withdrawal
    get "/cancel", GesttaltWeb.PageController, :cancel
    get "/report-illegal-content", GesttaltWeb.PageController, :report_illegal_content
    get "/sitemap.xml", GesttaltWeb.SitemapController, :show
    get "/api-docs", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi"
    get "/agent/identity/claim", GesttaltWeb.AgentClaimController, :show
  end

  scope "/", GesttaltWeb do
    pipe_through :oauth_json

    get "/health", HealthController, :show
    get "/internal/domains/allow", DomainAllowController, :show
    get "/.well-known/oauth-authorization-server", WellKnownController, :authorization_server
    get "/.well-known/openid-configuration", WellKnownController, :authorization_server
    get "/.well-known/oauth-protected-resource", WellKnownController, :protected_resource
    get "/.well-known/oauth-protected-resource/mcp", WellKnownController, :mcp_protected_resource
    get "/.well-known/jwks.json", WellKnownController, :jwks
    get "/.well-known/mcp/server-card.json", WellKnownController, :mcp_server_card
    get "/auth.md", AuthMarkdownController, :show
    post "/agent/identity", AgentIdentityController, :create
  end

  scope "/oauth2", GesttaltWeb.OAuth do
    pipe_through :oauth_json

    post "/token", TokenController, :token
    post "/register", RegistrationController, :register
    post "/introspect", IntrospectController, :introspect
    post "/revoke", RevokeController, :revoke
  end

  scope "/oauth2", GesttaltWeb.OAuth do
    pipe_through :browser

    get "/authorize", AuthorizeController, :authorize
  end

  scope "/webhooks", GesttaltWeb do
    pipe_through :oauth_json
    post "/stripe", BillingController, :webhook
  end

  scope "/admin", GesttaltWeb do
    pipe_through [:browser, :admin]

    get "/", AdminController, :index
    get "/posts/new", AdminController, :new
    post "/posts", AdminController, :create
    get "/posts/:id/edit", AdminController, :edit
    put "/posts/:id", AdminController, :update
    post "/posts/:id/publish", AdminController, :publish
    post "/posts/:id/unpublish", AdminController, :unpublish
    delete "/posts/:id", AdminController, :delete

    get "/media", MediaController, :index
    post "/media", MediaController, :create
    get "/media/:id/:filename", MediaController, :show
    delete "/media/:id", MediaController, :delete

    get "/theme", ThemeController, :edit

    get "/settings", SiteSettingsController, :show
    put "/settings", SiteSettingsController, :update
    post "/domains", SiteSettingsController, :create_domain
    post "/domains/:id/verify", SiteSettingsController, :verify_domain
    delete "/domains/:id", SiteSettingsController, :delete_domain

    get "/oauth-clients", OAuthClientController, :index
    post "/oauth-clients", OAuthClientController, :create
    delete "/oauth-clients/:id", OAuthClientController, :delete

    get "/billing", BillingController, :show
    post "/billing/checkout", BillingController, :checkout
    post "/billing/portal", BillingController, :portal
  end

  scope "/api" do
    pipe_through :api

    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
    get "/posts", GesttaltWeb.ApiPostController, :index
    post "/posts", GesttaltWeb.ApiPostController, :create
    get "/posts/:id", GesttaltWeb.ApiPostController, :show
    patch "/posts/:id", GesttaltWeb.ApiPostController, :update
    put "/posts/:id", GesttaltWeb.ApiPostController, :update
    delete "/posts/:id", GesttaltWeb.ApiPostController, :delete
    post "/posts/:id/publish", GesttaltWeb.ApiPostController, :publish
    post "/posts/:id/unpublish", GesttaltWeb.ApiPostController, :unpublish
    get "/media", GesttaltWeb.ApiMediaController, :index
    post "/media", GesttaltWeb.ApiMediaController, :create
  end

  forward "/mcp", Gesttalt.MCP

  scope "/theme-previews", GesttaltWeb do
    pipe_through :theme_preview

    get "/:session_id/events", ThemePreviewController, :events
    get "/:session_id/media/:id/:filename", ThemePreviewController, :media
    get "/:session_id/blog/:slug", ThemePreviewController, :article
    get "/:session_id/:slug", ThemePreviewController, :page
    get "/:session_id", ThemePreviewController, :home
  end

  if Application.compile_env(:gesttalt, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: GesttaltWeb.Telemetry
      post "/users/log-in-as-test-user", GesttaltWeb.UserSessionController, :test_user
    end
  end

  scope "/", GesttaltWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]
    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", GesttaltWeb do
    pipe_through [:browser, :require_authenticated_user]
    post "/agent/identity/claim", AgentClaimController, :update
    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", GesttaltWeb do
    pipe_through :browser
    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  scope "/", GesttaltWeb do
    pipe_through [:browser, :tenant]
    get "/", SiteController, :home
    get "/blog/feed.xml", FeedController, :index
    get "/blog/:slug", SiteController, :article
    get "/media/:id/:filename", SiteController, :media
    get "/:slug", SiteController, :page
  end
end
