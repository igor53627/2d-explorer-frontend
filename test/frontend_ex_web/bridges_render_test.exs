defmodule FrontendExWeb.BridgesRenderTest do
  @moduledoc """
  Render tests for `/bridges` (TASK-45). Drives the controller via an
  inline adapter that implements `FrontendEx.Blockscout.RequestAdapter`,
  mirroring the pattern in `usdc_render_test.exs`. The fixture shape is
  the one resolved in `2d` TASK-13.17 (flat `source_chain_id` /
  `source_tx_hash` / `source_log_index`); the seed values mirror
  `~/pse/2d/test/support/explorer_api_golden/bridges_index.json`.

  Per-scenario payloads are stashed in `Application` env (not the process
  dictionary) because the controller fetches via `Task.async`, which spawns
  a separate process whose `Process` dict is empty.
  """

  use FrontendExWeb.ConnCase, async: false

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
            Application.get_env(:frontend_ex, :bridges_test_stats_payload)

          "/api/v2/bridges" ->
            # Track only /api/v2/bridges URLs — /api/v2/stats fires from the
            # same controller and would otherwise overwrite the bridge URL we
            # want to assert in cursor / page-size tests.
            Application.put_env(:frontend_ex, :bridges_test_last_url, url)

            Application.get_env(:frontend_ex, :bridges_test_payload, %{
              "items" => [],
              "next_page_params" => nil
            })

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
    Application.put_env(:frontend_ex, :bridges_test_stats_payload, @stats)

    _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)
    _ = FrontendEx.Cache.clear(FrontendEx.ApiSWRCache)

    on_exit(fn ->
      Application.put_env(:frontend_ex, :blockscout_request_adapter, prev_adapter)
      Application.delete_env(:frontend_ex, :bridges_test_stats_payload)
      Application.delete_env(:frontend_ex, :bridges_test_payload)
      Application.delete_env(:frontend_ex, :bridges_test_last_url)

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

  defp put_bridges_payload(payload) do
    Application.put_env(:frontend_ex, :bridges_test_payload, payload)
    _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)
    _ = FrontendEx.Cache.clear(FrontendEx.ApiSWRCache)
  end

  describe "GET /bridges with one mint (mainnet)" do
    setup do
      put_bridges_payload(%{"items" => [@bridge_default], "next_page_params" => nil})
      :ok
    end

    test "renders all columns from the resolved flat shape", %{conn: conn} do
      html = conn |> get("/bridges") |> html_response(200)

      assert html =~ "Bridges"
      # Amount: trailing zeros trimmed (`1.0000` → `1`) since post-P1
      # /bridges is a row-dense surface where round amounts read better
      # without filler zeros.
      assert html =~ "1 USDC"
      refute html =~ "1.0000 USDC"
      assert html =~ ~s(<a href="/address/0xfe00000000000000000000000000000000000000")
      assert html =~ "0xfe00...0000"

      assert html =~
               ~s(<a href="/tx/0xface000000000000000000000000000000000000000000000000000000000000")

      assert html =~ "0xface...0000"
      # Event ID + HTLC are no longer surfaced as visible cells
      # (operator-only, returned by API) but the row carries them as
      # data-* attributes for power-user inspection / future CSV export.
      assert html =~ ~s(data-event-id="0xbeef000000000000000000000000000000000000000000000000000000000000")
      assert html =~ ~s(data-htlc-hash="0xc0de000000000000000000000000000000000000000000000000000000000000")
      refute html =~ "0xbeef...0000"
      refute html =~ "0xc0de...0000"
      # Direction arrow cell sits between Source ETH Tx and 2D Tx to
      # cue the cross-chain narrative visually.
      assert html =~ ~s(<td class="dir-cell dir-col">)
    end

    test "renders source-chain link to Etherscan when chain_id == 1", %{conn: conn} do
      html = conn |> get("/bridges") |> html_response(200)

      assert html =~
               ~s(href="https://etherscan.io/tx/0xabcd000000000000000000000000000000000000000000000000000000000000")

      assert html =~ "0xabcd...0000#7"
    end
  end

  describe "GET /bridges batch-refill disambiguation" do
    setup do
      shared_tx = "0xdada000000000000000000000000000000000000000000000000000000000000"

      mint_a =
        @bridge_default
        |> Map.put(
          "eth_event_id",
          "0x1111000000000000000000000000000000000000000000000000000000000000"
        )
        |> Map.put("source_tx_hash", shared_tx)
        |> Map.put("source_log_index", 4)
        |> Map.put(
          "tx_hash_2d",
          "0xa1a1000000000000000000000000000000000000000000000000000000000000"
        )

      mint_b =
        @bridge_default
        |> Map.put(
          "eth_event_id",
          "0x2222000000000000000000000000000000000000000000000000000000000000"
        )
        |> Map.put("source_tx_hash", shared_tx)
        |> Map.put("source_log_index", 7)
        |> Map.put(
          "tx_hash_2d",
          "0xb2b2000000000000000000000000000000000000000000000000000000000000"
        )

      put_bridges_payload(%{"items" => [mint_a, mint_b], "next_page_params" => nil})
      :ok
    end

    test "two rows sharing source_tx_hash render distinguishable #log_index suffixes", %{
      conn: conn
    } do
      html = conn |> get("/bridges") |> html_response(200)

      assert html =~ "0xdada...0000#4"
      assert html =~ "0xdada...0000#7"
    end
  end

  describe "GET /bridges empty result" do
    setup do
      put_bridges_payload(%{"items" => [], "next_page_params" => nil})
      :ok
    end

    test "renders onboarding empty-state and 200, no error", %{conn: conn} do
      html = conn |> get("/bridges") |> html_response(200)
      # Post-P2: empty-state is an onboarding block, not a one-line
      # "no records" stub. Pin the heading + the docs link so future
      # template tweaks don't accidentally drop the orientation copy
      # that helps a user landing on /bridges cold.
      assert html =~ ~s(class="empty-state bridges-empty-state")
      assert html =~ "No bridge mints yet"
      assert html =~ "cross-chain USDC transfers from Ethereum into 2D"
      assert html =~ ~s(href="https://igor53627.github.io/2d-docs/")
    end
  end

  describe "GET /bridges page-size handling" do
    setup do
      put_bridges_payload(%{"items" => [@bridge_default], "next_page_params" => nil})
      :ok
    end

    test "ps=999 clamps to default 50", %{conn: conn} do
      _html = conn |> get("/bridges?ps=999") |> html_response(200)
      url = Application.get_env(:frontend_ex, :bridges_test_last_url)
      assert is_binary(url)
      assert url =~ "items_count=50"
    end

    test "ps=25 passes through", %{conn: conn} do
      _html = conn |> get("/bridges?ps=25") |> html_response(200)
      url = Application.get_env(:frontend_ex, :bridges_test_last_url)
      assert is_binary(url)
      assert url =~ "items_count=25"
    end

    test "items_count bypass via top-level param is ignored (server-controlled)", %{conn: conn} do
      _html = conn |> get("/bridges?items_count=10000") |> html_response(200)
      url = Application.get_env(:frontend_ex, :bridges_test_last_url)
      assert is_binary(url)
      # User-supplied items_count must not reach upstream — only normalized ps.
      assert url =~ "items_count=50"
      refute url =~ "items_count=10000"
    end

    test "items_count bypass via cursor segment is stripped", %{conn: conn} do
      _html =
        conn
        |> get("/bridges?cursor=items_count=10000%26block_number=42")
        |> html_response(200)

      url = Application.get_env(:frontend_ex, :bridges_test_last_url)
      assert is_binary(url)
      assert url =~ "items_count=50"
      refute url =~ "items_count=10000"
      assert url =~ "block_number=42"
    end
  end

  describe "GET /bridges cursor passthrough" do
    setup do
      put_bridges_payload(%{"items" => [], "next_page_params" => nil})
      :ok
    end

    test "block_number + event_id from cursor querystring reach the upstream URL", %{conn: conn} do
      cursor =
        "block_number=42&event_id=0x" <> String.duplicate("a", 64)

      conn
      |> get("/bridges", %{"cursor" => cursor})
      |> html_response(200)

      url = Application.get_env(:frontend_ex, :bridges_test_last_url)
      assert is_binary(url)
      assert url =~ "block_number=42"
      assert url =~ "event_id=0x" <> String.duplicate("a", 64)
    end
  end

  describe "GET /bridges non-mainnet chain falls back to plain text" do
    setup do
      mint = Map.put(@bridge_default, "source_chain_id", 999)
      put_bridges_payload(%{"items" => [mint], "next_page_params" => nil})
      :ok
    end

    test "no Etherscan <a> wrapping the source-tx cell", %{conn: conn} do
      html = conn |> get("/bridges") |> html_response(200)
      refute html =~ "https://etherscan.io/tx/"
      assert html =~ "0xabcd...0000#7"
    end
  end

  describe "GET /bridges malformed source_tx_hash on mainnet (defense-in-depth)" do
    # `source_chain_explorer_url/2` validates the hash with a strict
    # `^(0x)?[0-9a-fA-F]{64}$` regex even when chain_id == 1 — so a
    # corrupted upstream payload (truncated hash, embedded scheme
    # injection, etc.) cannot land in an `href=` attribute. Compact
    # roborev #2237 flagged that this branch was implemented in PR #4
    # but had no targeted regression test.
    test "truncated hash with chain_id=1 falls back to plain text (no <a href)", %{conn: conn} do
      mint = Map.put(@bridge_default, "source_tx_hash", "0xdeadbeef")
      put_bridges_payload(%{"items" => [mint], "next_page_params" => nil})

      html = conn |> get("/bridges") |> html_response(200)
      refute html =~ "https://etherscan.io/tx/"
    end

    test "scheme-injection-shaped hash with chain_id=1 produces no <a href", %{conn: conn} do
      # The regex guard rejects non-hex shapes so the controller returns
      # nil for `source_chain_explorer_url`, and the template's
      # `case ... <% _ -> %>` arm renders a plain `<span>` instead of an
      # anchor. The malformed `"javascript:alert(1)"` does still surface
      # inside the cell's `title=` tooltip (it's the raw `source_tx_hash`
      # value), but a tooltip cannot execute a URI scheme — only `href=`
      # with `javascript:` would. So the right assertion is "no anchor
      # tag was emitted for this row", not "the bytes never appear in
      # the HTML".
      mint = Map.put(@bridge_default, "source_tx_hash", "javascript:alert(1)")
      put_bridges_payload(%{"items" => [mint], "next_page_params" => nil})

      html = conn |> get("/bridges") |> html_response(200)
      refute html =~ "https://etherscan.io/tx/"
      # Defense in depth: the dangerous shape is `href="javascript:` —
      # any href whose value starts with the javascript scheme. Title
      # attributes (`title="javascript:..."`) are inert.
      refute html =~ ~s(href="javascript:)
    end
  end

  describe "GET /bridges source_log_index nil tooltip" do
    # Display surface and tooltip both guard against `nil` log index now
    # (ultrareview bug_001 fix in 9d3ba47). Pin the tooltip behavior so a
    # future template refactor doesn't regress to the trailing-label form
    # `title="0xabcd... log index "`.
    test "title attribute omits 'log index' label when source_log_index is nil", %{conn: conn} do
      mint = Map.put(@bridge_default, "source_log_index", nil)
      put_bridges_payload(%{"items" => [mint], "next_page_params" => nil})

      html = conn |> get("/bridges") |> html_response(200)
      # Display cell shows just the truncated hash, no `#N` suffix.
      assert html =~ "0xabcd...0000"
      refute html =~ "0xabcd...0000#"
      # Tooltip on the source-tx span must not contain the dangling
      # "log index " label when the value is nil.
      refute html =~ ~r/title="[^"]*log index ?"/
    end
  end
end
