defmodule FrontendExWeb.TxBridgeGoldenTest do
  @moduledoc """
  Golden HTML snapshots for bridge-tx card partials (TASK-49 AC#10).
  """

  use ExUnit.Case, async: true

  alias FrontendEx.TestSupport.Golden
  alias FrontendExWeb.TxBridgeCard

  @native_coin %{symbol: "USDC", decimals: 6}
  @golden_dir Path.expand("../golden/tx_bridge", __DIR__)

  @bridge_refill_payload %{
    "kind" => "bridge_refill_mint",
    "data" => %{
      "amount" => "1000000",
      "eth_event_id" => "0x8a26217d2693abf40185791db4ca9889b322f73e5645ab1c2842139185c1b66c",
      "source_chain_id" => 1,
      "source_log_index" => 7,
      "source_tx_hash" => "0xabcd000000000000000000000000000000000000000000000000000000000000",
      "bridge_mint" => %{
        "tx_hash_2d" => "0xface000000000000000000000000000000000000000000000000000000000000",
        "amount" => "1000000",
        "eth_event_id" => "0x8a26217d2693abf40185791db4ca9889b322f73e5645ab1c2842139185c1b66c"
      }
    }
  }

  @bridge_lock_payload %{
    "kind" => "bridge_lock",
    "data" => %{
      "amount" => "1000000",
      "eth_event_id" => "0x8a26217d2693abf40185791db4ca9889b322f73e5645ab1c2842139185c1b66c",
      "htlc_hash" => "0xc0de000000000000000000000000000000000000000000000000000000000000",
      "preimage_hash" => "0xc0de000000000000000000000000000000000000000000000000000000000000",
      "recipient" => "0xfe00000000000000000000000000000000000000",
      "source_chain_id" => 1,
      "source_log_index" => 7,
      "source_tx_hash" => "0xabcd000000000000000000000000000000000000000000000000000000000000",
      "deadline_ms" => 1_700_000_000_000,
      "bridge_mint" => %{
        "tx_hash_2d" => "0xface000000000000000000000000000000000000000000000000000000000001",
        "amount" => "1000000",
        "eth_event_id" => "0x8a26217d2693abf40185791db4ca9889b322f73e5645ab1c2842139185c1b66c"
      },
      "htlc_swap" => %{
        "status" => "locked",
        "amount" => "1000000",
        "receiver" => "0xfe00000000000000000000000000000000000000"
      }
    }
  }

  @htlc_settle_payload %{
    "kind" => "htlc_settle",
    "data" => %{
      "lock_id" => "0xee00000000000000000000000000000000000000000000000000000000000000",
      "lock_tx_hash" => "0xface000000000000000000000000000000000000000000000000000000000000",
      "preimage" => "0xbe00000000000000000000000000000000000000000000000000000000000000",
      "htlc_swap" => %{
        "status" => "claimed",
        "amount" => "1000000",
        "receiver" => "0xfe00000000000000000000000000000000000000"
      }
    }
  }

  @htlc_refund_payload %{
    "kind" => "htlc_refund",
    "data" => %{
      "lock_id" => "0xee00000000000000000000000000000000000000000000000000000000000000",
      "lock_tx_hash" => "0xface000000000000000000000000000000000000000000000000000000000000",
      "htlc_swap" => %{
        "status" => "refunded",
        "amount" => "1000000",
        "receiver" => "0xfe00000000000000000000000000000000000000"
      }
    }
  }

  defp assert_card_golden!(name, payload) do
    card = TxBridgeCard.build(payload, @native_coin)
    html = TxBridgeCard.render_html(card)
    path = Path.join(@golden_dir, "#{name}.card.html")
    Golden.assert_golden!(path, html)
  end

  test "golden bridge_refill_mint card" do
    assert_card_golden!("refill_mint", @bridge_refill_payload)
  end

  test "golden bridge_lock card" do
    assert_card_golden!("bridge_lock", @bridge_lock_payload)
  end

  test "golden htlc_settle card" do
    assert_card_golden!("htlc_settle", @htlc_settle_payload)
  end

  test "golden htlc_refund card" do
    assert_card_golden!("htlc_refund", @htlc_refund_payload)
  end

  test "golden bridge endpoint 404 — no card fragment" do
    assert TxBridgeCard.build(nil, @native_coin) == nil
    Golden.assert_golden!(Path.join(@golden_dir, "endpoint_404.card.html"), "")
  end
end
