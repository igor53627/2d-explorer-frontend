defmodule FrontendEx.Tron.Base58Test do
  @moduledoc """
  Vectors verified against `Chain.Tron.Base58.encode/1,decode/1` in
  `~/pse/2d`. Both implementations use the Bitcoin alphabet — same as
  Tron mainnet.
  """

  use ExUnit.Case, async: true

  alias FrontendEx.Tron.Base58

  describe "encode/1 known-good vectors" do
    @vectors [
      # Wikipedia's Bitcoin Base58 entry (interpreted as a binary, no
      # check byte): "Hello World!" UTF-8.
      {"Hello World!", "2NEpo7TZRRrLZSi2U"},
      # Empty input → empty output (no leading zeros, no body).
      {"", ""},
      # Single null byte → single "1" (alphabet index for leading zeros).
      {<<0>>, "1"},
      # Three null bytes → three "1"s.
      {<<0, 0, 0>>, "111"},
      # Single non-zero byte at the value 1 — first non-leading-zero
      # alphabet character.
      {<<1>>, "2"},
      # Round-trippable: 0x010203
      {<<1, 2, 3>>, "Ldp"}
    ]

    for {raw, expected} <- @vectors do
      test "encode(#{inspect(raw)}) == #{inspect(expected)}" do
        assert Base58.encode(unquote(raw)) == unquote(expected)
      end

      test "decode(#{inspect(expected)}) round-trips to #{inspect(raw)}" do
        case unquote(expected) do
          "" ->
            # Empty Base58 is rejected (matches 2d's encoder/decoder
            # contract — empty input is not a valid encoded string).
            assert Base58.decode("") == {:error, :invalid_character}

          encoded ->
            assert Base58.decode(encoded) == {:ok, unquote(raw)}
        end
      end
    end
  end

  describe "decode/1 errors" do
    test "non-alphabet character is rejected" do
      assert Base58.decode("invalid_character_0OIl") == {:error, :invalid_character}
    end
  end

  describe "encode/1 ↔ decode/1 round-trip" do
    test "any 20-byte binary survives encode→decode unchanged" do
      for _ <- 1..32 do
        bin = :crypto.strong_rand_bytes(20)
        encoded = Base58.encode(bin)
        assert {:ok, ^bin} = Base58.decode(encoded)
      end
    end
  end
end
