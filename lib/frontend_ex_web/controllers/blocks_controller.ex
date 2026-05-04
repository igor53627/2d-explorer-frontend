defmodule FrontendExWeb.BlocksController do
  use FrontendExWeb, :controller

  require Logger

  alias FrontendEx.Blockscout.Client
  alias FrontendEx.Format
  alias FrontendExWeb.BlocksHTML

  @blocks_limit 50

  def index(conn, _params) do
    stats_path = "/api/v2/stats"
    blocks_path = "/api/v2/blocks?limit=#{@blocks_limit}"

    stats_task = Task.async(fn -> Client.get_json_cached(stats_path, :public) end)

    blocks_task =
      Task.async(fn ->
        Client.get_json_cached(blocks_path, :public)
      end)

    [stats_json, blocks_json] =
      await_many_ok([{stats_path, stats_task}, {blocks_path, blocks_task}], "blocks")

    {coin_price, gas_price} = derive_coin_gas(stats_json)
    native_coin = derive_native_coin(stats_json)
    blocks = parse_blocks(blocks_json)

    base_assigns =
      base_assigns(%{
        blocks: blocks,
        coin_price: coin_price,
        gas_price: gas_price,
        native_coin: native_coin
      })

    styles = BlocksHTML.classic_styles(base_assigns)

    render(conn, :classic_content, %{
      base_assigns
      | page_title: "Blocks | 2D",
        nav_blocks: "active",
        styles: styles
    })
  end

  defp parse_blocks(nil), do: []

  defp parse_blocks(%{} = json) do
    items =
      case json["items"] do
        list when is_list(list) -> list
        _ -> []
      end

    items
    |> Enum.take(@blocks_limit)
    |> Enum.map(&display_block/1)
  end

  defp parse_blocks(_), do: []

  defp display_block(%{} = b) do
    height =
      case b["height"] do
        v when is_integer(v) -> v
        v when is_binary(v) -> parse_int_or(v, nil)
        _ -> nil
      end

    ts_raw = to_string(b["timestamp"] || "")

    miner_hash =
      case get_in(b, ["miner", "hash"]) do
        v when is_binary(v) and v != "" -> v
        _ -> nil
      end

    # 2d returns "transaction_count" (singular); upstream Blockscout uses
    # "tx_count" / "transactions_count". Accept all three so each row shows
    # the real count instead of "0".
    tx_count =
      case b["tx_count"] || b["transaction_count"] || b["transactions_count"] do
        v when is_integer(v) -> v
        v when is_binary(v) -> parse_int_or(v, 0)
        _ -> 0
      end

    %{
      height: height,
      time_ago: Format.format_blocks_time_ago(ts_raw),
      tx_count: tx_count,
      miner_hash: miner_hash,
      gas_used: format_optional_number_string(b["gas_used"]),
      gas_limit: format_optional_number_string(b["gas_limit"])
    }
  end

  defp format_optional_number_string(nil), do: ""

  defp format_optional_number_string(v) when is_integer(v),
    do: v |> Integer.to_string() |> Format.format_number_with_commas()

  defp format_optional_number_string(v) when is_binary(v), do: Format.format_number_with_commas(v)
  defp format_optional_number_string(_), do: ""
end
