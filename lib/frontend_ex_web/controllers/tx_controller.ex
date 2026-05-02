defmodule FrontendExWeb.TxController do
  use FrontendExWeb, :controller

  alias FrontendEx.Blockscout.Client
  alias FrontendEx.Format
  alias FrontendExWeb.TxHTML

  @task_timeout_ms 10_000
  # Rust treats transaction-by-hash and related tx tabs data as immutable (300s cache).
  @immutable_ttl_ms 300_000

  def show(conn, %{"hash" => hash}) when is_binary(hash) do
    hash = String.trim(hash)

    if not valid_tx_hash?(hash) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Transaction not found")
    else
      base_url = Application.get_env(:frontend_ex, :base_url, "https://fast.53627.org")

      stats_task = Task.async(fn -> Client.get_json_cached("/api/v2/stats", :public) end)

      tx_task =
        Task.async(fn ->
          Client.get_json_cached("/api/v2/transactions/#{hash}", :public, @immutable_ttl_ms)
        end)

      logs_task =
        Task.async(fn ->
          Client.get_json_cached("/api/v2/transactions/#{hash}/logs", :public, @immutable_ttl_ms)
        end)

      blocks_task =
        Task.async(fn ->
          # Rust uses SWR for latest blocks; this is only used for confirmations.
          Client.get_json_swr("/api/v2/blocks?limit=1", :public)
        end)

      [stats_json, tx_json, logs_json, blocks_json] =
        await_ok_many([stats_task, tx_task, logs_task, blocks_task], @task_timeout_ms)

      if is_nil(tx_json) do
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "Transaction not found")
      else
        {coin_price, gas_price} = derive_coin_gas(stats_json)

        logs_count = parse_logs_count(logs_json)
        latest_block_height = parse_latest_block_height(blocks_json)

        display_tx =
          tx_json
          |> parse_tx()
          |> maybe_format_method()
          |> with_confirmations(latest_block_height)

        {from_is_contract_like, from_is_verified, to_is_contract_like, to_is_verified} =
          address_flags(display_tx)

        {fee_eth, timestamp_relative, timestamp_readable, method_id} =
          derive_tx_display_fields(display_tx)

        {gas_display, gas_percentage} = gas_fields(display_tx.gas_used, display_tx.gas_limit)

        gas_price_eth =
          if display_tx.gas_price,
            do: Format.format_wei_to_eth_exact(display_tx.gas_price),
            else: nil

        gas_price_gwei =
          if display_tx.gas_price, do: Format.format_wei_to_gwei(display_tx.gas_price), else: nil

        base_fee_gwei =
          if display_tx.base_fee_per_gas,
            do: Format.format_wei_to_gwei(display_tx.base_fee_per_gas),
            else: nil

        max_fee_gwei =
          if display_tx.max_fee_per_gas,
            do: Format.format_wei_to_gwei(display_tx.max_fee_per_gas),
            else: nil

        max_priority_fee_gwei =
          if display_tx.max_priority_fee_per_gas,
            do: Format.format_wei_to_gwei(display_tx.max_priority_fee_per_gas),
            else: nil

        base_assigns =
          base_assigns(%{
            base_url: base_url,
            tx: display_tx,
            from_is_contract_like: from_is_contract_like,
            from_is_verified: from_is_verified,
            to_is_contract_like: to_is_contract_like,
            to_is_verified: to_is_verified,
            fee_eth: fee_eth,
            timestamp_relative: timestamp_relative,
            timestamp_readable: timestamp_readable,
            method_id: method_id,
            gas_display: gas_display,
            gas_percentage: gas_percentage,
            gas_price_eth: gas_price_eth,
            gas_price_gwei: gas_price_gwei,
            base_fee_gwei: base_fee_gwei,
            max_fee_gwei: max_fee_gwei,
            max_priority_fee_gwei: max_priority_fee_gwei,
            logs_count: logs_count,
            coin_price: coin_price,
            gas_price: gas_price
          })

        head_meta = TxHTML.classic_head_meta(base_assigns)
        styles = TxHTML.classic_styles(base_assigns)

        render(conn, :classic_content, %{
          base_assigns
          | page_title: "Transaction #{display_tx.hash} | Sepolia",
            head_meta: head_meta,
            styles: styles
        })
      end
    end
  end

  def logs(conn, %{"hash" => hash}) when is_binary(hash) do
    hash = String.trim(hash)

    if valid_tx_hash?(hash) do
      render_logs_tab(conn, hash)
    else
      send_tx_not_found(conn)
    end
  end

  def state(conn, %{"hash" => hash}) when is_binary(hash) do
    hash = String.trim(hash)

    if valid_tx_hash?(hash) do
      render_state_tab(conn, hash)
    else
      send_tx_not_found(conn)
    end
  end

  def card(conn, %{"hash" => hash}) when is_binary(hash) do
    hash = String.trim(hash)

    if not valid_tx_hash?(hash) do
      send_tx_not_found(conn)
    else
      stats_task = Task.async(fn -> Client.get_json_cached("/api/v2/stats", :public) end)

      tx_task =
        Task.async(fn ->
          Client.get_json_cached("/api/v2/transactions/#{hash}", :public, @immutable_ttl_ms)
        end)

      [stats_json, tx_json] = await_ok_many([stats_task, tx_task], @task_timeout_ms)

      if is_nil(tx_json) do
        send_tx_not_found(conn)
      else
        coin_price_f = parse_coin_price_float(stats_json)

        tx = parse_tx(tx_json)
        from_name = get_in(tx_json, ["from", "name"])
        to_name = get_in(tx_json, ["to", "name"])

        tx =
          tx
          |> put_in([:from, :name], if(is_binary(from_name), do: from_name, else: nil))
          |> maybe_put_to_name(to_name)

        fee_eth =
          case tx.fee do
            %{value: v} when is_binary(v) -> Format.format_wei_to_eth(v)
            _ -> nil
          end

        timestamp_relative =
          if tx.timestamp, do: Format.format_relative_time(tx.timestamp), else: nil

        gas_display = if tx.gas_used, do: format_gas_compact(tx.gas_used), else: nil

        value_eth = Format.format_wei_to_eth(tx.value)
        value_usd = compute_value_usd(tx.value, coin_price_f)

        assigns =
          base_assigns(%{
            base_url: Application.get_env(:frontend_ex, :base_url, "https://fast.53627.org"),
            tx: tx,
            short_hash: tx_short_hash_card(hash),
            fee_eth: fee_eth,
            timestamp_relative: timestamp_relative,
            gas_display: gas_display,
            value_eth: value_eth,
            value_usd: value_usd
          })

        render(conn, :tx_card, assigns)
      end
    end
  end

  def og_image(conn, %{"hash" => hash}) when is_binary(hash) do
    hash = String.trim(hash)

    if not valid_tx_hash?(hash) do
      send_tx_not_found(conn)
    else
      case Client.get_json_cached("/api/v2/transactions/#{hash}", :public, @immutable_ttl_ms) do
        {:ok, tx_json} when is_map(tx_json) ->
          tx = parse_tx(tx_json)

          short_hash = tx_short_hash_svg(hash)

          {status_text, status_color, status_bg} =
            case tx.status do
              "ok" -> {"Success", "#22c55e", "rgba(34, 197, 94, 0.2)"}
              "error" -> {"Failed", "#ef4444", "rgba(239, 68, 68, 0.2)"}
              _ -> {"Pending", "#eab308", "rgba(234, 179, 8, 0.2)"}
            end

          from_short = Format.truncate_hash(get_in(tx, [:from, :hash]) || "")

          to_short =
            case tx.to do
              %{hash: to_hash} when is_binary(to_hash) and to_hash != "" ->
                Format.truncate_hash(to_hash)

              _ ->
                "Contract Creation"
            end

          fee =
            case tx.fee do
              %{value: v} when is_binary(v) -> Format.format_wei_to_eth(v)
              _ -> "0"
            end

          block =
            case tx.block_number do
              b when is_integer(b) -> "#" <> Integer.to_string(b)
              _ -> "Pending"
            end

          svg =
            """
            <svg width="1200" height="630" xmlns="http://www.w3.org/2000/svg">
              <defs>
                <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" style="stop-color:#1a1a2e"/>
                  <stop offset="50%" style="stop-color:#16213e"/>
                  <stop offset="100%" style="stop-color:#0f3460"/>
                </linearGradient>
                <linearGradient id="accent" x1="0%" y1="0%" x2="100%" y2="0%">
                  <stop offset="0%" style="stop-color:#00d4ff"/>
                  <stop offset="50%" style="stop-color:#7c3aed"/>
                  <stop offset="100%" style="stop-color:#f59e0b"/>
                </linearGradient>
                <linearGradient id="value-gradient" x1="0%" y1="0%" x2="100%" y2="0%">
                  <stop offset="0%" style="stop-color:#00d4ff"/>
                  <stop offset="100%" style="stop-color:#7c3aed"/>
                </linearGradient>
              </defs>
              
              <rect width="1200" height="630" fill="url(#bg)"/>
              <rect x="0" y="0" width="1200" height="6" fill="url(#accent)"/>
              
              <!-- Logo -->
              <g transform="translate(60, 50)">
                <path d="M24 2L4 14v24l20 12 20-12V14L24 2z" fill="#7c3aed"/>
                <path d="M24 8L10 16v16l14 8 14-8V16L24 8z" fill="white"/>
                <path d="M24 14L16 19v10l8 5 8-5V19l-8-5z" fill="#7c3aed"/>
              </g>
              <text x="120" y="85" font-family="Inter, system-ui, sans-serif" font-size="28" font-weight="700" fill="white">Blockscout</text>
              
              <!-- Status Badge -->
              <rect x="1000" y="50" width="140" height="40" rx="20" fill="#{status_bg}"/>
              <text x="1070" y="78" font-family="Inter, system-ui, sans-serif" font-size="18" font-weight="600" fill="#{status_color}" text-anchor="middle">#{status_text}</text>
              
              <!-- Transaction Label -->
              <text x="600" y="180" font-family="Inter, system-ui, sans-serif" font-size="16" fill="rgba(255,255,255,0.5)" text-anchor="middle" letter-spacing="3">TRANSACTION</text>
              
              <!-- Value -->
              <text x="600" y="260" font-family="Inter, system-ui, sans-serif" font-size="72" font-weight="700" fill="url(#value-gradient)" text-anchor="middle">#{Format.format_wei_to_eth(tx.value)} ETH</text>
              
              <!-- From/To Flow -->
              <rect x="80" y="320" width="440" height="120" rx="16" fill="rgba(255,255,255,0.05)"/>
              <text x="300" y="360" font-family="Inter, system-ui, sans-serif" font-size="14" fill="rgba(255,255,255,0.5)" text-anchor="middle" letter-spacing="1">FROM</text>
              <text x="300" y="400" font-family="monospace" font-size="20" fill="#00d4ff" text-anchor="middle">#{from_short}</text>
              
              <!-- Arrow -->
              <circle cx="600" cy="380" r="30" fill="url(#value-gradient)"/>
              <path d="M588 380 L612 380 M602 370 L612 380 L602 390" stroke="white" stroke-width="3" fill="none"/>
              
              <rect x="680" y="320" width="440" height="120" rx="16" fill="rgba(255,255,255,0.05)"/>
              <text x="900" y="360" font-family="Inter, system-ui, sans-serif" font-size="14" fill="rgba(255,255,255,0.5)" text-anchor="middle" letter-spacing="1">TO</text>
              <text x="900" y="400" font-family="monospace" font-size="20" fill="#00d4ff" text-anchor="middle">#{to_short}</text>
              
              <!-- Details -->
              <rect x="80" y="480" width="340" height="90" rx="12" fill="rgba(255,255,255,0.03)"/>
              <text x="250" y="515" font-family="Inter, system-ui, sans-serif" font-size="12" fill="rgba(255,255,255,0.5)" text-anchor="middle" letter-spacing="1">BLOCK</text>
              <text x="250" y="545" font-family="Inter, system-ui, sans-serif" font-size="22" font-weight="600" fill="white" text-anchor="middle">#{block}</text>
              
              <rect x="440" y="480" width="320" height="90" rx="12" fill="rgba(255,255,255,0.03)"/>
              <text x="600" y="515" font-family="Inter, system-ui, sans-serif" font-size="12" fill="rgba(255,255,255,0.5)" text-anchor="middle" letter-spacing="1">FEE</text>
              <text x="600" y="545" font-family="Inter, system-ui, sans-serif" font-size="22" font-weight="600" fill="white" text-anchor="middle">#{fee} ETH</text>
              
              <rect x="780" y="480" width="340" height="90" rx="12" fill="rgba(255,255,255,0.03)"/>
              <text x="950" y="515" font-family="Inter, system-ui, sans-serif" font-size="12" fill="rgba(255,255,255,0.5)" text-anchor="middle" letter-spacing="1">HASH</text>
              <text x="950" y="545" font-family="monospace" font-size="16" fill="rgba(255,255,255,0.6)" text-anchor="middle">#{short_hash}</text>
            </svg>
            """
            |> String.trim_trailing("\n")

          conn
          |> put_resp_content_type("image/svg+xml")
          |> put_resp_header("cache-control", "public, max-age=300")
          |> send_resp(200, svg)

        {:error, :not_found} ->
          send_tx_not_found(conn)

        {:error, _} ->
          send_tx_not_found(conn)
      end
    end
  end

  defp send_tx_not_found(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "Transaction not found")
  end

  defp valid_tx_hash?(hash) when is_binary(hash), do: tx_hash?(String.trim(hash))
  defp valid_eth_address?(address) when is_binary(address), do: eth_address?(String.trim(address))

  defp render_logs_tab(conn, hash) when is_binary(hash) do
    stats_task = Task.async(fn -> Client.get_json_cached("/api/v2/stats", :public) end)

    logs_task =
      Task.async(fn ->
        Client.get_json_cached("/api/v2/transactions/#{hash}/logs", :public, @immutable_ttl_ms)
      end)

    [stats_json, logs_json] = await_ok_many([stats_task, logs_task], @task_timeout_ms)

    {coin_price, gas_price} = derive_coin_gas(stats_json)
    logs = parse_tx_logs(logs_json)
    logs_count = length(logs)

    base_assigns =
      base_assigns(%{
        base_url: Application.get_env(:frontend_ex, :base_url, "https://fast.53627.org"),
        tx_hash: hash,
        logs: logs,
        logs_count: logs_count,
        coin_price: coin_price,
        gas_price: gas_price
      })

    styles = TxHTML.classic_logs_styles(base_assigns)

    render(conn, :classic_logs_content, %{
      base_assigns
      | page_title: "Transaction #{hash} Logs | Sepolia",
        styles: styles
    })
  end

  defp render_state_tab(conn, hash) when is_binary(hash) do
    stats_task = Task.async(fn -> Client.get_json_cached("/api/v2/stats", :public) end)

    state_task =
      Task.async(fn ->
        Client.get_json_cached(
          "/api/v2/transactions/#{hash}/state-changes",
          :public,
          @immutable_ttl_ms
        )
      end)

    logs_task =
      Task.async(fn ->
        Client.get_json_cached("/api/v2/transactions/#{hash}/logs", :public, @immutable_ttl_ms)
      end)

    [stats_json, state_json, logs_json] =
      await_ok_many([stats_task, state_task, logs_task], @task_timeout_ms)

    {coin_price, gas_price} = derive_coin_gas(stats_json)
    state_changes = parse_state_changes(state_json)
    logs_count = parse_logs_count(logs_json)

    base_assigns =
      base_assigns(%{
        base_url: Application.get_env(:frontend_ex, :base_url, "https://fast.53627.org"),
        tx_hash: hash,
        state_changes: state_changes,
        logs_count: logs_count,
        coin_price: coin_price,
        gas_price: gas_price
      })

    styles = TxHTML.classic_state_styles(base_assigns)

    render(conn, :classic_state_content, %{
      base_assigns
      | page_title: "Transaction #{hash} State | Sepolia",
        styles: styles
    })
  end

  defp parse_coin_price_float(%{"coin_price" => v}) when is_binary(v) do
    case Float.parse(String.trim(v)) do
      {f, ""} -> f
      _ -> nil
    end
  end

  defp parse_coin_price_float(_), do: nil

  defp compute_value_usd(wei_str, coin_price_f)
       when is_binary(wei_str) and is_float(coin_price_f) do
    wei_str = String.trim(wei_str)

    case Integer.parse(wei_str) do
      {wei, ""} when is_integer(wei) and wei >= 0 ->
        eth = wei / 1.0e18
        usd = eth * coin_price_f
        :io_lib.format("~.2f", [usd]) |> IO.iodata_to_binary()

      _ ->
        nil
    end
  end

  defp compute_value_usd(_wei_str, _coin_price_f), do: nil

  defp tx_short_hash_card(hash) when is_binary(hash) do
    if byte_size(hash) > 16 do
      prefix = binary_part(hash, 0, 10)
      suffix = binary_part(hash, byte_size(hash) - 6, 6)
      prefix <> "..." <> suffix
    else
      hash
    end
  end

  defp tx_short_hash_svg(hash) when is_binary(hash) do
    if byte_size(hash) > 20 do
      prefix = binary_part(hash, 0, 10)
      suffix = binary_part(hash, byte_size(hash) - 8, 8)
      prefix <> "..." <> suffix
    else
      hash
    end
  end

  defp format_gas_compact(gas) when is_binary(gas) do
    gas = String.trim(gas)

    case Integer.parse(gas) do
      {g, ""} when g >= 1_000_000 ->
        :io_lib.format("~.1fM", [g / 1_000_000]) |> IO.iodata_to_binary()

      {g, ""} when g >= 1_000 ->
        :io_lib.format("~.1fK", [g / 1_000]) |> IO.iodata_to_binary()

      {g, ""} ->
        Integer.to_string(g)

      _ ->
        gas
    end
  end

  defp format_gas_compact(_), do: nil

  defp maybe_put_to_name(%{to: %{hash: _} = to} = tx, to_name) when is_binary(to_name) do
    %{tx | to: Map.put(to, :name, to_name)}
  end

  defp maybe_put_to_name(%{to: %{hash: _} = to} = tx, _to_name) do
    %{tx | to: Map.put(to, :name, nil)}
  end

  defp maybe_put_to_name(tx, _to_name), do: tx

  defp parse_tx_logs(%{"items" => items}) when is_list(items) do
    Enum.map(items, &parse_tx_log/1)
  end

  defp parse_tx_logs(_), do: []

  defp parse_tx_log(%{} = log) do
    index = parse_u64(log["index"]) || 0
    address_hash = to_string(get_in(log, ["address", "hash"]) || "")

    topics =
      case log["topics"] do
        list when is_list(list) ->
          Enum.flat_map(list, fn
            v when is_binary(v) -> [v]
            _ -> []
          end)

        _ ->
          []
      end

    decoded = decode_tx_log(log["decoded"])
    data = if is_binary(log["data"]), do: log["data"], else: nil

    %{
      index: index,
      address_hash: address_hash,
      topics: topics,
      decoded: decoded,
      data: data
    }
  end

  defp parse_tx_log(_), do: %{index: 0, address_hash: "", topics: [], decoded: nil, data: nil}

  defp decode_tx_log(decoded) when is_map(decoded) do
    method_call =
      case decoded["method_call"] do
        v when is_binary(v) -> v
        _ -> ""
      end

    event_name =
      case String.split(method_call, "(", parts: 2) do
        [name, _rest] -> name
        [name] -> name
        _ -> method_call
      end

    params =
      case decoded["parameters"] do
        list when is_list(list) ->
          Enum.map(list, &decode_tx_log_param/1)

        _ ->
          []
      end

    %{event_name: event_name, params: params}
  end

  defp decode_tx_log(_), do: nil

  defp decode_tx_log_param(%{} = p) do
    indexed =
      case p["indexed"] do
        true -> true
        _ -> false
      end

    name =
      case p["name"] do
        v when is_binary(v) -> v
        _ -> "-"
      end

    param_type =
      case p["type"] do
        v when is_binary(v) -> v
        _ -> "-"
      end

    value =
      case Map.get(p, "value") do
        nil -> "-"
        v -> json_value_to_display(v)
      end

    %{indexed: indexed, name: name, param_type: param_type, value: value}
  end

  defp decode_tx_log_param(_), do: %{indexed: false, name: "-", param_type: "-", value: "-"}

  defp json_value_to_display(v) when is_binary(v), do: v
  defp json_value_to_display(v) when is_number(v), do: to_string(v)
  defp json_value_to_display(v) when is_boolean(v), do: to_string(v)

  defp json_value_to_display(v) when is_list(v) do
    "[" <> Enum.map_join(v, ", ", &json_value_to_display/1) <> "]"
  end

  defp json_value_to_display(v) when is_map(v), do: encode_json_sorted(v)
  defp json_value_to_display(nil), do: "-"
  defp json_value_to_display(other), do: to_string(other)

  # `serde_json::Value::to_string()` uses a stable key order by default; mimic
  # this for the rare cases where decoded log params contain objects.
  defp encode_json_sorted(map) when is_map(map) do
    "{" <>
      (map
       |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
       |> Enum.map_join(",", fn {k, v} ->
         encode_json_string(to_string(k)) <> ":" <> encode_json_value_sorted(v)
       end)) <> "}"
  end

  defp encode_json_value_sorted(v) when is_binary(v), do: encode_json_string(v)
  defp encode_json_value_sorted(v) when is_number(v), do: to_string(v)
  defp encode_json_value_sorted(v) when is_boolean(v), do: if(v, do: "true", else: "false")

  defp encode_json_value_sorted(v) when is_list(v) do
    "[" <> Enum.map_join(v, ",", &encode_json_value_sorted/1) <> "]"
  end

  defp encode_json_value_sorted(v) when is_map(v), do: encode_json_sorted(v)
  defp encode_json_value_sorted(nil), do: "null"
  defp encode_json_value_sorted(other), do: encode_json_string(to_string(other))

  defp encode_json_string(s) when is_binary(s) do
    escaped =
      s
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\r", "\\r")
      |> String.replace("\t", "\\t")

    "\"" <> escaped <> "\""
  end

  defp parse_state_changes(%{"items" => items}) when is_list(items), do: items
  defp parse_state_changes(_), do: []


  defp await_ok_many(tasks, timeout_ms)
       when is_list(tasks) and is_integer(timeout_ms) and timeout_ms >= 0 do
    tasks
    |> Task.yield_many(timeout_ms)
    |> Enum.map(fn {task, res} ->
      json =
        case res do
          {:ok, {:ok, v}} -> v
          {:ok, {:error, _}} -> nil
          {:exit, _} -> nil
          nil -> nil
        end

      if is_nil(res) do
        _ = Task.shutdown(task, :brutal_kill)
      end

      json
    end)
  end

  defp parse_logs_count(%{} = logs_json) do
    case logs_json["items"] do
      items when is_list(items) -> length(items)
      _ -> 0
    end
  end

  defp parse_logs_count(_), do: 0

  defp parse_latest_block_height(%{} = blocks_json) do
    items =
      case blocks_json["items"] do
        list when is_list(list) -> list
        _ -> []
      end

    case List.first(items) do
      %{"height" => h} when is_integer(h) -> h
      %{"height" => h} when is_binary(h) -> parse_u64(h)
      _ -> nil
    end
  end

  defp parse_latest_block_height(_), do: nil

  defp parse_tx(%{} = tx_json) do
    hash = to_string(tx_json["hash"] || "")

    from_hash =
      case get_in(tx_json, ["from", "hash"]) do
        v when is_binary(v) -> v
        _ -> ""
      end

    to_hash =
      case get_in(tx_json, ["to", "hash"]) do
        v when is_binary(v) -> v
        _ -> nil
      end

    %{
      hash: hash,
      block_number: parse_u64(tx_json["block_number"]),
      from: %{hash: from_hash},
      to: if(to_hash, do: %{hash: to_hash}, else: nil),
      value: to_string(tx_json["value"] || "0"),
      gas_used: normalize_opt_string(tx_json["gas_used"]),
      gas_price: normalize_opt_string(tx_json["gas_price"]),
      gas_limit: normalize_opt_string(tx_json["gas_limit"]),
      fee: parse_fee(tx_json["fee"]),
      status: normalize_opt_string(tx_json["status"]),
      timestamp: normalize_opt_string(tx_json["timestamp"]),
      confirmations: nil,
      method: normalize_opt_string(tx_json["method"]),
      tx_type: parse_u64(tx_json["type"]),
      base_fee_per_gas: normalize_opt_string(tx_json["base_fee_per_gas"]),
      max_fee_per_gas: normalize_opt_string(tx_json["max_fee_per_gas"]),
      max_priority_fee_per_gas: normalize_opt_string(tx_json["max_priority_fee_per_gas"]),
      raw_input: normalize_opt_string(tx_json["raw_input"])
    }
  end

  defp parse_tx(_), do: nil

  defp parse_fee(%{"value" => v}) when is_binary(v), do: %{value: v}
  defp parse_fee(_), do: nil

  defp maybe_format_method(nil), do: nil

  defp maybe_format_method(%{} = tx) do
    method =
      case tx.method do
        v when is_binary(v) -> Format.format_method_name(v)
        _ -> nil
      end

    %{tx | method: method}
  end

  defp with_confirmations(%{} = tx, latest_height) when is_integer(latest_height) do
    confirmations =
      case tx.block_number do
        b when is_integer(b) ->
          if latest_height >= b do
            latest_height - b + 1
          else
            0
          end

        _ ->
          nil
      end

    %{tx | confirmations: confirmations}
  end

  defp with_confirmations(%{} = tx, _latest_height), do: tx

  defp address_flags(%{} = tx) do
    from_hash = get_in(tx, [:from, :hash]) || ""

    from_info =
      if valid_eth_address?(from_hash) do
        case Client.get_json_cached("/api/v2/addresses/#{from_hash}", :public) do
          {:ok, json} when is_map(json) -> json
          _ -> nil
        end
      else
        nil
      end

    to_info =
      case tx.to do
        %{hash: to_hash} when is_binary(to_hash) and to_hash != "" ->
          if valid_eth_address?(to_hash) do
            case Client.get_json_cached("/api/v2/addresses/#{to_hash}", :public) do
              {:ok, json} when is_map(json) -> json
              _ -> nil
            end
          else
            nil
          end

        _ ->
          nil
      end

    from_is_verified = truthy?(from_info && from_info["is_verified"])

    from_is_contract_like =
      truthy?(from_info && from_info["is_contract"]) || from_is_verified ||
        is_binary(from_info && from_info["name"])

    to_is_verified = truthy?(to_info && to_info["is_verified"])

    to_is_contract_like =
      truthy?(to_info && to_info["is_contract"]) || to_is_verified ||
        is_binary(to_info && to_info["name"])

    {from_is_contract_like, from_is_verified, to_is_contract_like, to_is_verified}
  end

  defp truthy?(true), do: true
  defp truthy?(_), do: false

  defp derive_tx_display_fields(%{} = tx) do
    fee_eth =
      case tx.fee do
        %{value: v} when is_binary(v) -> Format.format_wei_to_eth_exact(v)
        _ -> nil
      end

    timestamp_relative = if tx.timestamp, do: Format.format_relative_time(tx.timestamp), else: nil

    timestamp_readable =
      case tx.timestamp do
        ts when is_binary(ts) -> Format.format_readable_date_classic(ts)
        _ -> nil
      end

    method_id =
      case tx.raw_input do
        input when is_binary(input) and byte_size(input) >= 10 -> binary_part(input, 0, 10)
        _ -> nil
      end

    {fee_eth, timestamp_relative, timestamp_readable, method_id}
  end

  defp gas_fields(nil, _limit), do: {nil, nil}
  defp gas_fields(used, nil) when is_binary(used), do: {used, nil}
  defp gas_fields(_used, nil), do: {nil, nil}

  defp gas_fields(used, limit) when is_binary(used) and is_binary(limit) do
    case {Integer.parse(used), Integer.parse(limit)} do
      {{u, ""}, {l, ""}} when l > 0 ->
        pct = u * 100.0 / l
        {used <> " / " <> limit, :io_lib.format("~.2f", [pct]) |> IO.iodata_to_binary()}

      {{_u, ""}, {0, ""}} ->
        {used, "0"}

      {{_u, ""}, {_l, ""}} ->
        {used, nil}

      _ ->
        {used, nil}
    end
  end

  defp gas_fields(_used, _limit), do: {nil, nil}
end
