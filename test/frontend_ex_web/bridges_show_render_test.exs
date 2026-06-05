defmodule FrontendExWeb.BridgesShowRenderTest do
  alias FrontendEx.TestSupport.Golden

  @moduledoc """
  Render tests for `/bridges/:eth_event_id` (TASK-47).
  """

  use FrontendExWeb.ConnCase, async: false

  @event_id "0xbeef000000000000000000000000000000000000000000000000000000000000"

  @stats %{
    "total_blocks" => 1,
    "total_transactions" => 1,
    "latest_block_number" => 0,
    "native_coin" => %{"symbol" => "USDC", "decimals" => 6}
  }

  @bridge_show %{
    "amount" => "1000000",
    "eth_event_id" => @event_id,
    "htlc_hash" => "0xc0de000000000000000000000000000000000000000000000000000000000000",
    "inserted_at" => "2026-02-09T10:00:00.000Z",
    "recipient" => "0xfe00000000000000000000000000000000000000",
    "source_chain_id" => 1,
    "source_log_index" => 7,
    "source_tx_hash" => "0xabcd000000000000000000000000000000000000000000000000000000000000",
    "tx_hash_2d" => "0xface000000000000000000000000000000000000000000000000000000000000"
  }

  @frozen_now ~U[2026-02-09 12:00:00Z]

  defmodule Adapter do
    @moduledoc false
    @behaviour FrontendEx.Blockscout.RequestAdapter

    @impl true
    def request_raw(url) when is_binary(url) do
      uri = URI.parse(url)
      path = uri.path || ""

      body =
        case path do
          "/api/v2/stats" ->
            Application.get_env(:frontend_ex, :bridges_show_test_stats_payload)

          "/api/v2/bridges/" <> _ ->
            Application.get_env(:frontend_ex, :bridges_show_test_payload)

          _ ->
            nil
        end

      case body do
        nil ->
          {:ok, %Req.Response{status: 404, headers: [], body: ""}}

        map ->
          {:ok,
           %Req.Response{
             status: 200,
             headers: [{"content-type", "application/json"}],
             body: Jason.encode!(map)
           }}
      end
    end
  end

  setup do
    prev_adapter = Application.get_env(:frontend_ex, :blockscout_request_adapter)
    prev_clock = Application.get_env(:frontend_ex, :clock_utc_now)

    Application.put_env(:frontend_ex, :blockscout_request_adapter, Adapter)
    Application.put_env(:frontend_ex, :clock_utc_now, @frozen_now)
    Application.put_env(:frontend_ex, :bridges_show_test_stats_payload, @stats)
    Application.put_env(:frontend_ex, :bridges_show_test_payload, @bridge_show)

    _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)
    _ = FrontendEx.Cache.clear(FrontendEx.ApiSWRCache)

    on_exit(fn ->
      Application.put_env(:frontend_ex, :blockscout_request_adapter, prev_adapter)
      Application.delete_env(:frontend_ex, :bridges_show_test_stats_payload)
      Application.delete_env(:frontend_ex, :bridges_show_test_payload)

      if prev_clock do
        Application.put_env(:frontend_ex, :clock_utc_now, prev_clock)
      else
        Application.delete_env(:frontend_ex, :clock_utc_now)
      end

      _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)
      _ = FrontendEx.Cache.clear(FrontendEx.ApiSWRCache)
    end)

    :ok
  end

  defp clear_api_caches do
    _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)
    _ = FrontendEx.Cache.clear(FrontendEx.ApiSWRCache)
  end

  test "renders bridge mint detail with links", %{conn: conn} do
    html =
      conn
      |> get("/bridges/#{@event_id}")
      |> html_response(200)

    golden_path = Path.expand("../golden/bridges_show.classic.html", __DIR__)
    Golden.assert_golden!(golden_path, html)

    assert html =~ "Bridge mint"
    assert html =~ @event_id
    assert html =~ "1 USDC"
    assert html =~ "/tx/0xface"
    assert html =~ "etherscan.io/tx/0xabcd"
    assert html =~ "/address/0xfe00000000000000000000000000000000000000"
    assert html =~ "← All bridges"
  end

  test "returns 404 for unknown event id", %{conn: conn} do
    Application.put_env(:frontend_ex, :bridges_show_test_payload, nil)
    clear_api_caches()

    conn = get(conn, "/bridges/#{@event_id}")
    assert conn.status == 404
    assert conn.resp_body == "Bridge mint not found"
  end

  test "returns 404 for malformed event id", %{conn: conn} do
    conn = get(conn, "/bridges/not-a-hash")
    assert conn.status == 404
    assert conn.resp_body == "Bridge mint not found"
  end
end
