defmodule FrontendExWeb.BlockController do
  use FrontendExWeb, :controller

  alias FrontendEx.Blockscout.Client
  alias FrontendEx.Format
  alias FrontendExWeb.BlockHTML

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

      {block, txs_preview} =
        parse_block_and_preview_txs(block_json, txs_json, explorer_url)

      base_assigns =
        base_assigns(%{
          block: block,
          transactions: txs_preview,
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

    internal_transactions_count =
      case block_json["internal_transactions_count"] do
        v when is_integer(v) and v > 0 -> v
        _ -> nil
      end

    miner_hash =
      case get_in(block_json, ["miner", "hash"]) do
        v when is_binary(v) -> v
        _ -> nil
      end

    miner = if miner_hash, do: %{hash: miner_hash, truncated: miner_hash}, else: nil

    fee_recipient_in_secs = fee_recipient_in_secs(prev_block_json, ts_raw)

    proposed_on =
      case compute_sepolia_slot_epoch(ts_raw) do
        {slot, epoch} -> "Block proposed on slot #{slot}, epoch #{epoch}"
        nil -> nil
      end

    {gas_used_percent, gas_used_percent_gauge, gas_target_delta} =
      gas_percent_fields(block_json)

    display_block = %{
      height: height,
      timestamp_relative: Format.format_relative_time(ts_raw),
      timestamp_readable: Format.format_readable_date_classic_plus_utc(ts_raw),
      tx_count: parse_tx_count(block_json),
      internal_transactions_count: internal_transactions_count,
      miner: miner,
      fee_recipient_in_secs: fee_recipient_in_secs,
      proposed_on: proposed_on,
      block_reward_eth: nil,
      block_reward_breakdown: nil,
      withdrawals_count: nil,
      gas_used: format_optional_number_string(block_json["gas_used"]),
      gas_used_percent: gas_used_percent,
      gas_used_percent_gauge: gas_used_percent_gauge,
      gas_target_delta: gas_target_delta,
      gas_limit: format_optional_number_string(block_json["gas_limit"]),
      size: format_optional_size(block_json["size"]),
      # base_fee_per_gas arrives in native base units (USDC = 6 decimals on
      # 2d). Format here so the template can label it with @native_coin.symbol
      # without overstating by 10^6. Mirrors the tx-detail flow in
      # tx_controller.ex (see base_fee_native there).
      base_fee_per_gas: format_base_fee_native(block_json["base_fee_per_gas"]),
      base_fee_per_gas_gwei: nil,
      burnt_fees_eth: nil,
      hash: block_json["hash"],
      parent_hash: block_json["parent_hash"],
      state_root: block_json["state_root"],
      nonce: block_json["nonce"],
      extra_data: block_json["extra_data"],
      explorer_url: explorer_url
    }

    {display_block, txs_preview}
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

    # Per-address From/To form (TASK-13.13): prefer each side's
    # primary_kind, fall back to tx.kind for fresh recipients.
    kind =
      case tx["kind"] do
        v when is_binary(v) -> v
        _ -> nil
      end

    from_kind = get_in(tx, ["from", "primary_kind"]) || kind
    to_kind = get_in(tx, ["to", "primary_kind"]) || kind

    %{
      hash: hash,
      method: method,
      kind: kind,
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
      fee: if(fee_value, do: %{value: fee_value}, else: nil)
    }
  end

  defp display_tx(_),
    do: %{
      hash: "",
      method: nil,
      kind: nil,
      from: %{hash: "", display: ""},
      to: nil,
      value: "0",
      fee: nil
    }

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

  defp compute_sepolia_slot_epoch(timestamp) when is_binary(timestamp) do
    # 2022-06-20 14:00:00 UTC
    sepolia_genesis_time = 1_655_733_600
    slot_secs = 12
    slots_per_epoch = 32

    with {:ok, dt, _} <- DateTime.from_iso8601(String.trim(timestamp)) do
      ts = DateTime.to_unix(dt)

      if ts < sepolia_genesis_time do
        nil
      else
        since_genesis = ts - sepolia_genesis_time
        slot = div(since_genesis, slot_secs)
        epoch = div(slot, slots_per_epoch)
        {slot, epoch}
      end
    else
      _ -> nil
    end
  end

  defp gas_percent_fields(%{} = block_json) do
    gas_used_u64 = parse_u64(block_json["gas_used"])
    gas_limit_u64 = parse_u64(block_json["gas_limit"])

    percent_value =
      case {gas_used_u64, gas_limit_u64} do
        {used, limit} when is_integer(used) and is_integer(limit) and limit > 0 ->
          used * 100.0 / limit

        _ ->
          nil
      end

    gas_used_percent =
      if is_number(percent_value) do
        (:io_lib.format("~.2f", [percent_value]) |> IO.iodata_to_binary()) <> "%"
      else
        nil
      end

    gas_used_percent_gauge =
      if is_number(percent_value) do
        percent_value
        |> min(100.0)
        |> format_float_rust_display()
      else
        nil
      end

    gas_target_delta =
      case {gas_used_u64, gas_limit_u64} do
        {used, limit} when is_integer(used) and is_integer(limit) and limit > 0 ->
          target = max(div(limit, 2), 1)
          delta = round((used - target) * 100.0 / target)
          format_signed(delta) <> "% Gas Target"

        _ ->
          nil
      end

    {gas_used_percent, gas_used_percent_gauge, gas_target_delta}
  end

  # Rust templates render f64 gauge values using default Display, which prints
  # `0.0` as `0` and `50.0` as `50`.
  defp format_float_rust_display(v) when is_integer(v), do: Integer.to_string(v)

  defp format_float_rust_display(v) when is_float(v) do
    if v == trunc(v) do
      Integer.to_string(trunc(v))
    else
      Float.to_string(v)
    end
  end

  defp format_signed(n) when is_integer(n) and n >= 0, do: "+" <> Integer.to_string(n)
  defp format_signed(n) when is_integer(n), do: Integer.to_string(n)

  defp format_optional_number_string(v) when is_binary(v), do: Format.format_number_with_commas(v)

  defp format_optional_number_string(v) when is_integer(v),
    do: Format.format_number_with_commas(Integer.to_string(v))

  defp format_optional_number_string(_), do: nil

  defp format_optional_size(v) when is_integer(v) do
    Format.format_number_with_commas(Integer.to_string(v))
  end

  defp format_optional_size(v) when is_binary(v) do
    Format.format_number_with_commas(v)
  end

  defp format_optional_size(_), do: nil

  defp format_base_fee_native(v) when is_binary(v),
    do: Format.format_native_amount(String.trim(v))

  defp format_base_fee_native(v) when is_integer(v) and v >= 0,
    do: Format.format_native_amount(Integer.to_string(v))

  defp format_base_fee_native(_), do: nil
end
