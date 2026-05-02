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
          "tx_count" => 1,
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
      "gas_used" => 21_000,
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

    @impl true
    def request_raw(url) when is_binary(url) do
      uri = URI.parse(url)
      path = uri.path || ""

      body =
        case path do
          "/api/v2/stats" -> @stats
          "/api/v2/blocks" -> @blocks_list
          "/api/v2/transactions" -> @transactions_list
          "/api/v2/transactions/" <> rest ->
            cond do
              rest == @tx_hash -> @tx_detail
              rest == "#{@tx_hash}/logs" -> @tx_logs
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
  end
end
