defmodule FrontendEx.BridgeTx do
  @moduledoc """
  Bridge-transaction detection for explorer pages (TASK-48/49).

  A tx is a **bridge candidate** when its `to` address is one of the 2d
  precompiles: HTLC (`0x2D…0001`) or BridgeRefillMint (`0x2D…0003`).
  """

  @htlc_hex "0x2d0000000000000000000000000000000000000001"
  @bridge_hex "0x2d0000000000000000000000000000000000000003"

  @doc "True when `to_hash` targets a bridge precompile (case-insensitive hex)."
  @spec bridge_candidate?(binary() | nil) :: boolean()
  def bridge_candidate?(nil), do: false

  def bridge_candidate?(to_hash) when is_binary(to_hash) do
    normalized = String.downcase(String.trim(to_hash))
    normalized in [@htlc_hex, @bridge_hex]
  end

  def bridge_candidate?(_), do: false

  @doc """
  Etherscan (or configured host) URL for an Ethereum mainnet source tx.

  Reads `:ethereum_tx_explorer_base` (default `https://etherscan.io/tx`).
  Only chain id `1` is supported today; other chains return `nil`.
  """
  @spec source_chain_tx_url(term(), binary()) :: binary() | nil
  def source_chain_tx_url(1, hash) when is_binary(hash) and hash != "" do
    if Regex.match?(~r/^(0x)?[0-9a-fA-F]{64}$/, hash) do
      base =
        Application.get_env(:frontend_ex, :ethereum_tx_explorer_base, "https://etherscan.io/tx")

      base = String.trim_trailing(base, "/")
      base <> "/" <> ensure_hex_prefix(hash)
    else
      nil
    end
  end

  def source_chain_tx_url(_, _), do: nil

  defp ensure_hex_prefix("0x" <> _ = h), do: h
  defp ensure_hex_prefix(h), do: "0x" <> h
end
