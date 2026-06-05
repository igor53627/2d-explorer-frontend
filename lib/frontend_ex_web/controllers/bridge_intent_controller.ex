defmodule FrontendExWeb.BridgeIntentController do
  use FrontendExWeb, :controller

  alias FrontendEx.Blockscout.Client
  alias FrontendExWeb.{BridgeIntentHTML, BridgeIntentStatus}

  def show(conn, %{"intent_id" => raw}) when is_binary(raw) do
    intent_id = String.trim(raw)

    if BridgeIntentStatus.valid_intent_id?(intent_id) do
      show_intent(conn, intent_id)
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Bridge intent not found")
    end
  end

  defp show_intent(conn, intent_id) do
    api_path = "/api/v2/bridge/intents/#{intent_id}"

    stats_task = Task.async(fn -> Client.get_json_cached("/api/v2/stats", :public) end)
    intent_task = Task.async(fn -> Client.get_json_cached(api_path, :public) end)

    [stats_json, intent_json] =
      await_many_ok([{"stats", stats_task}, {"intent", intent_task}], "bridge_intent")

    if is_nil(intent_json) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Bridge intent not found")
    else
      intent = BridgeIntentStatus.build(intent_json)

      if is_nil(intent) do
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "Bridge intent not found")
      else
        native_coin = derive_native_coin(stats_json)

        base_assigns =
          base_assigns(%{
            intent: intent,
            native_coin: native_coin
          })

        styles = BridgeIntentHTML.classic_styles(base_assigns)

        render(conn, :classic_show_content, %{
          base_assigns
          | page_title: "Bridge intent | 2D",
            nav_bridges: "active",
            styles: styles
        })
      end
    end
  end
end
