# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :frontend_ex,
  generators: [timestamp_type: :utc_datetime],
  # Ethereum source-tx links on bridge surfaces (TASK-49 AC#9).
  ethereum_tx_explorer_base: "https://etherscan.io/tx"

# Configure the endpoint
#
# Session and LiveView signing salts default to dev-only placeholders here
# and must be overridden at build time for prod — see `config/prod.exs` which
# reads SESSION_SIGNING_SALT / LIVE_VIEW_SIGNING_SALT from the environment.
config :frontend_ex, :session_signing_salt, "dev-only-not-for-prod"

config :frontend_ex, FrontendExWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FrontendExWeb.ErrorHTML, json: FrontendExWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FrontendEx.PubSub,
  live_view: [signing_salt: "dev-only-not-for-prod"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Byte-for-byte HTML parity with Rust templates requires preserving
# whitespace on lines that contain only EEx tags (Askama does not trim).
config :phoenix_template, :trim_on_html_eex_engine, false

# Prometheus metrics exporter (scraped by telegraf/prometheus). The exporter runs
# its own HTTP server on localhost and does not impact parity SSR routes.
config :frontend_ex, :metrics,
  enabled: true,
  port: 9568,
  ip: {127, 0, 0, 1}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
