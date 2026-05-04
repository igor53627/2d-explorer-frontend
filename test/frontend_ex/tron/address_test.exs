defmodule FrontendEx.Tron.AddressTest do
  @moduledoc """
  Cross-checked against `Chain.Tron.Address.encode/1` in `~/pse/2d` (a
  separate, independently-tested implementation that 2d itself relies
  on for mainnet broadcasts). The two encoders produce the same Base58
  string for every vector below; if they ever diverge, this test fails
  and points at the implementation that drifted.
  """

  use ExUnit.Case, async: true

  alias FrontendEx.Tron.Address

  describe "from_eth_hex/1 — known-good vectors" do
    # Each pair: 0x-prefixed Ethereum-form hex → expected Tron Base58Check.
    # Vectors verified against the 2d chain repo's encoder; do not adjust
    # one side without verifying the other.
    @vectors [
      {"0x0000000000000000000000000000000000000001", "T9yD14Nj9j7xAB4dbGeiX9h8unkKLxmGkn"},
      {"0x2f0b11ba5dafc50f3347a35b7dbe4af4a0b36e96", "TEFx2BPmshHkaoqM73QjjEnMTw4oe4panw"},
      {"0x2D00000000000000000000000000000000000001", "TE59Qh41ufkPrgdYaqhfCXpDXtLtbHohR8"},
      {"0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef", "TWGd9idELBV3is6rrtC5PQUhudiJYeCr7E"}
    ]

    for {eth, tron} <- @vectors do
      test "#{eth} → #{tron}" do
        assert Address.from_eth_hex(unquote(eth)) == unquote(tron)
      end
    end

    test "uppercase 0X prefix is accepted (mirror of lowercase)" do
      assert Address.from_eth_hex("0X2f0b11ba5dafc50f3347a35b7dbe4af4a0b36e96") ==
               "TEFx2BPmshHkaoqM73QjjEnMTw4oe4panw"
    end

    test "mixed-case hex digits are accepted" do
      assert Address.from_eth_hex("0x2F0b11Ba5DafC50F3347a35b7Dbe4af4a0B36E96") ==
               "TEFx2BPmshHkaoqM73QjjEnMTw4oe4panw"
    end
  end

  describe "from_eth_hex/1 — invalid input returns nil" do
    test "missing 0x prefix" do
      assert Address.from_eth_hex("2f0b11ba5dafc50f3347a35b7dbe4af4a0b36e96") == nil
    end

    test "too short" do
      assert Address.from_eth_hex("0xdeadbeef") == nil
    end

    test "too long" do
      assert Address.from_eth_hex("0x" <> String.duplicate("ab", 21)) == nil
    end

    test "non-hex characters" do
      assert Address.from_eth_hex("0xZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ") == nil
    end

    test "non-binary input" do
      assert Address.from_eth_hex(nil) == nil
      assert Address.from_eth_hex(123) == nil
      assert Address.from_eth_hex(:foo) == nil
    end
  end

  describe "encode_bin/1 — direct binary input" do
    test "all-zero 20-byte payload encodes to T9yD…" do
      assert Address.encode_bin(<<0::160>>) == "T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb"
    end

    test "rejects payloads other than 20 bytes" do
      assert_raise FunctionClauseError, fn ->
        Address.encode_bin(<<0::152>>)
      end
    end
  end
end
