defmodule FrontendExWeb.BlockController do
  use FrontendExWeb, :controller

  alias FrontendEx.Blockscout.Client
  alias FrontendEx.Format
  alias FrontendExWeb.{BlockHTML, BridgeDetect}

  @txs_preview_limit 20

  def show(conn, %{"id" => id}) when is_binary(id) do
    id = String.trim(id)

    if not block_id?(id) do
      conn |> put_resp_content_type("text/plain") |> send_resp(404, "Block not found")
    else
      show_block(conn, id)
    end
  end

  defp show_block(conn, id) do
    # parse_block_and_preview_txs/3 needs the explorer URL for its own
    # templating; binding it once here avoids a second helper call.
    explorer_url = explorer_url()

    stats_task = Task.async(fn -> Client.get_json_cached("/api/v2/stats", :public) end)
    block_task = Task.async(fn -> Client.get_json_cached("/api/v2/blocks/#{id}", :public) end)

    txs_task =
      Task.async(fn ->
        Client.get_json_cached("/api/v2/blocks/#{id}/transactions", :public)
      end)

    [stats_json, block_json, txs_json] =
      await_many_ok(
        [{"stats", stats_task}, {"block", block_task}, {"block_txs", txs_task}],
        "block"
      )

    if is_nil(block_json) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Block not found")
    else
      {coin_price, gas_price} = derive_coin_gas(stats_json)
      native_coin = derive_native_coin(stats_json)

      {block, txs_preview, bridge_ops} =
        parse_block_and_preview_txs(block_json, txs_json, explorer_url)

      base_assigns =
        base_assigns(%{
          block: block,
          transactions: txs_preview,
          bridge_ops: bridge_ops,
          coin_price: coin_price,
          gas_price: gas_price,
          native_coin: native_coin
        })

      styles = BlockHTML.classic_show_styles(base_assigns)

      render(conn, :classic_show_content, %{
        base_assigns
        | page_title: "Block ##{block.height} | 2D",
          nav_blocks: "active",
          styles: styles
      })
    end
  end

  def txs(conn, %{"id" => id}) when is_binary(id) do
    id = String.trim(id)

    if not block_id?(id) do
      conn |> put_resp_content_type("text/plain") |> send_resp(404, "Block not found")
    else
      txs_block(conn, id)
    end
  end

  defp txs_block(conn, id) do
    stats_task = Task.async(fn -> Client.get_json_cached("/api/v2/stats", :public) end)
    block_task = Task.async(fn -> Client.get_json_cached("/api/v2/blocks/#{id}", :public) end)

    txs_task =
      Task.async(fn ->
        Client.get_json_cached("/api/v2/blocks/#{id}/transactions", :public)
      end)

    [stats_json, block_json, txs_json] =
      await_many_ok(
        [{"stats", stats_task}, {"block", block_task}, {"block_txs", txs_task}],
        "block"
      )

    if is_nil(block_json) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Block not found")
    else
      {coin_price, gas_price} = derive_coin_gas(stats_json)
      native_coin = derive_native_coin(stats_json)

      block_height = parse_height(block_json)
      tx_count = parse_tx_count(block_json)
      transactions = parse_transactions(txs_json)

      base_assigns =
        base_assigns(%{
          block_height: block_height,
          tx_count: tx_count,
          transactions: transactions,
          coin_price: coin_price,
          gas_price: gas_price,
          native_coin: native_coin
        })

      styles = BlockHTML.classic_txs_styles(base_assigns)

      render(conn, :classic_txs_content, %{
        base_assigns
        | page_title: "Block ##{block_height} Transactions | 2D",
          nav_blocks: "active",
          styles: styles
      })
    end
  end

  defp parse_block_and_preview_txs(block_json, txs_json, explorer_url)
       when is_map(block_json) and (is_map(txs_json) or is_nil(txs_json)) do
    height = parse_height(block_json)
    ts_raw = to_string(block_json["timestamp"] || "")

    prev_block_json =
      if is_integer(height) and height > 0 do
        case Client.get_json_cached("/api/v2/blocks/#{height - 1}", :public) do
          {:ok, json} when is_map(json) -> json
          _ -> nil
        end
      else
        nil
      end

    all_txs = parse_transactions(txs_json)
    txs_preview = Enum.take(all_txs, @txs_preview_limit)
    bridge_ops = bridge_ops_summary(height, all_txs)

    miner_hash =
      case get_in(block_json, ["miner", "hash"]) do
        v when is_binary(v) -> v
        _ -> nil
      end

    miner = if miner_hash, do: %{hash: miner_hash, truncated: miner_hash}, else: nil

    fee_recipient_in_secs = fee_recipient_in_secs(prev_block_json, ts_raw)

    # Template renders only the rows actually meaningful on 2d (height,
    # status, timestamp, tx count, proposer, size, block / parent /
    # state root). Fields tied to upstream PoW/PoS / EIP-4844 / gas
    # economics (proposed_on, withdrawals, block_reward, total_difficulty,
    # gas_used, gas_limit, base_fee_per_gas, burnt_fees, extra_data,
    # internal_transactions_count) were removed from the view earlier;
    # the view-model below stops carrying them too.
    display_block = %{
      height: height,
      timestamp_relative: Format.format_relative_time(ts_raw),
      timestamp_readable: Format.format_readable_date_classic_plus_utc(ts_raw),
      tx_count: parse_tx_count(block_json),
      miner: miner,
      fee_recipient_in_secs: fee_recipient_in_secs,
      size: format_optional_size(block_json["size"]),
      hash: block_json["hash"],
      parent_hash: block_json["parent_hash"],
      state_root: block_json["state_root"],
      explorer_url: explorer_url
    }

    {display_block, txs_preview, bridge_ops}
  end

  defp bridge_ops_summary(height, all_txs) do
    case BridgeDetect.count_bridge_ops(all_txs) do
      0 ->
        nil

      count ->
        %{
          count: count,
          block_height: height,
          bridges_href: "/bridges"
        }
    end
  end

  defp parse_height(%{} = block_json) do
    case block_json["height"] do
      v when is_integer(v) -> v
      v when is_binary(v) -> v |> String.trim() |> String.to_integer()
      _ -> 0
    end
  rescue
    _ -> 0
  end

  # 2d returns "transaction_count" (singular); upstream Blockscout uses
  # "tx_count" / "transactions_count". Accept all three so the detail page
  # shows the real count instead of "0 transactions".
  defp parse_tx_count(%{} = block_json) do
    case block_json["tx_count"] || block_json["transaction_count"] ||
           block_json["transactions_count"] do
      v when is_integer(v) -> v
      v when is_binary(v) -> v |> String.trim() |> String.to_integer()
      _ -> 0
    end
  rescue
    _ -> 0
  end

  defp parse_transactions(nil), do: []

  defp parse_transactions(%{} = json) do
    items =
      case json["items"] do
        list when is_list(list) -> list
        _ -> []
      end

    Enum.map(items, &display_tx/1)
  end

  defp display_tx(%{} = tx) do
    hash = to_string(tx["hash"] || "")

    method =
      case tx["method"] do
        v when is_binary(v) -> v
        _ -> nil
      end

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

    fee_value =
      case get_in(tx, ["fee", "value"]) do
        v when is_binary(v) -> v
        _ -> nil
      end

    # 2d's API doesn't ship a `fee` object (gasless chain). Same
    # fallback as txs_controller / address_controller: compute
    # gas_price * gas_used → "0" on 2d, real value upstream.
    fee_raw = fee_value || compute_fee_raw(tx)

    # Per-address From/To form (TASK-13.13): prefer each side's
    # primary_kind, fall back to tx.kind for fresh recipients.
    kind =
      case tx["kind"] do
        v when is_binary(v) -> v
        _ -> nil
      end

    from_kind = get_in(tx, ["from", "primary_kind"]) || kind
    to_kind = get_in(tx, ["to", "primary_kind"]) || kind

    status =
      case tx["status"] do
        v when is_binary(v) -> v
        _ -> nil
      end

    %{
      hash: hash,
      method: method,
      kind: kind,
      status: status,
      from: %{
        hash: from_hash,
        display: FrontendEx.Tron.Address.display_for_kind(from_hash, from_kind)
      },
      to:
        if(to_hash,
          do: %{
            hash: to_hash,
            display: FrontendEx.Tron.Address.display_for_kind(to_hash, to_kind)
          },
          else: nil
        ),
      value: to_string(tx["value"] || "0"),
      fee: if(fee_value, do: %{value: fee_value}, else: nil),
      fee_raw: fee_raw
    }
  end

  defp display_tx(_),
    do: %{
      hash: "",
      method: nil,
      kind: nil,
      status: nil,
      from: %{hash: "", display: ""},
      to: nil,
      value: "0",
      fee: nil,
      fee_raw: nil
    }

  defp compute_fee_raw(%{} = tx) do
    with gp when is_integer(gp) and gp >= 0 <- normalize_int(tx["gas_price"]),
         gu when is_integer(gu) and gu >= 0 <- normalize_int(tx["gas_used"]) do
      Integer.to_string(gp * gu)
    else
      _ -> nil
    end
  end

  defp normalize_int(v) when is_integer(v), do: v

  defp normalize_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp normalize_int(_), do: nil

  defp fee_recipient_in_secs(nil, _cur_ts), do: nil

  defp fee_recipient_in_secs(%{} = prev_block_json, cur_ts_raw) when is_binary(cur_ts_raw) do
    prev_ts =
      case prev_block_json["timestamp"] do
        v when is_binary(v) -> v
        _ -> nil
      end

    with prev when is_binary(prev) <- prev_ts,
         {:ok, prev_dt, _} <- DateTime.from_iso8601(String.trim(prev)),
         {:ok, cur_dt, _} <- DateTime.from_iso8601(String.trim(cur_ts_raw)) do
      prev_unix = DateTime.to_unix(prev_dt)
      cur_unix = DateTime.to_unix(cur_dt)

      if cur_unix >= prev_unix do
        cur_unix - prev_unix
      else
        nil
      end
    else
      _ -> nil
    end
  end

  defp format_optional_size(v) when is_integer(v) do
    Format.format_number_with_commas(Integer.to_string(v))
  end

  defp format_optional_size(v) when is_binary(v) do
    Format.format_number_with_commas(v)
  end

  defp format_optional_size(_), do: nil
end
