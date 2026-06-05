defmodule FrontendEx.BridgeTxTest do
  use ExUnit.Case, async: false

  alias FrontendEx.BridgeTx

  test "bridge_candidate? for HTLC and Bridge precompile addresses" do
    assert BridgeTx.bridge_candidate?("0x2D0000000000000000000000000000000000000001")
    assert BridgeTx.bridge_candidate?("0x2d0000000000000000000000000000000000000003")
    refute BridgeTx.bridge_candidate?("0x0000000000000000000000000000000000000001")
    refute BridgeTx.bridge_candidate?(nil)
  end

  test "source_chain_tx_url uses configured base" do
    hash = "0x" <> String.duplicate("ab", 32)

    assert BridgeTx.source_chain_tx_url(1, hash) ==
             "https://etherscan.io/tx/" <> hash

    Application.put_env(
      :frontend_ex,
      :ethereum_tx_explorer_base,
      "https://sepolia.etherscan.io/tx"
    )

    on_exit(fn -> Application.delete_env(:frontend_ex, :ethereum_tx_explorer_base) end)

    assert BridgeTx.source_chain_tx_url(1, hash) ==
             "https://sepolia.etherscan.io/tx/" <> hash
  end

  test "bridge_detail_href and valid_eth_event_id?" do
    id = "0x" <> String.duplicate("a", 64)

    assert BridgeTx.bridge_detail_href(id) == "/bridges/" <> id
    assert BridgeTx.valid_eth_event_id?(id)
    refute BridgeTx.valid_eth_event_id?("0xabc")
    refute BridgeTx.valid_eth_event_id?("not-a-hash")
  end
end
