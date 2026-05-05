defmodule FrontendExWeb.AddressController do
  use FrontendExWeb, :controller

  alias FrontendEx.Blockscout.Client
  alias FrontendEx.Format
  alias FrontendExWeb.AddressHTML

  @txs_preview_limit 25
  @token_holdings_preview_limit 10

  def show(conn, %{"address" => address} = params) when is_binary(address) do
    address = String.trim(address)

    unless eth_address?(address) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Address not found")
    else
      show_valid(conn, address, params)
    end
  end

  defp show_valid(conn, address, params) do
    cursor_query =
      case Map.get(params, "cursor") do
        v when is_binary(v) -> String.trim(v)
        _ -> ""
      end

    stats_task = Task.async(fn -> Client.get_json_cached("/api/v2/stats", :public) end)

    addr_task =
      Task.async(fn -> Client.get_json_cached("/api/v2/addresses/#{address}", :public) end)

    txs_task =
      Task.async(fn ->
        Client.get_json_cached(address_txs_path(address, cursor_query), :public)
      end)

    tokens_task =
      Task.async(fn ->
        Client.get_json_cached("/api/v2/addresses/#{address}/tokens", :public)
      end)

    [stats_json, addr_json, txs_json, tokens_json] =
      await_many_ok(
        [
          {"stats", stats_task},
          {"address", addr_task},
          {"address_txs", txs_task},
          {"address_tokens", tokens_task}
        ],
        "address"
      )

    if is_nil(addr_json) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Address not found")
    else
      {coin_price, gas_price} = derive_coin_gas(stats_json)
      native_coin = derive_native_coin(stats_json)

      address_info = parse_address(addr_json)

      transactions =
        txs_json
        |> parse_transactions(address_info.hash, native_coin)
        |> Enum.take(@txs_preview_limit)

      {all_token_balances, token_holdings_count} = parse_token_balances(tokens_json)
      token_balances = Enum.take(all_token_balances, @token_holdings_preview_limit)

      balance_display = format_balance_display(address_info.coin_balance, native_coin)

      balance_usd_display =
        derive_balance_usd_display(address_info.coin_balance, coin_price, native_coin)

      {tx_first_seen, tx_latest_seen} =
        derive_tx_time_window(transactions, address_info.transactions_count)

      token_holdings_display =
        if token_holdings_count == 0 do
          "N/A"
        else
          ">$0.00 (#{token_holdings_count} Tokens)"
        end

      tx_count_display = format_tx_count_display(address_info.transactions_count)

      base_assigns =
        base_assigns(%{
          address: address_info,
          transactions: transactions,
          token_balances: token_balances,
          balance_display: balance_display,
          balance_usd_display: balance_usd_display,
          token_holdings_display: token_holdings_display,
          tx_count_display: tx_count_display,
          tx_first_seen: tx_first_seen,
          tx_latest_seen: tx_latest_seen,
          coin_price: coin_price,
          gas_price: gas_price,
          native_coin: native_coin
        })

      styles = AddressHTML.classic_styles(base_assigns)

      render(conn, :classic_content, %{
        base_assigns
        | page_title: "Address #{address_info.hash} | 2D",
          styles: styles
      })
    end
  end

  defp address_txs_path(address, ""), do: "/api/v2/addresses/#{address}/transactions"

  defp address_txs_path(address, cursor_query) when is_binary(cursor_query) do
    "/api/v2/addresses/#{address}/transactions?" <> cursor_query
  end

  defp parse_address(%{} = json) do
    hash = to_string(json["hash"] || "")

    %{
      hash: hash,
      # Same internal account, Tron-form display: derive deterministically
      # from the 0x form so the explorer can show both surfaces side-by-side
      # without waiting on the backend to advertise the tron variant.
      tron_hash: FrontendEx.Tron.Address.from_eth_hex(hash),
      is_contract: json["is_contract"],
      is_verified: json["is_verified"],
      coin_balance: normalize_opt_string(json["coin_balance"]),
      transactions_count: parse_u64(json["transactions_count"])
    }
  end

  defp parse_address(_),
    do: %{
      hash: "",
      tron_hash: nil,
      is_contract: nil,
      is_verified: nil,
      coin_balance: nil,
      transactions_count: nil
    }

  defp parse_transactions(nil, _addr_hash, _native_coin), do: []

  defp parse_transactions(%{} = txs_json, addr_hash, native_coin) when is_binary(addr_hash) do
    items =
      case txs_json["items"] do
        list when is_list(list) -> list
        _ -> []
      end

    items
    |> Enum.map(&display_tx(&1, addr_hash, native_coin))
  end

  defp display_tx(%{} = tx, addr_hash, native_coin) when is_binary(addr_hash) do
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

    value = to_string(tx["value"] || "0")
    has_value = String.match?(value, ~r/[1-9]/)

    fee =
      case get_in(tx, ["fee", "value"]) do
        v when is_binary(v) -> Format.format_native_amount(v)
        _ -> nil
      end

    method =
      case tx["method"] do
        v when is_binary(v) -> Format.format_method_name(v)
        _ -> nil
      end

    block_number = parse_u64(tx["block_number"])

    timestamp_raw =
      case tx["timestamp"] do
        v when is_binary(v) -> v
        _ -> nil
      end

    age =
      case timestamp_raw do
        v when is_binary(v) -> Format.format_relative_time(v)
        _ -> "-"
      end

    value_eth = Format.format_native_amount(value) <> " " <> native_coin.symbol

    # Per-address From/To form (TASK-13.13). Each side's display is keyed
    # off its own `primary_kind` (account's broadcast history) so a cross-
    # broadcast like Alice (eth) → Bob (tron) renders as `0xAlice → TBob`
    # instead of both sides matching this single tx's broadcast surface.
    # Falls back to tx.kind when an account has no broadcast history yet
    # (e.g. a fresh recipient).
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
      block_number: block_number,
      age: age,
      timestamp_raw: timestamp_raw,
      kind: kind,
      from_hash: from_hash,
      from_display: FrontendEx.Tron.Address.display_for_kind(from_hash, from_kind),
      to_hash: to_hash,
      to_display:
        if(to_hash, do: FrontendEx.Tron.Address.display_for_kind(to_hash, to_kind), else: nil),
      amount: value_eth,
      fee: fee,
      is_out: String.downcase(from_hash) == String.downcase(addr_hash),
      value_eth: value_eth,
      has_value: has_value
    }
  end

  defp display_tx(_, _addr_hash, _native_coin), do: nil

  defp parse_token_balances(nil), do: {[], 0}

  defp parse_token_balances(%{} = tokens_json) do
    items =
      case tokens_json["items"] do
        list when is_list(list) -> list
        _ -> []
      end

    balances =
      Enum.flat_map(items, fn
        %{"token" => %{} = token, "value" => value} ->
          [
            %{
              token: %{
                address: normalize_opt_string(token["address"]),
                name: normalize_opt_string(token["name"]),
                symbol: normalize_opt_string(token["symbol"])
              },
              value: to_string(value || "")
            }
          ]

        _ ->
          []
      end)

    {balances, length(balances)}
  end

  defp format_balance_display(nil, native_coin), do: "0 " <> native_coin.symbol

  defp format_balance_display(wei_balance, native_coin) when is_binary(wei_balance) do
    Format.format_native_amount_exact(wei_balance) <> " " <> native_coin.symbol
  end

  defp derive_balance_usd_display(nil, _coin_price, _native_coin), do: nil

  # USDC is dollar-pegged 1:1, so when /api/v2/stats doesn't advertise
  # `coin_price` (current 2d shape) we still show a meaningful USD value
  # by reading the balance directly. Falls through to the explicit
  # coin_price path for any non-stable native coin (forwards-compat).
  defp derive_balance_usd_display(wei_balance, _coin_price, %{symbol: "USDC"})
       when is_binary(wei_balance) do
    case Float.parse(Format.format_native_amount(wei_balance)) do
      {usdc, ""} -> "$" <> format_two_decimals_with_commas(usdc)
      _ -> nil
    end
  end

  defp derive_balance_usd_display(_wei_balance, nil, _native_coin), do: nil

  defp derive_balance_usd_display(wei_balance, coin_price, _native_coin)
       when is_binary(wei_balance) and is_binary(coin_price) do
    with {eth, ""} <- Float.parse(Format.format_native_amount(wei_balance)),
         {cp, ""} <- Float.parse(String.replace(coin_price, ",", "")) do
      "$" <> format_two_decimals_with_commas(eth * cp)
    else
      _ -> nil
    end
  end

  defp format_two_decimals_with_commas(n) when is_float(n) do
    s = :io_lib.format("~.2f", [n]) |> IO.iodata_to_binary()

    case String.split(s, ".", parts: 2) do
      [int_part, frac_part] -> Format.format_number_with_commas(int_part) <> "." <> frac_part
      [int_part] -> Format.format_number_with_commas(int_part)
    end
  end

  # Latest / First tx timestamps — derived from the already-fetched preview
  # list. The preview is freshness-DESC, so head = latest (always exact).
  # First is only exact when the preview holds the whole history (i.e.
  # length(preview) == transactions_count); otherwise we'd surface "first
  # within the last N" which is misleading, so we return nil there and the
  # template hides the row.
  defp derive_tx_time_window([], _count), do: {nil, nil}

  defp derive_tx_time_window(transactions, total_count) when is_list(transactions) do
    timestamps =
      transactions
      |> Enum.flat_map(fn
        %{timestamp_raw: ts} when is_binary(ts) and ts != "" -> [ts]
        _ -> []
      end)

    case timestamps do
      [] ->
        {nil, nil}

      [single] ->
        # Single tx in preview AND total_count is 1 → first == latest exact.
        if total_count in [nil, 1], do: {single, single}, else: {nil, single}

      list ->
        latest = List.first(list)
        first = if length(list) == total_count, do: List.last(list), else: nil
        {first, latest}
    end
  end

  defp format_tx_count_display(nil), do: ""

  defp format_tx_count_display(count) when is_integer(count) and count >= 0 do
    Format.format_number_with_commas(Integer.to_string(count))
  end
end
