defmodule FrontendExWeb.AddressBridgesRenderTest do
  @moduledoc """
  Render tests for `/address/:addr/bridges` (TASK-46) + Bridges-tab
  visibility on the address index page. Mirrors the inline-Adapter +
  Application-env-payload pattern from `bridges_render_test.exs` so
  payloads stay in scope across `Task.async`'d upstream calls.

  Stubs three endpoints: `/api/v2/stats`, `/api/v2/addresses/:addr`,
  `/api/v2/addresses/:addr/bridge-mints`.
  """

  use FrontendExWeb.ConnCase, async: false

  @addr "0xfe00000000000000000000000000000000000000"

  @stats %{
    "total_blocks" => 1,
    "total_transactions" => 1,
    "latest_block_number" => 0,
    "native_coin" => %{"symbol" => "USDC", "decimals" => 6}
  }

  @bridge_default %{
    "amount" => "1000000",
    "eth_event_id" => "0xbeef000000000000000000000000000000000000000000000000000000000000",
    "htlc_hash" => "0xc0de000000000000000000000000000000000000000000000000000000000000",
    "inserted_at" => "2026-02-09T10:00:00.000Z",
    "recipient" => @addr,
    "source_chain_id" => 1,
    "source_log_index" => 7,
    "source_tx_hash" => "0xabcd000000000000000000000000000000000000000000000000000000000000",
    "tx_hash_2d" => "0xface000000000000000000000000000000000000000000000000000000000000"
  }

  @addr_payload_base %{
    "hash" => @addr,
    "is_contract" => false,
    "is_verified" => false,
    "coin_balance" => "0",
    "transactions_count" => 0,
    "nonce" => 0,
    "primary_kind" => "eth_rlp",
    "has_token_transfers" => false,
    "has_tokens" => false
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
        cond do
          path == "/api/v2/stats" ->
            Application.get_env(:frontend_ex, :addr_bridges_test_stats_payload)

          String.starts_with?(path, "/api/v2/addresses/") and
              String.ends_with?(path, "/bridge-mints") ->
            Application.put_env(:frontend_ex, :addr_bridges_test_last_url, url)

            Application.get_env(:frontend_ex, :addr_bridges_test_payload, %{
              "items" => [],
              "next_page_params" => nil
            })

          String.starts_with?(path, "/api/v2/addresses/") ->
            Application.get_env(:frontend_ex, :addr_bridges_test_addr_payload)

          true ->
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
    Application.put_env(:frontend_ex, :addr_bridges_test_stats_payload, @stats)
    Application.put_env(:frontend_ex, :addr_bridges_test_addr_payload, @addr_payload_base)

    _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)
    _ = FrontendEx.Cache.clear(FrontendEx.ApiSWRCache)

    on_exit(fn ->
      Application.put_env(:frontend_ex, :blockscout_request_adapter, prev_adapter)
      Application.delete_env(:frontend_ex, :addr_bridges_test_stats_payload)
      Application.delete_env(:frontend_ex, :addr_bridges_test_addr_payload)
      Application.delete_env(:frontend_ex, :addr_bridges_test_payload)
      Application.delete_env(:frontend_ex, :addr_bridges_test_last_url)

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

  defp put_addr_payload(payload),
    do: Application.put_env(:frontend_ex, :addr_bridges_test_addr_payload, payload)

  defp put_bridges_payload(payload) do
    Application.put_env(:frontend_ex, :addr_bridges_test_payload, payload)
    _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)
    _ = FrontendEx.Cache.clear(FrontendEx.ApiSWRCache)
  end

  describe "GET /address/:addr/bridges (page itself)" do
    setup do
      put_bridges_payload(%{"items" => [@bridge_default], "next_page_params" => nil})
      :ok
    end

    test "renders bridge-mints table with correct columns", %{conn: conn} do
      html = conn |> get("/address/#{@addr}/bridges") |> html_response(200)

      # Amount: trimmed trailing zeros (post-P1 row-density tweak).
      assert html =~ "1 USDC"
      refute html =~ "1.0000 USDC"
      assert html =~ ~s(<a href="/address/#{@addr}")
      assert html =~ "0xfe00...0000"

      assert html =~
               ~s(<a href="/tx/0xface000000000000000000000000000000000000000000000000000000000000")

      assert html =~ "0xface...0000"

      assert html =~
               ~s(href="https://etherscan.io/tx/0xabcd000000000000000000000000000000000000000000000000000000000000")

      assert html =~ "0xabcd...0000#7"

      # Event ID + HTLC: row data-* attributes (operator-only fields,
      # surfaced via DevTools / future CSV export, not as visible cells).
      assert html =~ ~s(data-event-id="0xbeef000000000000000000000000000000000000000000000000000000000000")
      assert html =~ ~s(data-htlc-hash="0xc0de000000000000000000000000000000000000000000000000000000000000")
      refute html =~ "0xbeef...0000"
      refute html =~ "0xc0de...0000"
      # Direction arrow cell between Source ETH Tx and 2D Tx columns.
      # Direction arrow cell + `data-csv-skip` to mirror the `<th>` for
      # CSV-exporter consistency.
      assert html =~ ~s(<td class="dir-cell dir-col" data-csv-skip>)
    end

    test "Bridges tab always renders as active here, even when count==0 (ultrareview bug_003)", %{
      conn: conn
    } do
      # Default @addr_payload_base has no bridge_mints_count → parses to 0.
      # Direct URL entry (bookmark, shared link, URL bar) must still surface
      # an active-tab indicator so the user knows where they are; the
      # tab visibility gate from the address-index template does not apply
      # on this surface. Regression test for the rollout window when
      # 2d TASK-13.25 has not yet shipped `bridge_mints_count` on the
      # `/api/v2/addresses/:address` payload.
      put_addr_payload(@addr_payload_base)
      html = conn |> get("/address/#{@addr}/bridges") |> html_response(200)

      assert html =~ ~s(<a href="/address/#{@addr}/bridges" class="tab active">Bridges)
      # The "(N)" count suffix stays conditional — rendering "Bridges (0)"
      # alongside the empty-state copy "No bridge mints for this address."
      # would be redundant.
      refute html =~ "Bridges (0)"
    end
  end

  describe "GET /address/:addr/bridges empty result" do
    setup do
      put_bridges_payload(%{"items" => [], "next_page_params" => nil})
      :ok
    end

    test "renders empty-state copy and 200", %{conn: conn} do
      html = conn |> get("/address/#{@addr}/bridges") |> html_response(200)
      assert html =~ "No bridge mints for this address."
    end
  end

  describe "Bridges tab visibility on address index" do
    test "hidden when bridge_mints_count is missing (defaults to 0 — pre-13.25)", %{conn: conn} do
      put_addr_payload(@addr_payload_base)
      html = conn |> get("/address/#{@addr}") |> html_response(200)
      refute html =~ ~s(href="/address/#{@addr}/bridges")
      refute html =~ "Bridges ("
    end

    test "hidden when bridge_mints_count is explicitly 0", %{conn: conn} do
      put_addr_payload(Map.put(@addr_payload_base, "bridge_mints_count", 0))
      html = conn |> get("/address/#{@addr}") |> html_response(200)
      refute html =~ ~s(href="/address/#{@addr}/bridges")
      refute html =~ "Bridges ("
    end

    test "shown with count when bridge_mints_count > 0", %{conn: conn} do
      put_addr_payload(Map.put(@addr_payload_base, "bridge_mints_count", 3))
      html = conn |> get("/address/#{@addr}") |> html_response(200)
      assert html =~ ~s(href="/address/#{@addr}/bridges")
      assert html =~ "Bridges (3)"
    end
  end

  describe "GET /address/:addr/bridges page-size handling" do
    setup do
      put_bridges_payload(%{"items" => [@bridge_default], "next_page_params" => nil})
      :ok
    end

    test "ps=999 clamps to default 50", %{conn: conn} do
      _html = conn |> get("/address/#{@addr}/bridges?ps=999") |> html_response(200)
      url = Application.get_env(:frontend_ex, :addr_bridges_test_last_url)
      assert is_binary(url)
      assert url =~ "items_count=50"
    end

    test "ps=25 passes through", %{conn: conn} do
      _html = conn |> get("/address/#{@addr}/bridges?ps=25") |> html_response(200)
      url = Application.get_env(:frontend_ex, :addr_bridges_test_last_url)
      assert is_binary(url)
      assert url =~ "items_count=25"
    end

    test "items_count bypass via top-level param is ignored (server-controlled)", %{conn: conn} do
      _html =
        conn |> get("/address/#{@addr}/bridges?items_count=10000") |> html_response(200)

      url = Application.get_env(:frontend_ex, :addr_bridges_test_last_url)
      assert is_binary(url)
      assert url =~ "items_count=50"
      refute url =~ "items_count=10000"
    end

    test "items_count bypass via cursor segment is stripped", %{conn: conn} do
      _html =
        conn
        |> get("/address/#{@addr}/bridges?cursor=items_count=10000%26block_number=42")
        |> html_response(200)

      url = Application.get_env(:frontend_ex, :addr_bridges_test_last_url)
      assert is_binary(url)
      assert url =~ "items_count=50"
      refute url =~ "items_count=10000"
      assert url =~ "block_number=42"
    end
  end

  describe "GET /address/:addr/bridges cursor passthrough" do
    setup do
      put_bridges_payload(%{"items" => [], "next_page_params" => nil})
      :ok
    end

    test "block_number + event_id from cursor querystring reach upstream URL", %{conn: conn} do
      cursor = "block_number=42&event_id=0x" <> String.duplicate("a", 64)

      conn
      |> get("/address/#{@addr}/bridges", %{"cursor" => cursor})
      |> html_response(200)

      url = Application.get_env(:frontend_ex, :addr_bridges_test_last_url)
      assert is_binary(url)
      assert url =~ "block_number=42"
      assert url =~ "event_id=0x" <> String.duplicate("a", 64)
    end
  end

  describe "GET /address/:addr/bridges hex/Base58 explanatory note" do
    # `parse_address/1` in AddressController derives `tron_hash` from the
    # 0x form via `FrontendEx.Tron.Address.from_eth_hex/1`, so any non-
    # zero hex hash gets a tron_hash. The page-header note must mirror
    # the index template (classic_content) — present when both forms are
    # rendered, absent when there's only the hex form. Compact roborev
    # #2237 flagged that ultrareview bug_002 fix in 9d3ba47 had no
    # targeted regression test.
    setup do
      put_bridges_payload(%{"items" => [], "next_page_params" => nil})
      :ok
    end

    test "renders the hex/Base58 helper sentence when tron_hash is present", %{conn: conn} do
      # Default @addr (0xfe00...0000) has a non-zero hex form, so
      # from_eth_hex/1 returns a Base58 form. The note should render.
      html = conn |> get("/address/#{@addr}/bridges") |> html_response(200)

      assert html =~ ~s(<div class="address-page-header-note">)
      assert html =~ "Both addresses point to the same account"
    end

    test "omits the note when tron_hash derivation fails (defensive branch)", %{conn: conn} do
      # `parse_address/1` calls `Tron.Address.from_eth_hex(hash)` and
      # threads the result into the template's `tron_hash` conditional.
      # The fallback `from_eth_hex(_) -> nil` clause fires on malformed
      # input; an upstream payload with a missing `hash` field exercises
      # that path (`to_string(json["hash"] || "")` → `""` →
      # `from_eth_hex("") = nil`). The URL still uses the valid request
      # address (controller validates `eth_address?/1` before fetching),
      # so we can decouple URL-validity from payload-shape.
      put_addr_payload(@addr_payload_base |> Map.delete("hash"))

      html = conn |> get("/address/#{@addr}/bridges") |> html_response(200)

      refute html =~ ~s(<div class="address-page-header-note">)
      refute html =~ "Both addresses point to the same account"
    end
  end
end
