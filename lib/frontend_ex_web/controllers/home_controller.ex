defmodule FrontendExWeb.HomeController do
  use FrontendExWeb, :controller

  alias FrontendEx.Blockscout.Client
  alias FrontendEx.Format
  alias FrontendExWeb.HomeHTML

  @blocks_limit 6
  @txs_limit 6

  def index(conn, _params) do
    explorer_url = explorer_url()
    api_url = Application.get_env(:frontend_ex, :blockscout_api_url, explorer_url)
    ws_url = ws_url(explorer_url)

    stats_task = Task.async(fn -> Client.get_json_cached("/api/v2/stats", :public) end)

    blocks_task =
      Task.async(fn ->
        Client.get_json_swr("/api/v2/blocks?limit=#{@blocks_limit}", :public)
      end)

    txs_task =
      Task.async(fn ->
        Client.get_json_swr("/api/v2/transactions?items_count=#{@txs_limit}", :public)
      end)

    # Await concurrently so a single slow upstream doesn't stack
    # 3 × timeout. Tasks run in parallel anyway; sequential await would
    # extend wall-clock latency on the slow-path.
    [stats_json, blocks_json, txs_json] =
      await_many_ok(
        [{"stats", stats_task}, {"blocks", blocks_task}, {"transactions", txs_task}],
        "home"
      )

    stats = parse_stats(stats_json)
    blocks = parse_blocks(blocks_json)
    transactions = parse_transactions(txs_json)

    {coin_price, coin_price_change, gas_slow, gas_avg, gas_fast, gas_price} =
      derive_stats_fields(stats)

    base_assigns =
      base_assigns(%{
        api_url: api_url,
        ws_url: ws_url,
        stats: stats,
        blocks: blocks,
        transactions: transactions,
        coin_price: coin_price,
        coin_price_change: coin_price_change,
        gas_price: gas_price,
        gas_slow: gas_slow,
        gas_avg: gas_avg,
        gas_fast: gas_fast
      })

    styles = HomeHTML.classic_styles(base_assigns)
    scripts = HomeHTML.classic_scripts(base_assigns)

    render(conn, :classic_content, %{
      base_assigns
      | page_title: "Sepolia Testnet Explorer",
        nav_home: "active",
        styles: styles,
        scripts: scripts
    })
  end

  defp parse_stats(nil), do: nil

  defp parse_stats(%{} = json) do
    avg_ms = json["average_block_time"]

    avg_s =
      if is_number(avg_ms) do
        avg_ms / 1000.0
      else
        nil
      end

    total_blocks =
      case json["total_blocks"] do
        v when is_binary(v) -> Format.format_number_with_commas(v)
        _ -> nil
      end

    total_transactions =
      case json["total_transactions"] do
        v when is_binary(v) -> Format.format_number_with_commas(v)
        _ -> nil
      end

    total_addresses =
      case json["total_addresses"] do
        v when is_binary(v) -> Format.format_number_with_commas(v)
        _ -> nil
      end

    coin_price =
      case json["coin_price"] do
        v when is_binary(v) -> Format.format_price_with_commas(v)
        _ -> nil
      end

    coin_price_change =
      case json["coin_price_change_percentage"] do
        v when is_number(v) -> v
        _ -> nil
      end

    network_util =
      case json["network_utilization_percentage"] do
        v when is_number(v) -> v
        _ -> nil
      end

    gas_prices = json["gas_prices"] || %{}

    %{
      average_block_time: avg_s,
      total_blocks: total_blocks,
      total_transactions: total_transactions,
      total_addresses: total_addresses,
      network_utilization_percentage: network_util,
      coin_price: coin_price,
      coin_price_change_percentage: coin_price_change,
      gas_prices: gas_prices
    }
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

  defp display_block(%{} = b) do
    height = b["height"]

    height_formatted =
      if is_integer(height), do: Integer.to_string(height), else: to_string(height)

    hash = to_string(b["hash"] || "")
    ts_raw = to_string(b["timestamp"] || "")

    miner_hash =
      case get_in(b, ["miner", "hash"]) do
        v when is_binary(v) -> v
        _ -> nil
      end

    miner =
      if miner_hash do
        %{hash: miner_hash, display: Format.truncate_addr(miner_hash)}
      else
        nil
      end

    tx_count =
      case b["tx_count"] do
        v when is_integer(v) -> v
        _ -> nil
      end

    %{
      height: height,
      height_formatted: height_formatted,
      hash: hash,
      timestamp: Format.format_relative_time(ts_raw),
      timestamp_raw: ts_raw,
      tx_count: tx_count,
      miner: miner
    }
  end

  defp parse_transactions(nil), do: []

  defp parse_transactions(%{} = json) do
    items =
      case json["items"] do
        list when is_list(list) -> list
        _ -> []
      end

    items
    |> Enum.take(@txs_limit)
    |> Enum.map(&display_tx/1)
  end

  defp display_tx(%{} = tx) do
    hash = to_string(tx["hash"] || "")

    from_hash =
      case get_in(tx, ["from", "hash"]) do
        v when is_binary(v) -> v
        _ -> ""
      end

    to_hash =
      case get_in(tx, ["to", "hash"]) do
        v when is_binary(v) -> v
        _ -> nil
      end

    value = Format.format_native_amount(to_string(tx["value"] || "0"))

    fee =
      case get_in(tx, ["fee", "value"]) do
        v when is_binary(v) -> Format.format_native_amount(v)
        _ -> "0"
      end

    status =
      case tx["status"] do
        v when is_binary(v) -> v
        _ -> nil
      end

    ts_raw =
      case tx["timestamp"] do
        v when is_binary(v) -> v
        _ -> nil
      end

    tx_types =
      case tx["transaction_types"] do
        list when is_list(list) -> list
        _ -> []
      end

    is_contract_call = Enum.any?(tx_types, &(&1 == "contract_call"))

    %{
      hash: hash,
      from: %{hash: from_hash, display: Format.truncate_addr(from_hash)},
      to: if(to_hash, do: %{hash: to_hash, display: Format.truncate_addr(to_hash)}, else: nil),
      value: value,
      fee: fee,
      status: status,
      timestamp: if(ts_raw, do: Format.format_relative_time(ts_raw), else: nil),
      timestamp_raw: ts_raw,
      tx_type_label: if(is_contract_call, do: "Contract call", else: "Coin transfer"),
      tx_type_class: if(is_contract_call, do: "badge-blue", else: "badge-orange")
    }
  end

  defp derive_stats_fields(nil), do: {nil, nil, nil, nil, nil, nil}

  defp derive_stats_fields(%{} = stats) do
    coin_price = stats.coin_price
    coin_price_change = stats.coin_price_change_percentage

    gas_prices = stats.gas_prices || %{}

    gas_slow = get_in(gas_prices, ["slow", "price"])
    gas_avg = get_in(gas_prices, ["average", "price"])
    gas_fast = get_in(gas_prices, ["fast", "price"])

    gas_price =
      cond do
        is_number(gas_avg) and gas_avg < 0.1 ->
          "< 0.1"

        is_number(gas_avg) ->
          Format.format_one_decimal(gas_avg)

        true ->
          nil
      end

    {coin_price, coin_price_change, gas_slow, gas_avg, gas_fast, gas_price}
  end

  defp ws_url(explorer_url) when is_binary(explorer_url) do
    case Application.get_env(:frontend_ex, :blockscout_ws_url) do
      v when is_binary(v) ->
        v = String.trim(v)

        if v != "" do
          v
        else
          derive_ws_url(explorer_url)
        end

      _ ->
        derive_ws_url(explorer_url)
    end
  end

  defp derive_ws_url(explorer_url) when is_binary(explorer_url) do
    host =
      explorer_url
      |> String.trim()
      |> String.trim_trailing("/")
      |> String.replace_prefix("https://", "")
      |> String.replace_prefix("http://", "")

    "wss://" <> host <> "/socket/v2/websocket?vsn=2.0.0"
  end
end
