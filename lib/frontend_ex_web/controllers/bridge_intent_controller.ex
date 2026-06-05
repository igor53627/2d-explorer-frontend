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
    # The intent page renders no amount, so it needs no /api/v2/stats fetch —
    # use the default native coin and make the single intent request directly.
    intent =
      case Client.get_json_cached("/api/v2/bridge/intents/#{intent_id}", :public) do
        {:ok, json} -> BridgeIntentStatus.build(json)
        {:error, _} -> nil
      end

    if is_nil(intent) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Bridge intent not found")
    else
      base_assigns =
        base_assigns(%{
          intent: intent,
          native_coin: derive_native_coin(nil)
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
