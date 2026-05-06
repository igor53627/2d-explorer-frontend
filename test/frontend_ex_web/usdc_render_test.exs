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
      # Cross-form pair: this single fixture is reused on /, /txs, and
      # /block/:id/txs renderings, so making it cross-broadcast lets each
      # of those surfaces assert per-address primary_kind rendering
      # without dragging in a second fixture wiring.
      "from" => %{
        "hash" => "0x0000000000000000000000000000000000000001",
        "primary_kind" => "eth_rlp"
      },
      "to" => %{
        "hash" => "0x0000000000000000000000000000000000000002",
        "primary_kind" => "tron_pb"
      },
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
      "base_fee_per_gas" => "3",
      # Default tx is eth-broadcasted; the From/To rendering should use
      # EIP-55 checksummed 0x form, not Tron Base58.
      "kind" => "eth_rlp"
    }

    # Failed-tx fixture: status=error, to=null (mirrors what 2d emits for
    # failed Tron broadcasts pre-TASK-56). Defined here (before
    # @transactions_list) so list endpoints can include it without a
    # forward-reference.
    @tx_failed_hash "0xfa11ed000000000000000000000000000000000000000000000000000000fa11"
    @tx_failed_detail %{
      "hash" => @tx_failed_hash,
      "block_number" => 0,
      "transaction_index" => 2,
      "timestamp" => "2023-11-14T22:13:20Z",
      "from" => %{
        "hash" => "0x0000000000000000000000000000000000000001",
        "primary_kind" => "tron_pb"
      },
      "to" => nil,
      "value" => "0",
      "status" => "error",
      "gas_used" => 21_000,
      "gas_limit" => 30_000_000,
      "gas_price" => "0",
      "fee" => %{"value" => "0"},
      "transaction_type" => 0,
      "kind" => "tron_pb"
    }
    @tx_failed_logs %{"items" => [], "next_page_params" => nil}

    # Second normal-tx fixture (status=ok, to=set). Two normal rows
    # alongside one failed row in the listing means a regression that
    # inverts the to=null condition (label rendered on `to`-set rows
    # instead of `to=nil` rows) bumps occurrences of "failed tx" from
    # 1 → 2, tripping the count==1 assertion. With a single normal row
    # the count would silently match either branch.
    @tx_detail_alt %{
      "hash" => "0xa17e7" <> String.duplicate("0", 59),
      "block_number" => 0,
      "transaction_index" => 1,
      "timestamp" => "2023-11-14T22:13:20Z",
      "from" => %{
        "hash" => "0x0000000000000000000000000000000000000006",
        "primary_kind" => "eth_rlp"
      },
      "to" => %{
        "hash" => "0x0000000000000000000000000000000000000007",
        "primary_kind" => "eth_rlp"
      },
      "value" => "200",
      "status" => "ok",
      "transaction_type" => 0,
      "kind" => "eth_rlp"
    }

    @transactions_list %{
      "items" => [@tx_detail, @tx_detail_alt, @tx_failed_detail],
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

    # Cross-form fixture for /tx/:hash detail: eth-broadcast, sender's
    # primary surface is eth (→ EIP-55 0x), recipient's primary is Tron
    # (→ T-Base58). Pins per-address rendering on the tx-detail surface.
    @tx_cross_hash "0xc0055000000000000000000000000000000000000000000000000000000000a4"
    @tx_cross_detail %{
      "hash" => @tx_cross_hash,
      "block_number" => 0,
      "transaction_index" => 0,
      "timestamp" => "2023-11-14T22:13:20Z",
      "from" => %{
        "hash" => "0x0000000000000000000000000000000000000004",
        "primary_kind" => "eth_rlp"
      },
      "to" => %{
        "hash" => "0x0000000000000000000000000000000000000005",
        "primary_kind" => "tron_pb"
      },
      "value" => "100",
      "status" => "ok",
      "gas_used" => 21_000,
      "gas_limit" => 30_000_000,
      "gas_price" => "5",
      "fee" => %{"value" => "105000"},
      "transaction_type" => 0,
      "kind" => "eth_rlp"
    }
    @tx_cross_logs %{"items" => [], "next_page_params" => nil}

    # to=null + status=ok fixture: hypothetical edge case (2d empirically
    # never produces this today, but we shouldn't mislabel it as failed).
    @tx_orphan_hash "0x0177ba0000000000000000000000000000000000000000000000000000000077"
    @tx_orphan_detail %{
      "hash" => @tx_orphan_hash,
      "block_number" => 0,
      "transaction_index" => 3,
      "timestamp" => "2023-11-14T22:13:20Z",
      "from" => %{
        "hash" => "0x0000000000000000000000000000000000000001",
        "primary_kind" => "eth_rlp"
      },
      "to" => nil,
      "value" => "0",
      "status" => "ok",
      "gas_used" => 21_000,
      "gas_limit" => 30_000_000,
      "gas_price" => "0",
      "fee" => %{"value" => "0"},
      "transaction_type" => 0,
      "kind" => "eth_rlp"
    }
    @tx_orphan_logs %{"items" => [], "next_page_params" => nil}

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

    # Block 0 transactions list — three items (two normal + one failed)
    # so a regression that inverts the to=null condition trips count==1
    # (would render "failed tx" on the two normal rows). Same defensive
    # rationale as @transactions_list.
    @block_txs %{
      "items" => [@tx_detail, @tx_detail_alt, @tx_failed_detail],
      "next_page_params" => nil
    }

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
      # 3 outbound txs in @addr_with_ts_txs (cross-form + normal-2 +
      # failed). 3 rows means a regression that inverts the to=null
      # condition mislabels the two non-failed rows, bumping count to 2
      # — caught by the count==1 assertion. The
      # `derive_tx_time_window/2` "First exact" branch keys off
      # length(preview) == transactions_count, so this stays in lockstep.
      "transactions_count" => 3
    }
    @addr_with_ts_txs %{
      "items" => [
        %{
          "hash" => "0xab" <> String.duplicate("0", 62),
          "block_number" => 0,
          "transaction_index" => 0,
          "timestamp" => "2023-11-14T22:13:20Z",
          # Cross-broadcast: tx itself is Tron-broadcasted (kind=tron_pb)
          # AND the sender's primary surface is also Tron — so From
          # renders as T…. The recipient (0x…0003) has primary=eth_rlp
          # in their history, so To renders as 0x… even though *this*
          # tx was Tron-broadcast. Pins per-address rendering: kind on
          # its own would force both sides to T.
          "from" => %{"hash" => @addr_with_ts_hash, "primary_kind" => "tron_pb"},
          "to" => %{
            "hash" => "0x0000000000000000000000000000000000000003",
            "primary_kind" => "eth_rlp"
          },
          "value" => "100",
          "status" => "ok",
          "transaction_type" => 0,
          "kind" => "tron_pb"
        },
        # Second normal-tx so the listing has 2 normal + 1 failed —
        # makes count==1 catch the inverted-conditional regression.
        %{
          "hash" => "0xa2" <> String.duplicate("0", 62),
          "block_number" => 0,
          "transaction_index" => 1,
          "timestamp" => "2023-11-14T22:13:20Z",
          "from" => %{"hash" => @addr_with_ts_hash, "primary_kind" => "tron_pb"},
          "to" => %{
            "hash" => "0x0000000000000000000000000000000000000008",
            "primary_kind" => "eth_rlp"
          },
          "value" => "50",
          "status" => "ok",
          "transaction_type" => 0,
          "kind" => "tron_pb"
        },
        # Failed tx in this address's list — pins the "failed tx" label
        # rendering on the /address row surface.
        %{
          "hash" => "0xfa" <> String.duplicate("0", 62),
          "block_number" => 0,
          "transaction_index" => 2,
          "timestamp" => "2023-11-14T22:13:20Z",
          "from" => %{"hash" => @addr_with_ts_hash, "primary_kind" => "tron_pb"},
          "to" => nil,
          "value" => "0",
          "status" => "error",
          "transaction_type" => 0,
          "kind" => "tron_pb"
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
              rest == @tx_cross_hash -> @tx_cross_detail
              rest == "#{@tx_cross_hash}/logs" -> @tx_cross_logs
              rest == @tx_failed_hash -> @tx_failed_detail
              rest == "#{@tx_failed_hash}/logs" -> @tx_failed_logs
              rest == @tx_orphan_hash -> @tx_orphan_detail
              rest == "#{@tx_orphan_hash}/logs" -> @tx_orphan_logs
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

  test "GET /address/:hash renders cross-form From/To by per-address primary_kind",
       %{conn: conn} do
    # Fixture: tx kind=tron_pb, from.primary_kind=tron_pb,
    # to.primary_kind=eth_rlp → expect From rendered as T… (Tron Base58)
    # and To as 0x… (truncated EIP-55) on the SAME row. This is the
    # whole point of TASK-13.13 / TASK-55 — kind on its own would force
    # both sides to T.
    body =
      conn
      |> get("/address/0x0000000000000000000000000000000000000002")
      |> html_response(200)

    expected_from_tron =
      FrontendEx.Tron.Address.from_eth_hex("0x0000000000000000000000000000000000000002")

    assert is_binary(expected_from_tron) and String.starts_with?(expected_from_tron, "T")

    # From column: truncated T-form (Tron Base58, sender's primary).
    assert body =~ FrontendEx.Format.truncate_addr_classic(expected_from_tron),
           "expected truncated Tron-form for From column (sender primary=tron_pb)"

    # To column: truncated 0x-form (recipient's primary=eth_rlp), NOT
    # the Tron derivation of 0x…0003. If per-address rendering ever
    # regresses to per-tx kind, this assertion catches it.
    truncated_to_eth =
      FrontendEx.Format.truncate_addr_classic("0x0000000000000000000000000000000000000003")

    assert body =~ truncated_to_eth,
           "expected truncated 0x-form for To column (recipient primary=eth_rlp)"

    truncated_to_tron =
      FrontendEx.Format.truncate_addr_classic(
        FrontendEx.Tron.Address.from_eth_hex("0x0000000000000000000000000000000000000003")
      )

    refute body =~ truncated_to_tron,
           "To column must NOT render the Tron-form when recipient primary=eth_rlp " <>
             "(would mean per-tx kind is still driving both sides — regression of TASK-13.13)"

    # Link target stays on canonical 0x regardless of display surface.
    assert body =~ ~s{href="/address/0x0000000000000000000000000000000000000002"},
           "row link must still point at the canonical /address/0x…"
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

  test "GET /tx/:hash renders Transaction Action as 'Transfer N USDC to <addr>' for value tx",
       %{conn: conn} do
    body =
      conn
      |> get("/tx/0xcafe000000000000000000000000000000000000000000000000000000000000")
      |> html_response(200)

    # @tx_detail has value=100 (= 0.0001 USDC at 6 decimals), to=set,
    # method=nil, tx_type=2. Action row should describe the transfer
    # Etherscan-style: "Transfer 0.0001 USDC to 0x…0002".
    assert body =~ ~r{Transfer\s+0\.000100\s+USDC\s+to\s+<a},
           "expected Etherscan-style 'Transfer N USDC to ADDR' Transaction Action"
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

  describe "per-address primary_kind cross-form across listing surfaces (roborev)" do
    # /address has its own dedicated test above. roborev flagged that
    # the home tile, /txs list, and /block/:id/txs surfaces went
    # uncovered. The same @tx_detail fixture (from.primary=eth_rlp,
    # to.primary=tron_pb) is reused on all three so the assertions just
    # need to verify the rendered HTML carries the expected mix.

    @cross_from "0x0000000000000000000000000000000000000001"
    @cross_to "0x0000000000000000000000000000000000000002"

    test "GET /  renders cross-form on the home tx tile", %{conn: conn} do
      body = conn |> get("/") |> html_response(200)

      to_tron_truncated =
        FrontendEx.Format.truncate_addr(
          FrontendEx.Tron.Address.from_eth_hex(@cross_to)
        )

      from_eth_truncated = FrontendEx.Format.truncate_addr(@cross_from)

      assert body =~ from_eth_truncated,
             "home tile must render From in 0x form (from.primary=eth_rlp)"

      assert body =~ to_tron_truncated,
             "home tile must render To in T form (to.primary=tron_pb)"
    end

    test "GET /txs renders cross-form on the list rows", %{conn: conn} do
      body = conn |> get("/txs") |> html_response(200)

      to_tron_truncated =
        FrontendEx.Format.truncate_addr_classic(
          FrontendEx.Tron.Address.from_eth_hex(@cross_to)
        )

      from_eth_truncated = FrontendEx.Format.truncate_addr_classic(@cross_from)

      assert body =~ from_eth_truncated,
             "/txs row must render From in 0x form"

      assert body =~ to_tron_truncated,
             "/txs row must render To in T form"
    end

    test "GET /block/:id/txs renders cross-form in the block-tx list", %{conn: conn} do
      body = conn |> get("/block/0/txs") |> html_response(200)

      to_tron = FrontendEx.Tron.Address.from_eth_hex(@cross_to)

      assert body =~ @cross_from,
             "/block/:id/txs From cell must contain the 0x form"

      assert body =~ to_tron,
             "/block/:id/txs To cell must contain the T form"
    end
  end

  describe "share-card + OG image cross-form (ultrareview merged_bug_004)" do
    # Pre-fix tx_card.html.eex and og_image SVG used .hash (canonical
    # 0x) for From/To truncation, bypassing the per-address `display`
    # field. Cross-broadcast tx with from.primary=eth_rlp,
    # to.primary=tron_pb must surface 0x-form for From and Tron-form
    # for To on both surfaces.

    test "GET /tx/:hash/card renders cross-form using per-address display",
         %{conn: conn} do
      body =
        conn
        |> get("/tx/0xc0055000000000000000000000000000000000000000000000000000000000a4/card")
        |> html_response(200)

      expected_to_tron =
        FrontendEx.Tron.Address.from_eth_hex("0x0000000000000000000000000000000000000005")

      truncated_to = FrontendEx.Format.truncate_hash(expected_to_tron)

      assert body =~ truncated_to,
             "share-card To column must show truncated Tron-form when to.primary=tron_pb"

      # From: EIP-55 checksum on all-zeros+4 is identical to lowercase
      # (no a-f digits to flip). truncate_hash → "0x0000...0004".
      truncated_from =
        FrontendEx.Format.truncate_hash(
          FrontendEx.Format.checksum_eth_address("0x0000000000000000000000000000000000000004")
        )

      assert body =~ truncated_from,
             "share-card From column must show truncated 0x form (from.primary=eth_rlp)"
    end

    test "GET /tx/:hash/og-image.svg renders cross-form display",
         %{conn: conn} do
      conn =
        conn
        |> get("/tx/0xc0055000000000000000000000000000000000000000000000000000000000a4/og-image.svg")

      body = conn.resp_body
      assert conn.status == 200

      expected_to_tron =
        FrontendEx.Tron.Address.from_eth_hex("0x0000000000000000000000000000000000000005")

      truncated_to = FrontendEx.Format.truncate_hash(expected_to_tron)

      assert body =~ truncated_to,
             "OG SVG To text must render truncated Tron-form when to.primary=tron_pb"

      truncated_from =
        FrontendEx.Format.truncate_hash(
          FrontendEx.Format.checksum_eth_address("0x0000000000000000000000000000000000000004")
        )

      assert body =~ truncated_from,
             "OG SVG From text must render truncated 0x form (from.primary=eth_rlp)"
    end
  end

  describe "GET /tx/:hash — per-address primary_kind cross-form (TASK-13.13)" do
    # The /address regression test pins the table-row cells. tx-detail
    # uses a different code path (tx_controller.parse_tx + EIP-55
    # checksum on the eth side). Pin both surfaces independently so a
    # regression on one doesn't hide behind the other.

    test "renders 0xFrom + TTo when from.primary=eth_rlp and to.primary=tron_pb",
         %{conn: conn} do
      body =
        conn
        |> get("/tx/0xc0055000000000000000000000000000000000000000000000000000000000a4")
        |> html_response(200)

      # From: EIP-55 checksummed 0x form (sender's primary=eth_rlp).
      assert body =~ FrontendEx.Format.checksum_eth_address(
                       "0x0000000000000000000000000000000000000004"
                     ),
             "expected EIP-55 checksummed 0x form for From (from.primary=eth_rlp)"

      # To: Tron Base58 form (recipient's primary=tron_pb).
      expected_to_tron =
        FrontendEx.Tron.Address.from_eth_hex("0x0000000000000000000000000000000000000005")

      assert body =~ expected_to_tron,
             "expected Tron Base58 for To (to.primary=tron_pb)"
    end
  end

  describe "failed-tx label on listing surfaces (roborev)" do
    # @transactions_list, @block_txs, @addr_with_ts_txs each include
    # exactly ONE failed (status=error, to=null) item alongside ≥1
    # normal item. We assert occurrence-count == 1, not just presence,
    # so a regression that accidentally labels every row as "failed tx"
    # (e.g. the conditional moving outside the to=null branch) gets
    # caught — substring-match would happily pass with the leak.

    defp count_occurrences(haystack, needle) when is_binary(haystack) and is_binary(needle) do
      haystack |> String.split(needle) |> length() |> Kernel.-(1)
    end

    test "GET /txs renders 'failed tx' on exactly the failed row",
         %{conn: conn} do
      body = conn |> get("/txs") |> html_response(200)

      assert count_occurrences(body, "failed tx") == 1,
             "/txs must render 'failed tx' on exactly one row " <>
               "(label leaking onto normal rows is a regression)"
    end

    test "GET /block/:id/txs renders 'failed tx' on exactly the failed row",
         %{conn: conn} do
      body = conn |> get("/block/0/txs") |> html_response(200)

      assert count_occurrences(body, "failed tx") == 1,
             "/block/:id/txs must render 'failed tx' on exactly one row"
    end

    test "GET /address/:hash renders 'failed tx' on exactly the failed row",
         %{conn: conn} do
      body =
        conn
        |> get("/address/0x0000000000000000000000000000000000000002")
        |> html_response(200)

      assert count_occurrences(body, "failed tx") == 1,
             "/address row must render 'failed tx' on exactly one row"
    end

    test "GET / renders 'failed tx' on the home tile (ultrareview bug_006)",
         %{conn: conn} do
      # Pre-fix the home tile hardcoded 'Contract Create' for tx.to=nil,
      # bypassing the status-gated label. @transactions_list contains
      # one failed item, so the tile must surface it via the same label
      # as every other listing surface.
      #
      # The bare substring "failed tx" also appears once inside the inline
      # `<script>` block (JS realtime fallback string), so we anchor on
      # the SSR-only markup pattern `To <span class="text-muted">failed
      # tx<` which the JS literal doesn't reproduce.
      body = conn |> get("/") |> html_response(200)

      ssr_pattern = ~r/To\s+<span class="text-muted">failed tx</

      assert length(Regex.scan(ssr_pattern, body)) == 1,
             "home tile must render 'failed tx' on exactly one row " <>
               "(was hardcoded 'Contract Create' before ultrareview fix)"

      refute body =~ "Contract Create",
             "home tile must not render the legacy 'Contract Create' label"
    end
  end

  describe "failed-tx label on /tx/:hash share-card and OG meta (roborev)" do
    test "GET /tx/:hash share-card renders 'failed tx' when status=error+to=null",
         %{conn: conn} do
      body =
        conn
        |> get("/tx/0xfa11ed000000000000000000000000000000000000000000000000000000fa11/card")
        |> html_response(200)

      assert body =~ "failed tx",
             "share-card 'address-name' must show 'failed tx' for status=error+to=null"
    end

    test "GET /tx/:hash share-card renders neutral '—' when status=ok+to=null",
         %{conn: conn} do
      body =
        conn
        |> get("/tx/0x0177ba0000000000000000000000000000000000000000000000000000000077/card")
        |> html_response(200)

      refute body =~ "failed tx",
             "share-card must NOT label as 'failed tx' when status is not error"

      # Positive: neutral placeholder is what actually renders inside
      # the address-name slot. Anchored to that class so we don't match
      # "—" appearing elsewhere on the card (e.g. timestamp fallback).
      assert body =~ ~r{<div class="address-name">\s*—\s*</div>},
             "share-card 'address-name' must render neutral '—' for status=ok+to=null"
    end

    test "GET /tx/:hash OG meta description includes 'failed tx' when status=error",
         %{conn: conn} do
      body =
        conn
        |> get("/tx/0xfa11ed000000000000000000000000000000000000000000000000000000fa11")
        |> html_response(200)

      # og:description and twitter:description both go through the same
      # status-gated label.
      assert body =~ ~r{<meta property="og:description" content="[^"]*failed tx},
             "og:description must include 'failed tx' for status=error+to=null"

      assert body =~ ~r{<meta name="twitter:description" content="[^"]*failed tx},
             "twitter:description must include 'failed tx' for status=error+to=null"
    end

    test "GET /tx/:hash OG/Twitter meta has neutral em-dash when status=ok+to=null",
         %{conn: conn} do
      body =
        conn
        |> get("/tx/0x0177ba0000000000000000000000000000000000000000000000000000000077")
        |> html_response(200)

      refute body =~ ~r{<meta property="og:description" content="[^"]*failed tx},
             "og:description must NOT label as 'failed tx' when status is not error"

      refute body =~ ~r{<meta name="twitter:description" content="[^"]*failed tx},
             "twitter:description must NOT label as 'failed tx' when status is not error"

      # Positive: both meta tags render the neutral em-dash.
      assert body =~ ~r{<meta property="og:description" content="[^"]*—},
             "og:description must contain neutral '—' for status=ok+to=null"

      assert body =~ ~r{<meta name="twitter:description" content="[^"]*—},
             "twitter:description must contain neutral '—' for status=ok+to=null"
    end
  end

  describe "GET /tx/:hash — failed-tx label is status-gated (roborev)" do
    # roborev flagged that "failed tx" was selected purely from to=null
    # without checking status. Pins both branches: error → "failed tx",
    # else → neutral "—". Sterile against future cases where 2d emits
    # to=null with a non-error status.

    test "to=null + status=error → '[failed tx]'", %{conn: conn} do
      body =
        conn
        |> get("/tx/0xfa11ed000000000000000000000000000000000000000000000000000000fa11")
        |> html_response(200)

      assert body =~ "[failed tx]",
             "expected [failed tx] label when status=error AND to=null"

      refute body =~ "[—]",
             "neutral em-dash must NOT appear when status=error"
    end

    test "to=null + status=ok → neutral '[—]'", %{conn: conn} do
      body =
        conn
        |> get("/tx/0x0177ba0000000000000000000000000000000000000000000000000000000077")
        |> html_response(200)

      assert body =~ "[—]",
             "expected neutral [—] label when to=null AND status is not error"

      refute body =~ "[failed tx]",
             "must NOT label as failed tx when status is not error"
    end
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
