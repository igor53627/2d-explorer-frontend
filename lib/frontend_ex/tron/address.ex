defmodule FrontendEx.Tron.Address do
  @moduledoc """
  0x ↔ Tron-base58 address codec for the unified-account display.

  2d's design pins one internal account to two wallet surfaces (`eth_*`
  and `/wallet/*`) — the same 20-byte account renders as `0x…` in
  Ethereum-form or `T…` in Tron-form (Base58Check over `0x41 || addr`).
  Derivation is deterministic, so the explorer always shows both.

  Mirrors `Chain.Tron.Address.encode/1` in `~/pse/2d`.
  """

  alias FrontendEx.Tron.Base58

  @mainnet_version 0x41

  @doc """
  Render a 0x-prefixed Ethereum-form hex address as its Tron-form
  Base58Check string (T…). Returns `nil` for any non-conforming input
  (wrong length, non-hex, missing prefix) so call-sites can `||` past
  failures without raising.
  """
  @spec from_eth_hex(term()) :: binary() | nil
  def from_eth_hex(<<"0x", hex::binary-40>>), do: encode_hex(hex)
  def from_eth_hex(<<"0X", hex::binary-40>>), do: encode_hex(hex)
  def from_eth_hex(_), do: nil

  defp encode_hex(hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, <<addr::binary-20>>} -> encode_bin(addr)
      _ -> nil
    end
  end

  @doc "Base58Check encode a 20-byte account as Tron mainnet address (T…)."
  @spec encode_bin(<<_::160>>) :: binary()
  def encode_bin(<<_::binary-20>> = address) do
    payload = <<@mainnet_version>> <> address
    checksum = :binary.part(:crypto.hash(:sha256, :crypto.hash(:sha256, payload)), 0, 4)
    Base58.encode(payload <> checksum)
  end
end
