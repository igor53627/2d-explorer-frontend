defmodule FrontendExWeb.TxBridgeCard do
  @moduledoc """
  Builds display assigns for the SSR bridge card on `/tx/:hash` (TASK-49).

  Consumes `GET /api/v2/transactions/:hash/bridge` (`kind` + `data`).
  Returns `nil` when the endpoint 404s or the payload is unrecognized.

  Field decoders coerce defensively (`as_string/1`, `normalize_chain_id/1`):
  the upstream endpoint (2d/TASK-69) is not pinned in this repo, so a field
  that arrives as an object/array degrades to a hidden row rather than
  crashing the whole `/tx` page.
  """

  alias FrontendEx.{BridgeTx, Format}

  @doc "Parse bridge endpoint JSON into template assigns, or `nil`."
  @spec build(map() | nil, %{symbol: binary()}) :: map() | nil
  def build(nil, _native_coin), do: nil

  def build(%{"kind" => kind, "data" => data}, native_coin) when is_map(data) do
    case kind do
      "bridge_refill_mint" -> build_bridge_refill_mint(data, native_coin)
      "bridge_lock" -> build_bridge_lock(data, native_coin)
      "htlc_settle" -> build_htlc_settle(data, native_coin)
      "htlc_refund" -> build_htlc_refund(data, native_coin)
      _ -> nil
    end
  end

  def build(_, _), do: nil

  @doc "Render the bridge card partial to HTML (used by golden snapshot tests)."
  @spec render_html(map()) :: binary()
  def render_html(%{} = card) do
    card
    |> then(&FrontendExWeb.TxHTML.bridge_card(%{card: &1}))
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp build_bridge_refill_mint(data, native_coin) do
    mint = Map.get(data, "bridge_mint") || %{}

    eth_event_id = as_string(data["eth_event_id"] || mint["eth_event_id"])
    source_chain_id = normalize_chain_id(data["source_chain_id"] || mint["source_chain_id"])
    source_tx_hash = as_string(data["source_tx_hash"] || mint["source_tx_hash"])
    source_log_index = data["source_log_index"] || mint["source_log_index"]
    amount_raw = as_string(data["amount"] || mint["amount"])
    tx_hash_2d = as_string(mint["tx_hash_2d"] || data["tx_hash_2d"])

    %{
      kind: "bridge_refill_mint",
      title: "Bridge refill mint",
      eth_event_id: eth_event_id,
      eth_event_id_short: Format.truncate_hash(eth_event_id),
      bridges_detail_href: bridges_detail_href(eth_event_id),
      source_chain_id: source_chain_id,
      source_tx_hash: source_tx_hash,
      source_tx_hash_short: Format.truncate_hash(source_tx_hash),
      source_log_index: source_log_index,
      source_explorer_url: BridgeTx.source_chain_tx_url(source_chain_id, source_tx_hash),
      amount_display: amount_display(amount_raw, native_coin),
      tx_hash_2d: tx_hash_2d,
      tx_hash_2d_short: short_or_nil(tx_hash_2d),
      tx_hash_2d_href: tx_href(tx_hash_2d)
    }
  end

  defp build_bridge_lock(data, native_coin) do
    mint = Map.get(data, "bridge_mint") || %{}

    eth_event_id = as_string(data["eth_event_id"] || mint["eth_event_id"])
    source_chain_id = normalize_chain_id(data["source_chain_id"] || mint["source_chain_id"])
    source_tx_hash = as_string(data["source_tx_hash"] || mint["source_tx_hash"])
    source_log_index = data["source_log_index"] || mint["source_log_index"]
    amount_raw = as_string(data["amount"] || mint["amount"])
    htlc_hash = as_string(data["htlc_hash"] || mint["htlc_hash"])
    preimage_hash = as_string(data["preimage_hash"])
    recipient = as_string(data["recipient"] || mint["recipient"])
    tx_hash_2d = as_string(mint["tx_hash_2d"] || data["tx_hash_2d"])

    %{
      kind: "bridge_lock",
      title: "Bridge lock",
      eth_event_id: eth_event_id,
      eth_event_id_short: Format.truncate_hash(eth_event_id),
      bridges_detail_href: bridges_detail_href(eth_event_id),
      source_chain_id: source_chain_id,
      source_tx_hash: source_tx_hash,
      source_tx_hash_short: Format.truncate_hash(source_tx_hash),
      source_log_index: source_log_index,
      source_explorer_url: BridgeTx.source_chain_tx_url(source_chain_id, source_tx_hash),
      amount_display: amount_display(amount_raw, native_coin),
      htlc_hash: htlc_hash,
      htlc_hash_short: short_or_nil(htlc_hash),
      preimage_hash: preimage_hash,
      preimage_hash_short: short_or_nil(preimage_hash),
      recipient: recipient,
      recipient_short: Format.truncate_hash(recipient),
      recipient_href: address_href(recipient),
      deadline_readable: format_deadline_ms(data["deadline_ms"]),
      htlc_status: htlc_status(Map.get(data, "htlc_swap"), data),
      tx_hash_2d: tx_hash_2d,
      tx_hash_2d_short: short_or_nil(tx_hash_2d),
      tx_hash_2d_href: tx_href(tx_hash_2d)
    }
  end

  defp build_htlc_settle(data, native_coin) do
    swap = Map.get(data, "htlc_swap") || %{}
    lock_id = as_string(data["lock_id"])
    preimage = as_string(data["preimage"])
    recipient = as_string(swap["receiver"] || data["receiver"] || data["recipient"])
    lock_tx_hash = as_string(data["lock_tx_hash"])

    %{
      kind: "htlc_settle",
      title: "HTLC settle (claim)",
      lock_id: lock_id,
      lock_id_short: Format.truncate_hash(lock_id),
      preimage: preimage,
      preimage_short: Format.truncate_hash(preimage),
      lock_tx_hash: lock_tx_hash,
      lock_tx_hash_short: short_or_nil(lock_tx_hash),
      lock_tx_href: tx_href(lock_tx_hash),
      amount_display: amount_display(as_string(swap["amount"] || data["amount"]), native_coin),
      htlc_status: htlc_status(swap, data),
      recipient: recipient,
      recipient_short: Format.truncate_hash(recipient),
      recipient_href: address_href(recipient)
    }
  end

  defp build_htlc_refund(data, native_coin) do
    swap = Map.get(data, "htlc_swap") || %{}
    lock_id = as_string(data["lock_id"])
    recipient = as_string(swap["receiver"] || data["receiver"] || data["recipient"])
    lock_tx_hash = as_string(data["lock_tx_hash"])

    %{
      kind: "htlc_refund",
      title: "HTLC refund",
      lock_id: lock_id,
      lock_id_short: Format.truncate_hash(lock_id),
      lock_tx_hash: lock_tx_hash,
      lock_tx_hash_short: short_or_nil(lock_tx_hash),
      lock_tx_href: tx_href(lock_tx_hash),
      amount_display: amount_display(as_string(swap["amount"] || data["amount"]), native_coin),
      htlc_status: htlc_status(swap, data),
      recipient: recipient,
      recipient_short: Format.truncate_hash(recipient),
      recipient_href: address_href(recipient)
    }
  end

  # `nil` when there is no amount to show, so the template can omit the row
  # instead of rendering a misleading "0 USDC".
  defp amount_display("", _native_coin), do: nil

  defp amount_display(amount_raw, native_coin) when is_binary(amount_raw) do
    Format.format_native_amount_trimmed(amount_raw) <> " " <> native_coin.symbol
  end

  # Only link out to `/bridges/:id` when the event id is a real 32-byte hash —
  # the route 404s otherwise, so an unvalidated link would be dead-on-arrival.
  defp bridges_detail_href(eth_event_id) do
    if BridgeTx.valid_eth_event_id?(eth_event_id),
      do: BridgeTx.bridge_detail_href(eth_event_id)
  end

  # HTLC swap status, read from the nested `htlc_swap` object but falling back
  # to a data-level `status` field, normalized to a non-empty binary or `nil`.
  defp htlc_status(swap, data) do
    raw = (is_map(swap) and swap["status"]) || data["status"]
    if is_binary(raw) and raw != "", do: raw
  end

  defp short_or_nil(""), do: nil
  defp short_or_nil(hash) when is_binary(hash), do: Format.truncate_hash(hash)

  defp tx_href(""), do: nil
  defp tx_href(hash) when is_binary(hash), do: "/tx/#{hash}"

  defp address_href(""), do: nil
  defp address_href(addr) when is_binary(addr), do: "/address/#{addr}"

  # Coerce an arbitrary JSON value to a string. Objects/arrays (which would
  # raise `Protocol.UndefinedError` under `to_string/1`) degrade to "".
  defp as_string(v) when is_binary(v), do: v
  defp as_string(v) when is_integer(v), do: Integer.to_string(v)
  defp as_string(_), do: ""

  defp normalize_chain_id(id) when is_integer(id) and id >= 0, do: id

  defp normalize_chain_id(id) when is_binary(id) do
    case Integer.parse(String.trim(id)) do
      {n, ""} when n >= 0 -> n
      _ -> nil
    end
  end

  defp normalize_chain_id(_), do: nil

  defp format_deadline_ms(ms) when is_integer(ms) and ms > 0 do
    case DateTime.from_unix(ms, :millisecond) do
      {:ok, dt} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
      _ -> Integer.to_string(ms)
    end
  end

  defp format_deadline_ms(ms) when is_integer(ms), do: Integer.to_string(ms)

  defp format_deadline_ms(ms) when is_binary(ms) do
    case Integer.parse(String.trim(ms)) do
      {n, ""} -> format_deadline_ms(n)
      _ -> ms
    end
  end

  defp format_deadline_ms(_), do: nil
end
