defmodule FrontendExWeb.Router do
  use FrontendExWeb, :router

  import Phoenix.LiveDashboard.Router

  # Sessions/CSRF are intentionally avoided for parity SSR routes (see :fast_browser),
  # but we keep a working :browser pipeline for future non-parity pages.
  #
  # The signing salt is read from config (compile-time). For prod,
  # `config/prod.exs` requires the `SESSION_SIGNING_SALT` env var at build time.
  @session_options [
    store: :cookie,
    key: "_frontend_ex_key",
    signing_salt:
      Application.compile_env(:frontend_ex, :session_signing_salt, "dev-only-not-for-prod"),
    same_site: "Lax"
  ]

  pipeline :browser do
    plug :accepts, ["html"]
    plug Plug.Session, @session_options
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FrontendExWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # Fast-frontend parity routes: SSR HTML with skin-specific root layouts.
  #
  # Intentionally does not include sessions/CSRF protection to avoid extra
  # HTML/meta tags and keep output byte-for-byte compatible with Rust.
  pipeline :fast_browser do
    plug :accepts, ["html"]
    plug FrontendExWeb.Plugs.FastLayout
    plug :put_layout, false
    plug :put_secure_browser_headers
    plug FrontendExWeb.Plugs.TrimTrailingNewline
  end

  # 2d-fork: removed `:fast_csv` pipeline — its only consumer was the
  # NFT-CSV export, which 2d does not surface.

  # Standalone HTML documents (no root layout). Used for share cards that are
  # full HTML pages and should not be wrapped by the skin layout.
  pipeline :fast_plain_html do
    plug :accepts, ["html"]
    plug :put_root_layout, false
    plug :put_layout, false
    plug :put_secure_browser_headers
    plug FrontendExWeb.Plugs.TrimTrailingNewline
  end

  # Non-HTML assets (e.g. SVG) that should not be wrapped by the skin layout.
  pipeline :fast_svg do
    plug :accepts, ["html", "svg"]
    plug :put_root_layout, false
    plug :put_layout, false
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :dashboard do
    plug FrontendExWeb.Plugs.DashboardLocalOnly
  end

  scope "/", FrontendExWeb do
    # Ops/debug routes: no SSR pipeline, no trailing-newline trimming.
    get "/health", OpsController, :health
    get "/stats", OpsController, :stats
  end

  scope "/", FrontendExWeb do
    pipe_through [:browser, :dashboard]

    live_dashboard "/_dashboard", metrics: FrontendExWeb.Telemetry
  end

  # 2d-fork: removed routes (no ERC-20 / NFT / internal-tx in 2d):
  #   /nft-latest-mints.csv, /tokens, /nft-transfers, /nft-latest-mints,
  #   /tx/:hash/internal, /address/:address/{tokens,token-transfers,internal},
  #   /token/:address[/holders], /exportData
  # The 2d backend at `/api/v2/*` returns 404 for these (TASK-13.2).
  scope "/", FrontendExWeb do
    pipe_through :fast_browser

    get "/", HomeController, :index
    get "/search", SearchController, :index
    get "/blocks", BlocksController, :index
    get "/txs", TxsController, :index
    get "/block/:id", BlockController, :show
    get "/block/:id/txs", BlockController, :txs
    get "/tx/:hash", TxController, :show
    get "/tx/:hash/logs", TxController, :logs
    get "/tx/:hash/state", TxController, :state
    get "/address/:address", AddressController, :show
  end

  scope "/", FrontendExWeb do
    pipe_through :fast_plain_html

    get "/tx/:hash/card", TxController, :card
  end

  scope "/", FrontendExWeb do
    pipe_through :fast_svg

    get "/tx/:hash/og-image.svg", TxController, :og_image
  end
end
