defmodule FrontendExWeb.TxBridgeCard do
  @moduledoc """
  Builds display assigns for the SSR bridge card on `/tx/:hash` (TASK-49).

  Consumes `GET /api/v2/transactions/:hash/bridge` (`kind` + `data`).
  Returns `nil` when the endpoint 404s or the payload is unrecognized.
  """

  alias FrontendEx.{BridgeTx, Format}
  alias FrontendExWeb.BridgesController

  @doc "Parse bridge endpoint JSON into template assigns, or `nil`."
  @spec build(map() | nil, %{symbol: binary()}) :: map() | nil
  def build(nil, _native_coin), do: nil

  def build(%{"kind" => kind, "data" => data}, native_coin) when is_map(data) do
    kind = normalize_kind(kind)

    case kind do
      "bridge_lock" -> build_bridge_lock(data, native_coin)
      "htlc_settle" -> build_htlc_settle(data, native_coin)
      "htlc_refund" -> build_htlc_refund(data, native_coin)
      _ -> nil
    end
  end

  def build(_, _), do: nil

  defp normalize_kind("bridge_refill_mint"), do: "bridge_lock"
  defp normalize_kind(kind) when is_binary(kind), do: kind
  defp normalize_kind(_), do: nil

  defp build_bridge_lock(data, native_coin) do
    mint = Map.get(data, "bridge_mint") || %{}

    eth_event_id = to_string(data["eth_event_id"] || mint["eth_event_id"] || "")
    source_chain_id = data["source_chain_id"] || mint["source_chain_id"]
    source_tx_hash = to_string(data["source_tx_hash"] || mint["source_tx_hash"] || "")
    source_log_index = data["source_log_index"] || mint["source_log_index"]
    amount_raw = to_string(data["amount"] || mint["amount"] || "0")
    htlc_hash = to_string(data["htlc_hash"] || mint["htlc_hash"] || "")
    recipient = to_string(data["recipient"] || mint["recipient"] || "")
    deadline_ms = data["deadline_ms"]
    tx_hash_2d = to_string(mint["tx_hash_2d"] || "")

    swap = Map.get(data, "htlc_swap")
    swap_status = if is_map(swap), do: swap["status"], else: nil

    %{
      kind: "bridge_lock",
      title: "Bridge lock (refill mint)",
      eth_event_id: eth_event_id,
      eth_event_id_short: Format.truncate_hash(eth_event_id),
      bridges_list_href: "/bridges",
      source_chain_id: source_chain_id,
      source_tx_hash: source_tx_hash,
      source_tx_hash_short: Format.truncate_hash(source_tx_hash),
      source_log_index: source_log_index,
      source_explorer_url: BridgeTx.source_chain_tx_url(source_chain_id, source_tx_hash),
      amount_display: amount_display(amount_raw, native_coin),
      htlc_hash: htlc_hash,
      htlc_hash_short: Format.truncate_hash(htlc_hash),
      preimage_hash: to_string(data["preimage_hash"] || ""),
      preimage_hash_short: Format.truncate_hash(to_string(data["preimage_hash"] || "")),
      recipient: recipient,
      recipient_short: Format.truncate_hash(recipient),
      recipient_href: if(recipient != "", do: "/address/#{recipient}"),
      deadline_ms: deadline_ms,
      deadline_readable: format_deadline_ms(deadline_ms),
      htlc_status: swap_status,
      tx_hash_2d: tx_hash_2d,
      tx_hash_2d_short: if(tx_hash_2d != "", do: Format.truncate_hash(tx_hash_2d), else: nil),
      tx_hash_2d_href: if(tx_hash_2d != "", do: "/tx/#{tx_hash_2d}")
    }
  end

  defp build_htlc_settle(data, native_coin) do
    swap = Map.get(data, "htlc_swap") || %{}
    lock_id = to_string(data["lock_id"] || "")
    preimage = to_string(data["preimage"] || "")
    recipient = to_string(swap["receiver"] || "")

    %{
      kind: "htlc_settle",
      title: "HTLC settle (claim)",
      lock_id: lock_id,
      lock_id_short: Format.truncate_hash(lock_id),
      preimage: preimage,
      preimage_short: Format.truncate_hash(preimage),
      amount_display: amount_display(to_string(swap["amount"] || "0"), native_coin),
      htlc_status: swap["status"],
      recipient: recipient,
      recipient_short: Format.truncate_hash(recipient),
      recipient_href: if(recipient != "", do: "/address/#{recipient}")
    }
  end

  defp build_htlc_refund(data, native_coin) do
    swap = Map.get(data, "htlc_swap") || %{}
    lock_id = to_string(data["lock_id"] || "")
    recipient = to_string(swap["receiver"] || "")

    %{
      kind: "htlc_refund",
      title: "HTLC refund",
      lock_id: lock_id,
      lock_id_short: Format.truncate_hash(lock_id),
      amount_display: amount_display(to_string(swap["amount"] || "0"), native_coin),
      htlc_status: swap["status"],
      recipient: recipient,
      recipient_short: Format.truncate_hash(recipient),
      recipient_href: if(recipient != "", do: "/address/#{recipient}")
    }
  end

  defp amount_display(amount_raw, native_coin) do
    BridgesController.display_bridge(%{"amount" => amount_raw}, native_coin)
    |> Map.fetch!(:amount_formatted)
  end

  defp format_deadline_ms(ms) when is_integer(ms) do
    case DateTime.from_unix(ms, :millisecond) do
      {:ok, dt} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
      _ -> Integer.to_string(ms)
    end
  end

  defp format_deadline_ms(ms) when is_binary(ms), do: ms
  defp format_deadline_ms(_), do: nil
end
