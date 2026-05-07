defmodule FrontendExWeb.BridgesController do
  use FrontendExWeb, :controller

  alias FrontendEx.Blockscout.Client
  alias FrontendEx.Blockscout.Cursor
  alias FrontendEx.Format
  alias FrontendExWeb.BridgesHTML

  @page_size_options [10, 25, 50, 100]
  @default_page_size 50

  def index(conn, params) when is_map(params) do
    page_size = normalize_page_size(params)
    cursor_query = cursor_query_from_params(params)
    is_first_page = is_nil(cursor_query)

    stats_path = "/api/v2/stats"
    bridges_path = bridges_path(page_size, cursor_query)

    stats_task = Task.async(fn -> Client.get_json_cached(stats_path, :public) end)
    bridges_task = Task.async(fn -> Client.get_json_cached(bridges_path, :public) end)

    [stats_json, bridges_json] =
      await_many_ok([{stats_path, stats_task}, {bridges_path, bridges_task}], "bridges")

    native_coin = derive_native_coin(stats_json)
    {bridges, next_cursor} = parse_bridges_response(bridges_json, native_coin)

    page_label = if is_first_page, do: "Latest", else: "Older"

    page_size_options =
      Enum.map(@page_size_options, fn value ->
        %{value: value, selected: value == page_size}
      end)

    base_assigns =
      base_assigns(%{
        bridges: bridges,
        page_size: page_size,
        page_size_options: page_size_options,
        page_label: page_label,
        is_first_page: is_first_page,
        next_cursor: next_cursor,
        native_coin: native_coin
      })

    styles = BridgesHTML.classic_styles(base_assigns)

    render(conn, :classic_content, %{
      base_assigns
      | page_title: "Bridges | 2D",
        nav_bridges: "active",
        styles: styles
    })
  end

  defp normalize_page_size(params),
    do:
      FrontendExWeb.Pagination.normalize_page_size(params, @page_size_options, @default_page_size)

  @doc """
  Public so `AddressController.bridges/2` (TASK-46) can reuse the same
  cursor decoding/merging pipeline (`block_number` + `event_id` keys
  per `2d` TASK-13.17 decision (b)).
  """
  def cursor_query_from_params(params) when is_map(params) do
    cursor_raw =
      case Map.get(params, "cursor") do
        v when is_binary(v) -> String.trim(v)
        _ -> ""
      end

    cursor_raw = if cursor_raw == "", do: nil, else: cursor_raw

    cursor_query =
      case cursor_raw do
        v when is_binary(v) and v != "" ->
          v =
            if String.contains?(v, "%") do
              case Cursor.decode_cursor_value(v) do
                {:ok, decoded} -> decoded
                :error -> v
              end
            else
              v
            end

          merge_cursor_params(v, params)

        _ ->
          merge_cursor_params(nil, params)
      end

    case cursor_query do
      v when is_binary(v) ->
        v = String.trim(v)
        if v == "", do: nil, else: v

      _ ->
        nil
    end
  end

  defp merge_cursor_params(cursor_query, params) when is_map(params) do
    cursor_query =
      case cursor_query do
        v when is_binary(v) -> v
        _ -> ""
      end

    fragments = if cursor_query == "", do: [], else: [cursor_query]

    fragments =
      fragments
      |> maybe_append_numeric_param(cursor_query, "block_number", params)
      |> maybe_append_hex32_param(cursor_query, "event_id", params)

    fragments =
      fragments
      |> Enum.flat_map(fn
        v when is_binary(v) -> String.split(v, "&", trim: true)
        _ -> []
      end)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      # `items_count` is server-controlled (normalized via @page_size_options
      # clamp). Strip any user-supplied value here — whether it arrived as a
      # top-level `?items_count=10000` param (now ignored above) or sneaked
      # in via `?cursor=items_count=10000&block_number=42`. Without this,
      # the page_size clamp can be bypassed → unbounded upstream payload.
      # See `bridges_path/2` for where the normalized value gets stitched
      # back into the URL.
      |> Enum.reject(&String.starts_with?(&1, "items_count="))

    case fragments do
      [] -> nil
      _ -> Enum.join(fragments, "&")
    end
  end

  defp maybe_append_numeric_param(fragments, cursor_query, key, params)
       when is_list(fragments) and is_binary(cursor_query) and is_binary(key) and is_map(params) do
    if cursor_query != "" and String.contains?(cursor_query, key <> "=") do
      fragments
    else
      case normalize_numeric_param(params, key) do
        nil -> fragments
        v -> fragments ++ [key <> "=" <> v]
      end
    end
  end

  defp maybe_append_hex32_param(fragments, cursor_query, key, params)
       when is_list(fragments) and is_binary(cursor_query) and is_binary(key) and is_map(params) do
    if cursor_query != "" and String.contains?(cursor_query, key <> "=") do
      fragments
    else
      case normalize_hex32_param(params, key) do
        nil -> fragments
        v -> fragments ++ [key <> "=" <> v]
      end
    end
  end

  defp normalize_numeric_param(params, key) when is_map(params) and is_binary(key) do
    raw =
      case Map.get(params, key) do
        v when is_binary(v) -> String.trim(v)
        v when is_integer(v) and v >= 0 -> Integer.to_string(v)
        _ -> ""
      end

    cond do
      raw == "" -> nil
      String.match?(raw, ~r/^\d+$/) -> raw
      true -> nil
    end
  end

  defp normalize_hex32_param(params, key) when is_map(params) and is_binary(key) do
    raw =
      case Map.get(params, key) do
        v when is_binary(v) -> String.trim(v)
        _ -> ""
      end

    cond do
      raw == "" -> nil
      String.match?(raw, ~r/^0x[0-9a-fA-F]{64}$/) -> raw
      true -> nil
    end
  end

  defp bridges_path(page_size, nil) when is_integer(page_size) do
    "/api/v2/bridges?items_count=#{page_size}"
  end

  defp bridges_path(page_size, cursor_query)
       when is_integer(page_size) and is_binary(cursor_query) do
    # `cursor_query` is already stripped of any `items_count=` segment by
    # `merge_cursor_params/2`. Always set `items_count` from the normalized
    # `page_size` so the @page_size_options clamp can't be bypassed.
    "/api/v2/bridges?items_count=#{page_size}&" <> cursor_query
  end

  @doc """
  Public so `AddressController.bridges/2` (TASK-46) can reuse the same
  decode + decoration pipeline. Returns `{bridges, next_cursor}`.
  """
  def parse_bridges_response(nil, _native_coin), do: {[], nil}

  def parse_bridges_response(%{} = json, native_coin) do
    items =
      case json["items"] do
        list when is_list(list) -> list
        _ -> []
      end

    next_cursor =
      case Map.get(json, "next_page_params") do
        nil -> nil
        other -> Cursor.encode_next_page_params(other)
      end

    bridges =
      items
      |> Enum.flat_map(fn
        %{} = item -> [display_bridge(item, native_coin)]
        _ -> []
      end)

    {bridges, next_cursor}
  end

  def parse_bridges_response(_, _native_coin), do: {[], nil}

  @doc """
  Public so `AddressController.bridges/2` (TASK-46) can reuse the same
  per-row view-model decoration. Mirror the column expectations from
  `bridges_html/classic_content.html.eex`.
  """
  def display_bridge(%{} = item, native_coin) do
    eth_event_id = to_string(item["eth_event_id"] || "")

    htlc_hash =
      case item["htlc_hash"] do
        v when is_binary(v) -> v
        _ -> nil
      end

    amount_raw = to_string(item["amount"] || "0")

    recipient_hash =
      case item["recipient"] do
        v when is_binary(v) -> v
        _ -> nil
      end

    source_chain_id =
      case item["source_chain_id"] do
        v when is_integer(v) and v >= 0 -> v
        _ -> nil
      end

    source_tx_hash =
      case item["source_tx_hash"] do
        v when is_binary(v) -> v
        _ -> ""
      end

    source_log_index =
      case item["source_log_index"] do
        v when is_integer(v) and v >= 0 -> v
        _ -> nil
      end

    tx_hash_2d =
      case item["tx_hash_2d"] do
        v when is_binary(v) -> v
        _ -> nil
      end

    inserted_at =
      case item["inserted_at"] do
        v when is_binary(v) -> v
        _ -> nil
      end

    time_ago =
      case inserted_at do
        v when is_binary(v) -> Format.format_blocks_time_ago(v)
        _ -> "-"
      end

    timestamp_readable =
      case inserted_at do
        v when is_binary(v) -> Format.format_readable_date_classic(v)
        _ -> ""
      end

    %{
      eth_event_id: eth_event_id,
      eth_event_id_short: Format.truncate_hash(eth_event_id),
      htlc_hash: htlc_hash,
      htlc_hash_short: if(htlc_hash, do: Format.truncate_hash(htlc_hash), else: nil),
      # `Format.format_native_amount/1` always emits 4 decimal places
      # (e.g. "1.0000"). On a /bridges row that's most of the visual
      # weight; trim trailing zeros so round amounts read as `1 USDC`
      # and `0.5 USDC` instead of `1.0000 USDC` / `0.5000 USDC`. Local
      # post-process here so the global formatter's golden-byte parity
      # on /tx, /address etc. is unaffected.
      amount_formatted:
        trim_trailing_decimal_zeros(Format.format_native_amount(amount_raw)) <>
          " " <> native_coin.symbol,
      recipient_hash: recipient_hash,
      recipient_short: if(recipient_hash, do: Format.truncate_hash(recipient_hash), else: nil),
      source_tx_hash: source_tx_hash,
      source_tx_hash_short: Format.truncate_hash(source_tx_hash),
      source_log_index: source_log_index,
      source_chain_explorer_url: source_chain_explorer_url(source_chain_id, source_tx_hash),
      tx_hash_2d: tx_hash_2d,
      tx_hash_2d_short: if(tx_hash_2d, do: Format.truncate_hash(tx_hash_2d), else: nil),
      time_ago: time_ago,
      timestamp_readable: timestamp_readable,
      inserted_at_raw: inserted_at
    }
  end

  defp source_chain_explorer_url(1, hash) when is_binary(hash) and hash != "" do
    # Defense in depth: only return a URL if `hash` is a clean 32-byte hex
    # (with optional 0x prefix). The href= surface in the template
    # interpolates whatever this returns; a malformed hash that injected
    # a `javascript:` URI fragment would survive Phoenix.HTML escaping
    # (which guards against angle-brackets/quotes, not URI schemes).
    # The strict regex makes this path safe even if a future code change
    # widens what gets passed in.
    if Regex.match?(~r/^(0x)?[0-9a-fA-F]{64}$/, hash) do
      "https://etherscan.io/tx/" <> ensure_hex_prefix(hash)
    else
      nil
    end
  end

  defp source_chain_explorer_url(_, _), do: nil

  # Drop trailing zeros from the decimal part of a `Format.format_native_amount`
  # result, then drop the dot if nothing remains. Used to render bridge-mint
  # amounts compactly (`1 USDC` instead of `1.0000 USDC`). Pure string-level
  # post-process — keeps the global formatter unchanged so /tx and /address
  # goldens stay byte-identical.
  defp trim_trailing_decimal_zeros(s) when is_binary(s) do
    case String.split(s, ".", parts: 2) do
      [int_part, frac_part] ->
        case String.trim_trailing(frac_part, "0") do
          "" -> int_part
          trimmed -> int_part <> "." <> trimmed
        end

      _ ->
        s
    end
  end

  defp ensure_hex_prefix("0x" <> _ = v), do: v
  defp ensure_hex_prefix(v) when is_binary(v), do: "0x" <> v
end
