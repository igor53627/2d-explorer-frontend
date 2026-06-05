defmodule FrontendExWeb.BridgeIntentRenderTest do
  @moduledoc """
  Render tests for `/bridge/intents/:intent_id` (TASK-50).
  """

  use FrontendExWeb.ConnCase, async: false

  @intent_id "550e8400-e29b-41d4-a716-446655440000"

  @stats %{
    "total_blocks" => 1,
    "total_transactions" => 1,
    "latest_block_number" => 0,
    "native_coin" => %{"symbol" => "USDC", "decimals" => 6}
  }

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
            Application.get_env(:frontend_ex, :bridge_intent_test_stats)

          "/api/v2/bridge/intents/" <> _ ->
            Application.get_env(:frontend_ex, :bridge_intent_test_payload)

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
    Application.put_env(:frontend_ex, :bridge_intent_test_stats, @stats)

    _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)
    _ = FrontendEx.Cache.clear(FrontendEx.ApiSWRCache)

    on_exit(fn ->
      Application.put_env(:frontend_ex, :blockscout_request_adapter, prev_adapter)
      Application.delete_env(:frontend_ex, :bridge_intent_test_stats)
      Application.delete_env(:frontend_ex, :bridge_intent_test_payload)
      _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)
      _ = FrontendEx.Cache.clear(FrontendEx.ApiSWRCache)
    end)

    :ok
  end

  defp put_intent_payload(payload) do
    Application.put_env(:frontend_ex, :bridge_intent_test_payload, payload)
    _ = FrontendEx.Cache.clear(FrontendEx.ApiCache)
    _ = FrontendEx.Cache.clear(FrontendEx.ApiSWRCache)
  end

  test "renders consumed intent with green badge", %{conn: conn} do
    put_intent_payload(%{
      "intent_id" => @intent_id,
      "state" => "consumed",
      "claim_status" => nil,
      "last_error" => nil,
      "bump_count" => 0,
      "state_updated_at" => "2026-02-09T10:00:00.000Z"
    })

    html = conn |> get("/bridge/intents/#{@intent_id}") |> html_response(200)

    assert html =~ "badge-success"
    assert html =~ "Consumed"
    assert html =~ "Gas bump attempts"
    assert html =~ ">0<"
    refute html =~ "Last error"
  end

  test "renders claim_failed with red badge and last_error", %{conn: conn} do
    put_intent_payload(%{
      "intent_id" => @intent_id,
      "state" => "claim_failed",
      "claim_status" => "claim_failed",
      "last_error" => "preflight",
      "bump_count" => 3,
      "state_updated_at" => "2026-02-09T11:00:00.000Z"
    })

    html = conn |> get("/bridge/intents/#{@intent_id}") |> html_response(200)

    assert html =~ "badge-danger"
    assert html =~ "Claim failed"
    assert html =~ "preflight"
    assert html =~ ">3<"
  end

  test "renders in_progress with yellow badge", %{conn: conn} do
    put_intent_payload(%{
      "intent_id" => @intent_id,
      "state" => "in_progress",
      "claim_status" => nil,
      "last_error" => nil,
      "bump_count" => 1,
      "state_updated_at" => "2026-02-09T09:00:00.000Z"
    })

    html = conn |> get("/bridge/intents/#{@intent_id}") |> html_response(200)

    assert html =~ "badge-warning"
    assert html =~ "In progress"
    assert html =~ ">1<"
  end

  test "404 for unknown intent", %{conn: conn} do
    put_intent_payload(nil)

    conn = get(conn, "/bridge/intents/#{@intent_id}")
    assert conn.status == 404
    assert conn.resp_body == "Bridge intent not found"
  end

  test "404 for malformed intent id", %{conn: conn} do
    conn = get(conn, "/bridge/intents/not-a-uuid")
    assert conn.status == 404
    assert conn.resp_body == "Bridge intent not found"
  end
end
