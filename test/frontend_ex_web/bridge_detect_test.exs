defmodule FrontendExWeb.BridgeDetectTest do
  use ExUnit.Case, async: true

  alias FrontendExWeb.BridgeDetect

  @bridge "0x2d0000000000000000000000000000000000000003"
  @htlc "0x2d0000000000000000000000000000000000000001"
  @other "0x0000000000000000000000000000000000000001"

  test "count_bridge_ops/1" do
    txs = [
      %{to: %{hash: @bridge}},
      %{to: %{hash: @htlc}},
      %{to: %{hash: @other}},
      %{to: nil}
    ]

    assert BridgeDetect.count_bridge_ops(txs) == 2
    assert BridgeDetect.count_bridge_ops([]) == 0
  end
end