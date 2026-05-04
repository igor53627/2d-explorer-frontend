defmodule FrontendExWeb.UsdcRenderTest do
  @moduledoc """
  Smoke tests that the 2d fork renders the USDC native-coin ticker
  end-to-end through controllers/templates against 2d-shaped /api/v2/*
  JSON.

  Intentionally narrow: render each of `/`, `/blocks`, `/txs` once with
  a stub adapter and assert the USDC symbol surfaces on pages that
  display value/reward fields, plus the absence of the legacy "ETH"
  ticker. Full byte-for-byte goldens land later when the fork is
  pointed at a live 2d backend.
  """

  use FrontendExWeb.ConnCase, async: false

  defmodule TwoDAdapter do
    @moduledoc false
    @behaviour FrontendEx.Blockscout.RequestAdapter

    @stats %{
      "total_blocks" => 1,
      "total_transactions" => 1,
      "latest_block_number" => 0,
      "native_coin" => %{"symbol" => "USDC", "decimals" => 6}
    }

    @blocks_list %{
      "items" => [
        %{
          "height" => 0,
          "hash" => "0x" <> String.duplicate("0", 64),
          "parent_hash" => "0x" <> String.duplicate("0", 64),
          "timestamp" => "2023-11-14T22:13:20Z",
          "transaction_count" => 1,
          "miner" => %{"hash" => "0x2d00000000000000000000000000000000000001"}
        }
      ],
      "next_page_params" => nil
    }

    @tx_hash "0xcafe000000000000000000000000000000000000000000000000000000000000"

    # EIP-1559 fixture: non-nil 1559 fee fields exercise the
    # `<%= @gas_price_gwei %> <%= @native_coin.symbol %>` and
    # `Base / Max / Max Priority` template branches that earlier had
    # hardcoded "Gwei" labels. Values are USDC base units in 2d.
    @tx_detail %{
      "hash" => @tx_hash,
      "block_number" => 0,
      "transaction_index" => 0,
      "timestamp" => "2023-11-14T22:13:20Z",
      "from" => %{"hash" => "0x0000000000000000000000000000000000000001"},
      "to" => %{"hash" => "0x0000000000000000000000000000000000000002"},
      "value" => "100",
      "status" => "ok",
      # gas_used / gas_limit ship as JSON integers in 2d's API (vs. strings
      # upstream). The mixed shapes here pin parse_tx's normalizer:
      # if it ever regresses to binary-only, the gas-usage row vanishes.
      "gas_used" => 21_000,
      "gas_limit" => 30_000_000,
      "gas_price" => "5",
      "fee" => %{"value" => "105000"},
      "transaction_type" => 2,
      "max_fee_per_gas" => "10",
      "max_priority_fee_per_gas" => "2",
      "base_fee_per_gas" => "3"
    }

    @transactions_list %{
      "items" => [@tx_detail],
      "next_page_params" => nil
    }

    @tx_logs %{"items" => [], "next_page_params" => nil}

    # EIP-4844 blob-commit fixture. 2d uses `transaction_type` (singular);
    # upstream Blockscout uses `type`. parse_tx must accept both — without
    # the fallback, @tx.tx_type is permanently nil against 2d and the
    # template's `case @tx.tx_type do 3 -> "Commit EIP-4844 Blob"` branch
    # is unreachable.
    @tx_blob_hash "0xb10b000000000000000000000000000000000000000000000000000000000000"
    @tx_blob_detail %{
      "hash" => @tx_blob_hash,
      "block_number" => 0,
      "transaction_index" => 1,
      "timestamp" => "2023-11-14T22:13:20Z",
      "from" => %{"hash" => "0x0000000000000000000000000000000000000001"},
      "to" => %{"hash" => "0x0000000000000000000000000000000000000002"},
      "value" => "0",
      "status" => "ok",
      "gas_used" => 21_000,
      "gas_limit" => 30_000_000,
      "gas_price" => "5",
      "fee" => %{"value" => "105000"},
      "transaction_type" => 3
    }
    @tx_blob_logs %{"items" => [], "next_page_params" => nil}

    # EIP-1559 block detail: non-null base_fee_per_gas in USDC base units
    # (1500 base = 0.0015 USDC). Pins that /block/:id formats the base fee
    # via Format.format_native_amount/1 instead of dropping the raw integer
    # next to a USDC label (a 10^6 overstatement).
    @block_detail %{
      "height" => 0,
      "hash" => "0x" <> String.duplicate("0", 64),
      "parent_hash" => "0x" <> String.duplicate("0", 64),
      "timestamp" => "2023-11-14T22:13:20Z",
      "transaction_count" => 1,
      "miner" => %{"hash" => "0x2d00000000000000000000000000000000000001"},
      "gas_used" => 21_000,
      "gas_limit" => 30_000_000,
      "size" => 1024,
      "base_fee_per_gas" => "1500",
      "nonce" => "0x0000000000000000",
      "extra_data" => nil,
      "state_root" => "0x" <> String.duplicate("0", 64)
    }

    @block_txs %{"items" => [], "next_page_params" => nil}

    @addr_hash "0x0000000000000000000000000000000000000001"

    @address_detail %{
      "hash" => @addr_hash,
      "coin_balance" => "1234567",
      "is_contract" => false,
      "is_verified" => false,
      "transactions_count" => 0
    }

    @address_txs %{"items" => [], "next_page_params" => nil}
    @address_tokens %{"items" => [], "next_page_params" => nil}

    # Separate fixture for the More-Info Latest/First regression: a
    # second pool address with a single transaction that carries a
    # `timestamp`. transactions_count = 1 and preview length = 1, so
    # both Latest and First rows must surface (mirrors the path
    # `derive_tx_time_window/2` will hit once 2d ships TASK-13.7).
    @addr_with_ts_hash "0x0000000000000000000000000000000000000002"
    @addr_with_ts_detail %{
      "hash" => @addr_with_ts_hash,
      "coin_balance" => "500000",
      "is_contract" => false,
      "is_verified" => false,
      "transactions_count" => 1
    }
    @addr_with_ts_txs %{
      "items" => [
        %{
          "hash" => "0xab" <> String.duplicate("0", 62),
          "block_number" => 0,
          "transaction_index" => 0,
          "timestamp" => "2023-11-14T22:13:20Z",
          "from" => %{"hash" => @addr_with_ts_hash},
          "to" => %{"hash" => "0x0000000000000000000000000000000000000003"},
          "value" => "100",
          "status" => "ok",
          "transaction_type" => 0
        }
      ],
      "next_page_params" => nil
    }

    @impl true
    def request_raw(url) when is_binary(url) do
      uri = URI.parse(url)
      path = uri.path || ""

      body =
        case path do
          "/api/v2/stats" -> @stats
          "/api/v2/blocks" -> @blocks_list
          "/api/v2/blocks/0" -> @block_detail
          "/api/v2/blocks/0/transactions" -> @block_txs
          "/api/v2/transactions" -> @transactions_list
          "/api/v2/transactions/" <> rest ->
            cond do
              rest == @tx_hash -> @tx_detail
              rest == "#{@tx_hash}/logs" -> @tx_logs
              rest == @tx_blob_hash -> @tx_blob_detail
              rest == "#{@tx_blob_hash}/logs" -> @tx_blob_logs
              true -> nil
            end

          "/api/v2/addresses/" <> rest ->
            cond do
              rest == @addr_hash -> @address_detail
              rest == "#{@addr_hash}/transactions" -> @address_txs
              rest == "#{@addr_hash}/tokens" -> @address_tokens
              rest == @addr_with_ts_hash -> @addr_with_ts_detail
              rest == "#{@addr_with_ts_hash}/transactions" -> @addr_with_ts_txs
              rest == "#{@addr_with_ts_hash}/tokens" -> @address_tokens
              true -> nil
            end

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

  @frozen_now ~U[2026-02-09 12:00:00Z]

  setup do
    prev_adapter = Application.get_env(:frontend_ex, :blockscout_request_adapter)
    prev_clock = Application.get_env(:frontend_ex, :clock_utc_now)

    Application.put_env(:frontend_ex, :blockscout_request_adapter, TwoDAdapter)
    Application.put_env(:frontend_ex, :clock_utc_now, @frozen_now)

    # Clear caches so the adapter swap actually drives the next request.
    _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)
    _ = FrontendEx.Cache.clear(FrontendEx.ApiSWRCache)

    on_exit(fn ->
      Application.put_env(:frontend_ex, :blockscout_request_adapter, prev_adapter)

      if prev_clock do
        Application.put_env(:frontend_ex, :clock_utc_now, prev_clock)
      else
        Application.delete_env(:frontend_ex, :clock_utc_now)
      end
    end)

    :ok
  end

  test "GET / surfaces USDC, never ETH", %{conn: conn} do
    body = conn |> get("/") |> html_response(200)
    assert body =~ "USDC", "expected home page to render the USDC ticker"
    refute body =~ ~r/\bETH\b/
  end

  describe "WS_URL host source (bug_004 regression pin)" do
    # Pins that the realtime WS endpoint is derived from the Phoenix-channels
    # host (BLOCKSCOUT_API_URL), not the public-facing frontend host
    # (BLOCKSCOUT_URL). In single-host dev these coincide, masking any
    # regression — split-deployment values force the distinction.

    setup do
      prev_url = Application.get_env(:frontend_ex, :blockscout_url)
      prev_api = Application.get_env(:frontend_ex, :blockscout_api_url)
      prev_ws = Application.get_env(:frontend_ex, :blockscout_ws_url)

      on_exit(fn ->
        if prev_url,
          do: Application.put_env(:frontend_ex, :blockscout_url, prev_url),
          else: Application.delete_env(:frontend_ex, :blockscout_url)

        if prev_api,
          do: Application.put_env(:frontend_ex, :blockscout_api_url, prev_api),
          else: Application.delete_env(:frontend_ex, :blockscout_api_url)

        if prev_ws,
          do: Application.put_env(:frontend_ex, :blockscout_ws_url, prev_ws),
          else: Application.delete_env(:frontend_ex, :blockscout_ws_url)
      end)

      :ok
    end

    test "WS_URL derives from api_url when split from frontend url", %{conn: conn} do
      Application.put_env(:frontend_ex, :blockscout_url, "https://example.com")
      Application.put_env(:frontend_ex, :blockscout_api_url, "https://api.example.com")
      Application.delete_env(:frontend_ex, :blockscout_ws_url)

      body = conn |> get("/") |> html_response(200)

      assert body =~ "wss://api.example.com/socket/v2/websocket?vsn=2.0.0",
             "expected WS_URL to derive from BLOCKSCOUT_API_URL host"

      refute body =~ "wss://example.com/socket/v2/websocket",
             "WS_URL must not derive from the public-facing BLOCKSCOUT_URL host"
    end

    test "explicit BLOCKSCOUT_WS_URL overrides derivation", %{conn: conn} do
      Application.put_env(:frontend_ex, :blockscout_url, "https://example.com")
      Application.put_env(:frontend_ex, :blockscout_api_url, "https://api.example.com")
      Application.put_env(:frontend_ex, :blockscout_ws_url, "wss://realtime.example.com/ws")

      body = conn |> get("/") |> html_response(200)

      assert body =~ "wss://realtime.example.com/ws",
             "explicit BLOCKSCOUT_WS_URL must take precedence over derivation"
    end
  end

  test "GET /blocks renders 200 (no token-symbol display on blocks-list by design)", %{conn: conn} do
    body = conn |> get("/blocks") |> html_response(200)
    refute body =~ ~r/\bETH\b/
  end

  test "GET /txs surfaces USDC for tx values, never ETH", %{conn: conn} do
    body = conn |> get("/txs") |> html_response(200)
    assert body =~ "USDC", "expected /txs to render the USDC ticker on tx values"
    refute body =~ ~r/\bETH\b/
  end

  test "GET /tx/:hash surfaces USDC, no Gwei labels remain on gas fields",
       %{conn: conn} do
    body = conn |> get("/tx/0xcafe000000000000000000000000000000000000000000000000000000000000") |> html_response(200)

    assert body =~ "USDC", "expected /tx/:hash to render the USDC ticker"
    refute body =~ ~r/\bETH\b/
    # Gwei labels were the high-severity finding from the previous review:
    # gas-price/base-fee/max-fee values are USDC base units, so labeling
    # them "Gwei" would lie to the user.
    refute body =~ ~r/\bGwei\b/i,
           "tx-detail page must not surface Gwei labels — gas prices are USDC base units"

    # Pins bug_008: parse_tx must accept JSON-integer gas_used (2d's shape),
    # otherwise the entire "Gas Limit & Usage by Txn" row disappears. Match
    # both raw and HTML-escaped forms — Phoenix's safe_to_iodata/1 escapes
    # literal '&' in EEx templates.
    assert body =~ "Gas Limit & Usage by Txn" or body =~ "Gas Limit &amp; Usage by Txn",
           "expected /tx/:hash to render the Gas Limit & Usage row when gas_used is JSON-integer"

    assert body =~ "21000 / 30000000",
           "expected gas_used / gas_limit to render verbatim from 2d's integer-shaped fields"
  end

  describe "GET /address/:hash More Info — Latest / First (timestamp_raw regression)" do
    # Pins display_tx/3 → derive_tx_time_window/2 plumbing. If
    # display_tx ever drops timestamp_raw again, derive_tx_time_window
    # silently returns {nil, nil} and these rows vanish (the bug
    # roborev caught on commit 724600a).
    #
    # Assertions are scoped to the ".address-summary-label" + adjacent
    # ".address-summary-value" pair so they don't match the table
    # toolbar's "Latest 20 from a total of …" header or "ago" strings
    # that appear in the per-row Age column.

    test "shows Latest + First rows with relative time when preview holds the whole tx history",
         %{conn: conn} do
      body =
        conn
        |> get("/address/0x0000000000000000000000000000000000000002")
        |> html_response(200)

      assert [_, latest_value] = Regex.run(more_info_pair_re("Latest"), body),
             "expected More Info to contain a Latest <label,value> pair"

      assert [_, first_value] = Regex.run(more_info_pair_re("First"), body),
             "expected More Info to contain a First <label,value> pair"

      # Fixture timestamp 2023-11-14 + frozen clock 2026-02-09 →
      # Format.format_relative_time returns a non-empty "X … ago" /
      # "X … from now" string. Validate it's not just "-" or empty,
      # without locking the exact granularity (years/months/days) which
      # can shift if the clock ever moves.
      for v <- [latest_value, first_value] do
        refute v in ["", "-"], "Latest/First value must not be a placeholder"
        assert String.length(v) >= 3, "Latest/First value should be a real timestamp display"
      end
    end

    test "hides Latest / First when no timestamps are available (current 2d API)",
         %{conn: conn} do
      # @addr_hash → @address_txs has items: [] → derive_tx_time_window
      # returns {nil, nil} → template gates hide both rows.
      body =
        conn
        |> get("/address/0x0000000000000000000000000000000000000001")
        |> html_response(200)

      refute Regex.match?(more_info_label_re("Latest"), body),
             "Latest label must be absent when no tx timestamps are known"

      refute Regex.match?(more_info_label_re("First"), body),
             "First label must be absent when no tx timestamps are known"
    end
  end

  defp more_info_label_re(label) do
    ~r{class="address-summary-label">\s*#{Regex.escape(label)}\s*<}
  end

  defp more_info_pair_re(label) do
    ~r{class="address-summary-label">\s*#{Regex.escape(label)}\s*</div>\s*<div\s+class="address-summary-value">\s*([^<]+?)\s*</div>}
  end

  test "GET /address/:hash renders both 0x and Tron-base58 forms of the same account",
       %{conn: conn} do
    # Hardcoded oracle: independently verified against
    # `Chain.Tron.Address.encode/1` in ~/pse/2d. See
    # test/frontend_ex/tron/address_test.exs for unit-level coverage of
    # the converter; this test pins that the Tron-form actually surfaces
    # in the rendered HTML, not just that the converter is wired.
    eth_hex = "0x0000000000000000000000000000000000000001"
    expected_tron = "T9yD14Nj9j7xAB4dbGeiX9h8unkKLxmGkn"

    body = conn |> get("/address/#{eth_hex}") |> html_response(200)

    assert body =~ eth_hex,
           "expected /address/:hash to render the 0x form"

    assert body =~ expected_tron,
           "expected /address/:hash to render the Tron-form alongside the 0x form"
  end

  test "GET /tx/:hash with transaction_type=3 renders the EIP-4844 commit branch",
       %{conn: conn} do
    body =
      conn
      |> get("/tx/0xb10b000000000000000000000000000000000000000000000000000000000000")
      |> html_response(200)

    # 2d ships the type as `transaction_type: 3` (singular). If parse_tx
    # ever regresses to reading only `tx_json["type"]`, @tx.tx_type goes
    # nil and this branch silently disappears under the method-name
    # fallback (a "-" label).
    assert body =~ "EIP-4844 Blob",
           "expected /tx/:hash with transaction_type=3 to render the EIP-4844 commit-tx label"
  end

  test "GET /block/:id formats base_fee_per_gas as USDC, not raw base units",
       %{conn: conn} do
    body = conn |> get("/block/0") |> html_response(200)

    # 1500 base units / 10^6 decimals = 0.0015 USDC. The bug was the
    # template rendering "1500 USDC" — a 10^6 overstatement.
    assert body =~ "0.0015 USDC",
           "expected /block/0 to render base_fee_per_gas as 0.0015 USDC"

    refute body =~ "1500 USDC",
           "tx-detail page must not surface raw base units alongside the USDC label"
  end

  test "GET /tx/:hash/card surfaces stats-derived USDC ticker",
       %{conn: conn} do
    body =
      conn
      |> get("/tx/0xcafe000000000000000000000000000000000000000000000000000000000000/card")
      |> html_response(200)

    assert body =~ "USDC",
           "expected /tx/:hash/card share-card to render the stats-derived ticker"

    refute body =~ ~r/\bETH\b/
  end

  describe "no broken nav links to deleted routes" do
    @addr_hash "0x0000000000000000000000000000000000000001"
    @tx_hash "0xcafe000000000000000000000000000000000000000000000000000000000000"

    @dead_routes [
      "/tokens",
      "/nft-latest-mints",
      "/nft-transfers",
      "/exportData",
      "/token/",
      "/address/#{@addr_hash}/tokens",
      "/address/#{@addr_hash}/token-transfers",
      "/address/#{@addr_hash}/internal",
      "/tx/#{@tx_hash}/internal"
    ]

    test "home page does not link to any deleted route", %{conn: conn} do
      body = conn |> get("/") |> html_response(200)

      for route <- @dead_routes do
        refute body =~ ~s|href="#{route}|,
               "home page links to deleted route #{route}"
      end
    end

    test "address page does not link to any deleted route", %{conn: conn} do
      body = conn |> get("/address/#{@addr_hash}") |> html_response(200)

      for route <- @dead_routes do
        refute body =~ ~s|href="#{route}|,
               "address page links to deleted route #{route}"
      end
    end

    test "tx detail page does not link to any deleted route", %{conn: conn} do
      body = conn |> get("/tx/#{@tx_hash}") |> html_response(200)

      for route <- @dead_routes do
        refute body =~ ~s|href="#{route}|,
               "tx detail page links to deleted route #{route}"
      end
    end
  end
end
