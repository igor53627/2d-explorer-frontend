defmodule FrontendExWeb.Parsers do
  @moduledoc """
  Input parsers and validators shared by controllers.

  Exposed via the `:controller` macro in `frontend_ex_web.ex`, so every
  controller can call these directly (`parse_u64/1`, `eth_address?/1`, …).

  Validators return booleans; parsers return a value or `nil` / an explicit
  fallback. None of these functions raise on malformed input.
  """

  @address_re ~r/\A0x[0-9a-fA-F]{40}\z/i
  @hash32_re ~r/\A0x[0-9a-fA-F]{64}\z/i
  @decimal_re ~r/\A\d+\z/

  # u64 max = 2^64 - 1. Upstream numeric fields (block numbers, tx counts,
  # indexes) fit within this range; anything larger is malformed and returns
  # nil from parse_u64/1.
  @u64_max 18_446_744_073_709_551_615

  @doc "Regex matching an EVM address (`0x` + 40 hex chars, case-insensitive prefix)."
  @spec address_regex() :: Regex.t()
  def address_regex, do: @address_re

  @doc "Regex matching a 32-byte hex hash (tx hash or block hash), case-insensitive prefix."
  @spec hash32_regex() :: Regex.t()
  def hash32_regex, do: @hash32_re

  @doc """
  Returns `true` iff `v` is an EVM-style address (`0x` + 40 hex chars). The
  prefix is case-insensitive (`0x` or `0X`).

  Does not trim; callers should trim first if needed.
  """
  @spec eth_address?(term()) :: boolean()
  def eth_address?(v) when is_binary(v), do: Regex.match?(@address_re, v)
  def eth_address?(_), do: false

  @doc """
  Returns `true` iff `v` is a 32-byte hex hash (`0x` + 64 hex chars). The
  prefix is case-insensitive. Covers transaction and block hashes alike.
  """
  @spec tx_hash?(term()) :: boolean()
  def tx_hash?(v) when is_binary(v), do: Regex.match?(@hash32_re, v)
  def tx_hash?(_), do: false

  @doc """
  Returns `true` iff `v` is a valid block identifier: either a non-negative
  decimal string (block number, bounded to `u64`) or a 32-byte hex hash.

  Decimal strings above `2^64 - 1` are rejected so the route gate matches the
  downstream `parse_u64/1` contract — prevents oversized path segments from
  slipping past the router as "valid" block IDs.
  """
  @spec block_id?(term()) :: boolean()
  def block_id?(v) when is_binary(v) do
    cond do
      Regex.match?(@hash32_re, v) -> true
      Regex.match?(@decimal_re, v) -> u64_decimal?(v)
      true -> false
    end
  end

  def block_id?(_), do: false

  defp u64_decimal?(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} when n >= 0 and n <= @u64_max -> true
      _ -> false
    end
  end

  @doc """
  Parses a non-negative integer (`u64`-shaped) from an integer or binary.

  Whitespace in binaries is trimmed. Returns `nil` on any failure, including
  negative values and values above `2^64 - 1`.
  """
  @spec parse_u64(term()) :: non_neg_integer() | nil
  def parse_u64(v) when is_integer(v) and v >= 0 and v <= @u64_max, do: v
  def parse_u64(v) when is_integer(v), do: nil

  def parse_u64(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} when n >= 0 and n <= @u64_max -> n
      _ -> nil
    end
  end

  def parse_u64(_), do: nil

  @doc """
  Parses an integer from a binary or returns it passthrough if already an
  integer. Returns `fallback` for `nil`, unparseable binaries, or any other
  shape. Whitespace in binaries is trimmed.
  """
  @spec parse_int_or(term(), term()) :: integer() | term()
  def parse_int_or(nil, fallback), do: fallback
  def parse_int_or(v, _fallback) when is_integer(v), do: v

  def parse_int_or(v, fallback) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} -> n
      _ -> fallback
    end
  end

  def parse_int_or(_v, fallback), do: fallback

  @doc """
  Returns a trimmed binary, or `nil` for any non-binary input.
  """
  @spec normalize_opt_string(term()) :: binary() | nil
  def normalize_opt_string(v) when is_binary(v), do: String.trim(v)
  def normalize_opt_string(_), do: nil

  @doc """
  Like `normalize_opt_string/1`, but also accepts non-negative integers and
  renders them as decimal strings. Use this for upstream-vs-2d shape
  divergence on numeric-string fields (gas_used, gas_price, base_fee_per_gas
  …): upstream Blockscout returns these as JSON strings, 2d's API as JSON
  integers. Downstream callers (`Format.format_native_amount/1`,
  `Integer.parse/1`) want a binary either way.
  """
  @spec normalize_int_or_string(term()) :: binary() | nil
  def normalize_int_or_string(v) when is_binary(v), do: String.trim(v)
  def normalize_int_or_string(v) when is_integer(v) and v >= 0, do: Integer.to_string(v)
  def normalize_int_or_string(_), do: nil
end
