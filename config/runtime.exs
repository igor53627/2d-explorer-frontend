import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/frontend_ex start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :frontend_ex, FrontendExWeb.Endpoint, server: true
end

parse_ipv4 =
  fn host ->
    host = String.trim(host)

    host =
      case host do
        "" -> "0.0.0.0"
        "localhost" -> "127.0.0.1"
        other -> other
      end

    case String.split(host, ".", parts: 4) do
      [a, b, c, d] ->
        with {a, ""} <- Integer.parse(a),
             {b, ""} <- Integer.parse(b),
             {c, ""} <- Integer.parse(c),
             {d, ""} <- Integer.parse(d),
             true <- Enum.all?([a, b, c, d], &(&1 >= 0 and &1 <= 255)) do
          {a, b, c, d}
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

parse_listen_addr =
  fn listen_addr ->
    listen_addr = String.trim(to_string(listen_addr))

    case String.split(listen_addr, ":", parts: 2) do
      [host, port_str] ->
        ip = parse_ipv4.(host)

        case {ip, Integer.parse(String.trim(port_str))} do
          {nil, _} -> nil
          {_, :error} -> nil
          {ip, {port, ""}} when port > 0 and port < 65_536 -> {ip, port}
          _ -> nil
        end

      _ ->
        nil
    end
  end

default_listen_addr = "0.0.0.0:3000"

{ip, port} =
  parse_listen_addr.(System.get_env("LISTEN_ADDR") || default_listen_addr) ||
    {parse_ipv4.("0.0.0.0"), String.to_integer(System.get_env("PORT", "3000"))}

if config_env() != :test do
  config :frontend_ex, FrontendExWeb.Endpoint, http: [ip: ip, port: port]
end

# Default points at a local 2d dev backend. Override via BLOCKSCOUT_API_URL
# env in any non-default deployment (staging/prod/CI).
blockscout_api_url =
  System.get_env("BLOCKSCOUT_API_URL", "http://localhost:4000")
  |> String.trim()
  |> String.trim_trailing("/")

blockscout_txs_api_url =
  case System.get_env("BLOCKSCOUT_TXS_API_URL") do
    nil -> nil
    "" -> nil
    v -> v |> String.trim() |> String.trim_trailing("/")
  end

blockscout_url =
  System.get_env("BLOCKSCOUT_URL", blockscout_api_url)
  |> String.trim()
  |> String.trim_trailing("/")

blockscout_ws_url =
  case System.get_env("BLOCKSCOUT_WS_URL") do
    nil -> nil
    "" -> nil
    v -> v |> String.trim() |> String.trim_trailing("/")
  end

base_url =
  System.get_env("BASE_URL", "https://fast.53627.org")
  |> String.trim()
  |> String.trim_trailing("/")

ff_skin =
  System.get_env("FF_SKIN", "53627")
  |> String.trim()

config :frontend_ex,
  blockscout_api_url: blockscout_api_url,
  blockscout_txs_api_url: blockscout_txs_api_url,
  blockscout_url: blockscout_url,
  blockscout_ws_url: blockscout_ws_url,
  base_url: base_url,
  ff_skin: ff_skin

metrics_enabled =
  case System.get_env("FF_METRICS_ENABLED") do
    nil -> true
    "" -> true
    "true" -> true
    "TRUE" -> true
    "1" -> true
    "false" -> false
    "FALSE" -> false
    "0" -> false
    other -> raise "invalid FF_METRICS_ENABLED value: #{inspect(other)} (expected true/false)"
  end

metrics_port =
  case System.get_env("FF_METRICS_PORT") do
    nil ->
      9568

    v ->
      v = String.trim(v)

      if v == "" do
        9568
      else
        case Integer.parse(v) do
          {port, ""} when port > 0 and port < 65_536 ->
            port

          _ ->
            raise "invalid FF_METRICS_PORT value: #{inspect(v)} (expected integer 1..65535)"
        end
      end
  end

config :frontend_ex, :metrics,
  enabled: metrics_enabled,
  port: metrics_port,
  # Never bind metrics publicly by default.
  ip: {127, 0, 0, 1}

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :frontend_ex, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :frontend_ex, FrontendExWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :frontend_ex, FrontendExWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :frontend_ex, FrontendExWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
