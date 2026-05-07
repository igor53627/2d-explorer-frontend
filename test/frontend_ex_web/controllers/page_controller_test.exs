defmodule FrontendExWeb.HomeControllerTest do
  use FrontendExWeb.ConnCase, async: false

  @miner_hash "0x2d00000000000000000000000000000000000001"
  @block_hash "0x" <> String.duplicate("c0de", 16)

  @stats %{
    "total_blocks" => 1,
    "total_transactions" => 0,
    "latest_block_number" => 0,
    "native_coin" => %{"symbol" => "USDC", "decimals" => 6}
  }

  @blocks_list %{
    "items" => [
      %{
        "height" => 0,
        "hash" => @block_hash,
        "parent_hash" => "0x" <> String.duplicate("0", 64),
        "timestamp" => "2026-02-09T11:55:00Z",
        "transaction_count" => 0,
        "miner" => %{"hash" => @miner_hash}
      }
    ],
    "next_page_params" => nil
  }

  @transactions_list %{"items" => [], "next_page_params" => nil}

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
            Application.get_env(:frontend_ex, :home_test_stats_payload)

          path == "/api/v2/blocks" ->
            Application.get_env(:frontend_ex, :home_test_blocks_payload)

          path == "/api/v2/transactions" ->
            Application.get_env(:frontend_ex, :home_test_txs_payload)

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

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "2D Explorer"
  end

  describe "home block tile metadata flag (FF_HOME_BLOCK_META_FULL)" do
    setup do
      prev_home = Application.get_env(:frontend_ex, :home, [])
      prev_adapter = Application.get_env(:frontend_ex, :blockscout_request_adapter)

      Application.put_env(:frontend_ex, :blockscout_request_adapter, Adapter)
      Application.put_env(:frontend_ex, :home_test_stats_payload, @stats)
      Application.put_env(:frontend_ex, :home_test_blocks_payload, @blocks_list)
      Application.put_env(:frontend_ex, :home_test_txs_payload, @transactions_list)

      _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)
      _ = FrontendEx.Cache.clear(FrontendEx.ApiSWRCache)

      on_exit(fn ->
        Application.put_env(:frontend_ex, :home, prev_home)
        Application.put_env(:frontend_ex, :blockscout_request_adapter, prev_adapter)
        Application.delete_env(:frontend_ex, :home_test_stats_payload)
        Application.delete_env(:frontend_ex, :home_test_blocks_payload)
        Application.delete_env(:frontend_ex, :home_test_txs_payload)

        # Clear caches AFTER restoring the prior adapter — without this,
        # any /api/v2/* response cached during this test under the inline
        # Adapter would survive into the next async test, where the
        # restored (real or default) adapter would never be hit. Order-
        # dependent flakes are exactly what compact roborev #2237 flagged.
        _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)
        _ = FrontendEx.Cache.clear(FrontendEx.ApiSWRCache)
      end)

      :ok
    end

    test "hides Proposer and Fees rows by default", %{conn: conn} do
      Application.put_env(:frontend_ex, :home, block_meta_full: false)
      html = conn |> get(~p"/") |> html_response(200)

      # The SSR loop now actually iterates over `@blocks` (one stubbed item)
      # so absence of `block-miner`/`block-reward` proves the flag-gated
      # branches did not render. Without the inline adapter the blocks list
      # would be empty and `refute` would pass for the wrong reason.
      refute html =~ ~s(<div class="block-miner">)
      refute html =~ ~s(<div class="block-reward">)
    end

    test "shows Proposer and Fees rows when flag is true", %{conn: conn} do
      Application.put_env(:frontend_ex, :home, block_meta_full: true)
      html = conn |> get(~p"/") |> html_response(200)

      # Two-surface check: the SSR-rendered block-item div carries the
      # miner hash literal (proves the SSR iteration with flag=true), and
      # the JS template carries the same div (proves the live-update path
      # is also flag-gated). Without an inline adapter the SSR check would
      # silently match only the JS-template surface — which earlier review
      # bots correctly flagged.
      assert html =~ ~s(<div class="block-miner">)
      assert html =~ ~s(<div class="block-reward">)
      assert html =~ "Proposer"
      assert html =~ ~r/Fees 0 [A-Z]+/

      # SSR-only signal: the stubbed miner address is rendered into a real
      # block-item, not into the JS template (which uses `${miner}`
      # placeholders, not literal addresses). Catching the literal here
      # locks the test to the SSR path the user actually sees on first
      # paint.
      assert html =~ @miner_hash
    end
  end
end
