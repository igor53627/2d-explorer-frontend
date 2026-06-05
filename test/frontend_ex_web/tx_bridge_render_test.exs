defmodule FrontendExWeb.TxBridgeRenderTest do
  @moduledoc """
  Render tests for `/tx/:hash` bridge card (TASK-49).
  """

  use FrontendExWeb.ConnCase, async: false

  @stats %{
    "total_blocks" => 1,
    "total_transactions" => 1,
    "latest_block_number" => 0,
    "native_coin" => %{"symbol" => "USDC", "decimals" => 6}
  }

  @bridge_precompile "0x2d0000000000000000000000000000000000000003"
  @htlc_precompile "0x2d0000000000000000000000000000000000000001"

  @tx_bridge_lock "0xface000000000000000000000000000000000000000000000000000000000001"
  @tx_htlc_settle "0xface000000000000000000000000000000000000000000000000000000000002"
  @tx_htlc_refund "0xface000000000000000000000000000000000000000000000000000000000003"
  @tx_plain "0xface000000000000000000000000000000000000000000000000000000000004"
  @tx_bridge_miss "0xface000000000000000000000000000000000000000000000000000000000005"
  @plain_to "0x0000000000000000000000000000000000000002"

  @bridge_lock_payload %{
    "kind" => "bridge_lock",
    "data" => %{
      "amount" => "1000000",
      "eth_event_id" => "0x8a26217d2693abf40185791db4ca9889b322f73e5645ab1c2842139185c1b66c",
      "htlc_hash" => "0xc0de000000000000000000000000000000000000000000000000000000000000",
      "preimage_hash" => "0xc0de000000000000000000000000000000000000000000000000000000000000",
      "recipient" => "0xfe00000000000000000000000000000000000000",
      "source_chain_id" => 1,
      "source_log_index" => 7,
      "source_tx_hash" => "0xabcd000000000000000000000000000000000000000000000000000000000000",
      "deadline_ms" => 1_700_000_000_000,
      "bridge_mint" => %{
        "tx_hash_2d" => @tx_bridge_lock,
        "amount" => "1000000",
        "eth_event_id" => "0x8a26217d2693abf40185791db4ca9889b322f73e5645ab1c2842139185c1b66c"
      },
      "htlc_swap" => %{
        "status" => "locked",
        "amount" => "1000000",
        "receiver" => "0xfe00000000000000000000000000000000000000"
      }
    }
  }

  @htlc_settle_payload %{
    "kind" => "htlc_settle",
    "data" => %{
      "lock_id" => "0xee00000000000000000000000000000000000000000000000000000000000000",
      "preimage" => "0xbe00000000000000000000000000000000000000000000000000000000000000",
      "htlc_swap" => %{
        "status" => "claimed",
        "amount" => "1000000",
        "receiver" => "0xfe00000000000000000000000000000000000000"
      }
    }
  }

  @htlc_refund_payload %{
    "kind" => "htlc_refund",
    "data" => %{
      "lock_id" => "0xee00000000000000000000000000000000000000000000000000000000000000",
      "htlc_swap" => %{
        "status" => "refunded",
        "amount" => "1000000",
        "receiver" => "0xfe00000000000000000000000000000000000000"
      }
    }
  }

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
            Application.get_env(:frontend_ex, :tx_bridge_test_stats)

          String.starts_with?(path, "/api/v2/transactions/") and
              String.ends_with?(path, "/bridge") ->
            Application.get_env(:frontend_ex, :tx_bridge_test_bridge_payload)

          String.starts_with?(path, "/api/v2/transactions/") ->
            Application.get_env(:frontend_ex, :tx_bridge_test_tx_payload)

          path == "/api/v2/blocks" ->
            %{"items" => [%{"height" => 0}]}

          String.starts_with?(path, "/api/v2/transactions/") and String.ends_with?(path, "/logs") ->
            %{"items" => []}

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
    Application.put_env(:frontend_ex, :blockscout_request_adapter, Adapter)
    Application.put_env(:frontend_ex, :tx_bridge_test_stats, @stats)

    on_exit(fn ->
      Application.delete_env(:frontend_ex, :blockscout_request_adapter)
      Application.delete_env(:frontend_ex, :tx_bridge_test_stats)
      Application.delete_env(:frontend_ex, :tx_bridge_test_tx_payload)
      Application.delete_env(:frontend_ex, :tx_bridge_test_bridge_payload)
    end)

    :ok
  end

  defp put_tx_payload(tx_hash, to_hash) do
    Application.put_env(:frontend_ex, :tx_bridge_test_tx_payload, %{
      "hash" => tx_hash,
      "block_number" => 0,
      "from" => %{"hash" => "0x0000000000000000000000000000000000000001"},
      "to" => %{"hash" => to_hash},
      "value" => "0",
      "gas_used" => 21_000,
      "gas_price" => "0",
      "status" => "ok",
      "kind" => "eth_rlp"
    })
  end

  describe "GET /tx/:hash bridge card" do
    test "renders bridge_lock card for bridge precompile tx", %{conn: conn} do
      put_tx_payload(@tx_bridge_lock, @bridge_precompile)
      Application.put_env(:frontend_ex, :tx_bridge_test_bridge_payload, @bridge_lock_payload)

      html = conn |> get("/tx/#{@tx_bridge_lock}") |> html_response(200)

      assert html =~ ~s(id="bridge-tx-card")
      assert html =~ "Bridge lock"
      assert html =~ "HTLC hash"
      assert html =~ "etherscan.io/tx/"
      assert html =~ "/bridges"
    end

    test "renders htlc_settle card", %{conn: conn} do
      put_tx_payload(@tx_htlc_settle, @htlc_precompile)
      Application.put_env(:frontend_ex, :tx_bridge_test_bridge_payload, @htlc_settle_payload)

      html = conn |> get("/tx/#{@tx_htlc_settle}") |> html_response(200)

      assert html =~ ~s(data-bridge-kind="htlc_settle")
      assert html =~ "HTLC settle"
      assert html =~ "Preimage"
    end

    test "renders htlc_refund card", %{conn: conn} do
      put_tx_payload(@tx_htlc_refund, @htlc_precompile)
      Application.put_env(:frontend_ex, :tx_bridge_test_bridge_payload, @htlc_refund_payload)

      html = conn |> get("/tx/#{@tx_htlc_refund}") |> html_response(200)

      assert html =~ ~s(data-bridge-kind="htlc_refund")
      assert html =~ "HTLC refund"
    end

    test "no bridge card for non-bridge tx", %{conn: conn} do
      put_tx_payload(@tx_plain, @plain_to)

      html = conn |> get("/tx/#{@tx_plain}") |> html_response(200)

      refute html =~ ~s(id="bridge-tx-card")
    end

    test "bridge candidate but bridge endpoint 404 — no card, page still 200", %{conn: conn} do
      put_tx_payload(@tx_bridge_miss, @bridge_precompile)
      Application.put_env(:frontend_ex, :tx_bridge_test_bridge_payload, nil)

      html = conn |> get("/tx/#{@tx_bridge_miss}") |> html_response(200)

      refute html =~ ~s(id="bridge-tx-card")
      assert html =~ "Transaction Details"
    end
  end
end
