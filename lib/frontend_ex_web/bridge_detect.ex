defmodule FrontendExWeb.BridgeDetect do
  @moduledoc """
  Bridge-transaction detection for SSR pages (TASK-48 block summary, TASK-49 tx card).

  Delegates address matching to `FrontendEx.BridgeTx` so precompile constants stay
  in one place.
  """

  alias FrontendEx.BridgeTx

  @doc "True when `to_hash` targets HTLC or BridgeRefillMint precompile."
  @spec bridge_candidate?(binary() | nil) :: boolean()
  def bridge_candidate?(to_hash), do: BridgeTx.bridge_candidate?(to_hash)

  @doc "Count txs in a parsed block/address list whose `to` is a bridge precompile."
  @spec count_bridge_ops([map()]) :: non_neg_integer()
  def count_bridge_ops(transactions) when is_list(transactions) do
    Enum.count(transactions, &bridge_tx?/1)
  end

  defp bridge_tx?(%{to: %{hash: hash}}), do: BridgeTx.bridge_candidate?(hash)
  defp bridge_tx?(_), do: false
end