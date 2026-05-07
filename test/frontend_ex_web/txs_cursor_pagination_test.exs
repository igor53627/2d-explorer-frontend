defmodule FrontendExWeb.TxsCursorPaginationTest do
  # Mutates global Application env (request adapter), so must be serial.
  use FrontendExWeb.ConnCase, async: false

  defmodule Adapter do
    @moduledoc false
    @behaviour FrontendEx.Blockscout.RequestAdapter

    @stats %{
      "coin_price" => "3088.44",
      "gas_prices" => %{"average" => %{"price" => 1.2}},
      "total_transactions" => "1234567"
    }

    @txs_page_1 %{
      "items" => [
        %{
          "hash" => "0x" <> String.duplicate("1", 64),
          "method" => "0x82ad56cb",
          "block_number" => 7_000_000,
          "timestamp" => "2026-02-09T11:59:00+00:00",
          "from" => %{"hash" => "0x" <> String.duplicate("2", 40)},
          "to" => %{"hash" => "0x" <> String.duplicate("3", 40)},
          "value" => "0",
          "fee" => %{"value" => "1000000000000000"}
        }
      ],
      "next_page_params" => %{
        "items_count" => 50,
        "block_number" => 10_217_968,
        "index" => 82
      }
    }

    @txs_page_2 %{
      "items" => [
        %{
          "hash" => "0x" <> String.duplicate("a", 64),
          "method" => "0x82ad56cb",
          "block_number" => 6_999_999,
          "timestamp" => "2026-02-09T11:58:00+00:00",
          "from" => %{"hash" => "0x" <> String.duplicate("b", 40)},
          "to" => %{"hash" => "0x" <> String.duplicate("c", 40)},
          "value" => "0",
          "fee" => %{"value" => "1000000000000000"}
        }
      ],
      "next_page_params" => %{
        "items_count" => 50,
        "block_number" => 10_217_967,
        "index" => 1
      }
    }

    @impl true
    def request_raw(url) when is_binary(url) do
      uri = URI.parse(url)
      path = uri.path || ""
      query = uri.query || ""
      query_map = URI.decode_query(query)

      body =
        case {path, query, query_map} do
          {"/api/v2/stats", _q, _qm} ->
            @stats

          {"/api/v2/transactions", _q, %{"items_count" => "50"} = qm} when map_size(qm) == 1 ->
            @txs_page_1

          {"/api/v2/transactions", _q,
           %{"items_count" => "50", "block_number" => "10217968", "index" => "82"}} ->
            @txs_page_2

          _ ->
            nil
        end

      if is_nil(body) do
        {:ok, %Req.Response{status: 404, headers: [], body: ""}}
      else
        {:ok,
         %Req.Response{
           status: 200,
           headers: [{"content-type", "application/json"}],
           body: Jason.encode!(body)
         }}
      end
    end
  end

  @frozen_now ~U[2026-02-09 12:00:00Z]

  test "/txs encodes next_page_params into a single cursor param" do
    restore =
      put_env(%{
        ff_skin: "classic",
        blockscout_url: "https://2d.example.com",
        blockscout_api_url: "http://127.0.0.1:4901",
        blockscout_ws_url: nil,
        clock_utc_now: @frozen_now,
        blockscout_request_adapter: Adapter
      })

    on_exit(restore)
    on_exit(fn -> _ = FrontendEx.Cache.clear(FrontendEx.ApiCache) end)

    # Avoid flakiness from cached responses in other tests. This test swaps the request adapter,
    # so we must ensure the client actually re-fetches.
    _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)

    body = html_response(get(build_conn(), "/txs"), 200)

    assert body =~
             "href=\"/txs?cursor=block_number%3D10217968%26index%3D82%26items_count%3D50&amp;ps=50\""
  end

  test "/txs paginates even if cursor params arrive split by a proxy" do
    restore =
      put_env(%{
        ff_skin: "classic",
        blockscout_url: "https://2d.example.com",
        blockscout_api_url: "http://127.0.0.1:4901",
        blockscout_ws_url: nil,
        clock_utc_now: @frozen_now,
        blockscout_request_adapter: Adapter
      })

    on_exit(restore)
    on_exit(fn -> _ = FrontendEx.Cache.clear(FrontendEx.ApiCache) end)

    _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)

    body =
      html_response(
        get(build_conn(), "/txs?cursor=block_number=10217968&index=82&items_count=50&ps=50"),
        200
      )

    assert body =~
             "href=\"/txs?cursor=block_number%3D10217967%26index%3D1%26items_count%3D50&amp;ps=50\""
  end

  test "/txs ignores items_count bypass via top-level param (server-controlled)" do
    # Adapter only matches `items_count=50` for the first page; an
    # un-stripped `items_count=10000` would propagate to upstream and
    # miss every clause → 404. Receiving 200 + the first-page hash
    # proves the controller normalized the value back to ps default 50.
    restore =
      put_env(%{
        ff_skin: "classic",
        blockscout_url: "https://2d.example.com",
        blockscout_api_url: "http://127.0.0.1:4901",
        blockscout_ws_url: nil,
        clock_utc_now: @frozen_now,
        blockscout_request_adapter: Adapter
      })

    on_exit(restore)
    on_exit(fn -> _ = FrontendEx.Cache.clear(FrontendEx.ApiCache) end)

    _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)

    body = html_response(get(build_conn(), "/txs?items_count=10000"), 200)

    # First-page tx hash from @txs_page_1
    assert body =~ String.duplicate("1", 64)
  end

  test "/txs strips items_count from cursor segment (cursor bypass blocked)" do
    # Same defense: a `?cursor=items_count=10000&...` injection would
    # let the cursor's items_count survive into the upstream URL pre-fix.
    # After the fix, items_count is server-controlled regardless of how
    # it's smuggled in. Other cursor fields (block_number, index) survive
    # untouched, so the second-page adapter clause still matches.
    restore =
      put_env(%{
        ff_skin: "classic",
        blockscout_url: "https://2d.example.com",
        blockscout_api_url: "http://127.0.0.1:4901",
        blockscout_ws_url: nil,
        clock_utc_now: @frozen_now,
        blockscout_request_adapter: Adapter
      })

    on_exit(restore)
    on_exit(fn -> _ = FrontendEx.Cache.clear(FrontendEx.ApiCache) end)

    _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)

    body =
      html_response(
        get(
          build_conn(),
          "/txs?cursor=items_count=10000&block_number=10217968&index=82"
        ),
        200
      )

    # Second-page tx hash from @txs_page_2 — proves the cursor's
    # block_number+index reached upstream while the malicious
    # items_count=10000 was stripped.
    assert body =~ String.duplicate("a", 64)
  end

  defp put_env(kvs) when is_map(kvs) do
    prev =
      for {k, _v} <- kvs, into: %{} do
        {k, Application.get_env(:frontend_ex, k)}
      end

    Enum.each(kvs, fn
      {k, nil} -> Application.delete_env(:frontend_ex, k)
      {k, v} -> Application.put_env(:frontend_ex, k, v)
    end)

    fn ->
      Enum.each(prev, fn
        {k, nil} -> Application.delete_env(:frontend_ex, k)
        {k, v} -> Application.put_env(:frontend_ex, k, v)
      end)
    end
  end
end
