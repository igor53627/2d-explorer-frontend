defmodule FrontendExWeb.TxBridgeCardTest do
  @moduledoc """
  Unit tests for the bridge-card builder's defensive decoding (TASK-49).
  The upstream endpoint shape (2d/TASK-69) is not pinned, so these lock in
  graceful degradation rather than crashes / misleading rows.
  """

  use ExUnit.Case, async: true

  alias FrontendExWeb.TxBridgeCard

  @native_coin %{symbol: "USDC", decimals: 6}
  @event_id "0x" <> String.duplicate("a", 64)

  test "returns nil for 404 / unrecognized payloads" do
    assert TxBridgeCard.build(nil, @native_coin) == nil
    assert TxBridgeCard.build(%{"kind" => "nope", "data" => %{}}, @native_coin) == nil
    assert TxBridgeCard.build(%{"kind" => "bridge_lock", "data" => []}, @native_coin) == nil
  end

  test "object-valued fields degrade to blank instead of crashing the page" do
    card =
      TxBridgeCard.build(
        %{
          "kind" => "bridge_lock",
          "data" => %{
            "amount" => "1000000",
            "eth_event_id" => @event_id,
            # Blockscout-style nested objects would crash bare to_string/1.
            "recipient" => %{"hash" => "0xfe00000000000000000000000000000000000000"},
            "source_tx_hash" => %{"hash" => "0xabcd"},
            "source_chain_id" => 1
          }
        },
        @native_coin
      )

    assert card.kind == "bridge_lock"
    assert card.recipient == ""
    assert card.recipient_href == nil
    assert card.source_tx_hash == ""
  end

  test "string source_chain_id still resolves the Etherscan link" do
    card =
      TxBridgeCard.build(
        %{
          "kind" => "bridge_refill_mint",
          "data" => %{
            "amount" => "1000000",
            "eth_event_id" => @event_id,
            "source_chain_id" => "1",
            "source_tx_hash" => "0x" <> String.duplicate("b", 64)
          }
        },
        @native_coin
      )

    assert card.source_chain_id == 1
    assert card.source_explorer_url =~ "etherscan.io/tx/0x"
  end

  test "string deadline_ms is formatted as a date; negative falls back to the raw number" do
    base = fn deadline ->
      TxBridgeCard.build(
        %{"kind" => "bridge_lock", "data" => %{"amount" => "1", "deadline_ms" => deadline}},
        @native_coin
      )
    end

    assert base.("1700000000000").deadline_readable == "2023-11-14 22:13:20 UTC"
    assert base.(-1).deadline_readable == "-1"
  end

  test "missing htlc_swap omits the amount and receiver rows (no misleading 0 USDC)" do
    card =
      TxBridgeCard.build(
        %{"kind" => "htlc_settle", "data" => %{"lock_id" => "0xee"}},
        @native_coin
      )

    assert card.amount_display == nil
    assert card.recipient_href == nil
  end

  test "htlc_settle reads receiver/status from the data level when htlc_swap omits them" do
    card =
      TxBridgeCard.build(
        %{
          "kind" => "htlc_settle",
          "data" => %{
            "lock_id" => "0xee",
            "amount" => "1000000",
            "recipient" => "0xfe00000000000000000000000000000000000000",
            "status" => "claimed"
          }
        },
        @native_coin
      )

    assert card.recipient_href == "/address/0xfe00000000000000000000000000000000000000"
    assert card.htlc_status == "claimed"
    assert card.amount_display == "1 USDC"
  end

  test "invalid eth_event_id produces no /bridges cross-link" do
    card =
      TxBridgeCard.build(
        %{
          "kind" => "bridge_refill_mint",
          "data" => %{"eth_event_id" => "0xabc", "amount" => "1"}
        },
        @native_coin
      )

    assert card.bridges_detail_href == nil
  end
end
