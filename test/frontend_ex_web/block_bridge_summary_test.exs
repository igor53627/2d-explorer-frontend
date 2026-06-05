defmodule FrontendExWeb.BlockBridgeSummaryTest do
  use FrontendExWeb.ConnCase, async: false

  alias FrontendEx.TestSupport.Golden
  alias FrontendExWeb.BlockHTML

  import Phoenix.HTML, only: [safe_to_string: 1]

  @golden_dir Path.expand("../golden/block_bridge", __DIR__)

  @bridge "0x2d0000000000000000000000000000000000000003"
  @htlc "0x2d0000000000000000000000000000000000000001"
  @other "0x0000000000000000000000000000000000000002"

  @stats %{
    "total_blocks" => 1,
    "total_transactions" => 1,
    "latest_block_number" => 11,
    "native_coin" => %{"symbol" => "USDC", "decimals" => 6}
  }

  defmodule Adapter do
    @moduledoc false
    @behaviour FrontendEx.Blockscout.RequestAdapter

    @impl true
    def request_raw(url) when is_binary(url) do
      uri = URI.parse(url)
      path = uri.path || ""
      script = Application.get_env(:frontend_ex, :block_test_script, %{})

      body =
        case path do
          "/api/v2/stats" ->
            Map.get(script, :stats)

          "/api/v2/blocks/" <> rest ->
            case String.split(rest, "/", parts: 2) do
              [height, "transactions"] -> get_in(script, [:txs, height])
              [height, _] -> get_in(script, [:blocks, height])
              [height] -> get_in(script, [:blocks, height])
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

  setup do
    prev_adapter = Application.get_env(:frontend_ex, :blockscout_request_adapter)
    Application.put_env(:frontend_ex, :blockscout_request_adapter, Adapter)
    Application.put_env(:frontend_ex, :block_test_script, %{stats: @stats, blocks: %{}, txs: %{}})

    _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)
    _ = FrontendEx.Cache.clear(FrontendEx.ApiSWRCache)

    on_exit(fn ->
      Application.put_env(:frontend_ex, :blockscout_request_adapter, prev_adapter)
      Application.delete_env(:frontend_ex, :block_test_script)

      _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)
      _ = FrontendEx.Cache.clear(FrontendEx.ApiSWRCache)
    end)

    :ok
  end

  defp render_summary(count) do
    bridge_ops =
      if count == 0 do
        nil
      else
        %{count: count, block_height: 42, bridges_href: "/bridges"}
      end

    BlockHTML.bridge_ops_summary(%{bridge_ops: bridge_ops})
    |> safe_to_string()
  end

  defp tx(to_hash) do
    %{
      "hash" => "0x" <> Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
      "from" => %{"hash" => @other, "primary_kind" => "eth_rlp"},
      "to" => if(to_hash, do: %{"hash" => to_hash, "primary_kind" => "eth_rlp"}, else: nil),
      "value" => "0",
      "status" => "ok",
      "gas_used" => 0,
      "gas_price" => "0"
    }
  end

  defp queue_block!(height, tx_items) do
    block = %{
      "height" => height,
      "hash" => "0x" <> String.duplicate("a", 64),
      "parent_hash" => "0x" <> String.duplicate("b", 64),
      "timestamp" => "2023-11-14T22:13:20Z",
      "transaction_count" => length(tx_items),
      "miner" => %{"hash" => @other}
    }

    prev =
      if height > 0,
        do: %{
          "height" => height - 1,
          "hash" => "0x" <> String.duplicate("c", 64),
          "parent_hash" => "0x" <> String.duplicate("d", 64),
          "timestamp" => "2023-11-14T22:12:00Z",
          "transaction_count" => 0,
          "miner" => %{"hash" => @other}
        },
        else: nil

    h = Integer.to_string(height)

    script =
      Application.get_env(:frontend_ex, :block_test_script, %{stats: @stats, blocks: %{}, txs: %{}})

    blocks = Map.put(script.blocks, h, block)
    blocks = if prev, do: Map.put(blocks, Integer.to_string(height - 1), prev), else: blocks

    txs = Map.put(script.txs, h, %{"items" => tx_items, "next_page_params" => nil})

    Application.put_env(:frontend_ex, :block_test_script, %{script | blocks: blocks, txs: txs})

    _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)
    _ = FrontendEx.Cache.clear(FrontendEx.ApiSWRCache)
  end

  describe "bridge_ops_summary partial" do
    test "golden zero bridge ops — empty fragment" do
      Golden.assert_golden!(Path.join(@golden_dir, "zero.html"), render_summary(0))
    end

    test "golden one bridge op" do
      Golden.assert_golden!(Path.join(@golden_dir, "one.html"), render_summary(1))
    end

    test "golden multiple bridge ops" do
      Golden.assert_golden!(Path.join(@golden_dir, "many.html"), render_summary(3))
    end
  end

  describe "GET /block/:id bridge summary integration" do
    test "no panel when block has no bridge txs", %{conn: conn} do
      queue_block!(10, [tx(@other)])
      html = conn |> get("/block/10") |> html_response(200)

      refute html =~ ~s|<section class="bridge-ops-summary|
      refute html =~ "data-bridge-ops-count"
    end

    test "panel counts bridge precompile txs", %{conn: conn} do
      queue_block!(11, [tx(@other), tx(@bridge), tx(@htlc)])
      html = conn |> get("/block/11") |> html_response(200)

      assert html =~ ~s|<section class="bridge-ops-summary|
      assert html =~ ~s(data-bridge-ops-count="2")
      assert html =~ "bridge ops"
      assert html =~ ~s(href="/bridges")
      assert html =~ "block #11"
    end
  end
end