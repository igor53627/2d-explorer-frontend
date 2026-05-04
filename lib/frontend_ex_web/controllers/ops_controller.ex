defmodule FrontendExWeb.OpsController do
  use FrontendExWeb, :controller

  def health(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "OK")
  end

  def stats(conn, _params) do
    api_cache =
      Application.get_env(:frontend_ex, :blockscout_api_cache_server, FrontendEx.ApiCache)

    swr_cache =
      Application.get_env(:frontend_ex, :blockscout_api_swr_cache_server, FrontendEx.ApiSWRCache)

    api_stats = FrontendEx.Cache.stats(api_cache)
    swr_stats = FrontendEx.Cache.SWR.stats(swr_cache)

    json(conn, %{
      cache_entries: api_stats.entries,
      swr_cache_entries: swr_stats.entries,
      cache_config: %{
        standard_ttl_secs: 60,
        negative_ttl_secs: 5,
        swr_fresh_secs: 5,
        swr_stale_secs: 20
      },
      api_cache: api_stats,
      swr_cache: swr_stats,
      # Helpful when debugging in prod; values come from runtime config.
      upstream: %{
        blockscout_api_url: Application.get_env(:frontend_ex, :blockscout_api_url),
        blockscout_url: Application.get_env(:frontend_ex, :blockscout_url)
      }
    })
  end
end
