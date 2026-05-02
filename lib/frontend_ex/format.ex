defmodule FrontendEx.Format do
  @moduledoc false

  alias FrontendEx.Clock

  import Bitwise

  # Default native coin = USDC (6 decimals). Single-arity entry points
  # (`format_native_amount/1`, `format_native_amount_exact/1`) use this
  # for callers without `native_coin` in scope (e.g. SVG OG-image render).
  # Two-arity variants take the live decimals from `/api/v2/stats.native_coin`
  # so a future non-USDC token would format correctly without a code change.
  @default_decimals 6

  @doc "Default decimals when a caller has no `native_coin` in scope."
  def default_decimals, do: @default_decimals

  @doc """
  Format a native-coin amount (in base units) as a rounded display
  string. Threshold buckets mirror the original wei→ETH helper so very
  small amounts surface more decimal places.
  """
  @spec format_native_amount(binary()) :: binary()
  def format_native_amount(amount_str), do: format_native_amount(amount_str, @default_decimals)

  @spec format_native_amount(binary(), non_neg_integer()) :: binary()
  def format_native_amount(amount_str, decimals)
      when is_binary(amount_str) and is_integer(decimals) and decimals >= 0 do
    amount_str = String.trim(amount_str)
    base_units = Integer.pow(10, decimals)

    case Integer.parse(amount_str) do
      {n, ""} when n > 0 ->
        cond do
          # The threshold rule of thumb: bucket precision so very small
          # values still surface a non-zero fractional part.
          n < div(base_units, 1_000_000) -> format_native_rounded(n, 8, base_units)
          n < div(base_units, 1_000) -> format_native_rounded(n, 6, base_units)
          true -> format_native_rounded(n, 4, base_units)
        end

      {0, ""} ->
        "0"

      _ ->
        "0"
    end
  end

  # Exact decimal representation — no rounding.
  @spec format_native_amount_exact(binary()) :: binary()
  def format_native_amount_exact(amount_str),
    do: format_native_amount_exact(amount_str, @default_decimals)

  @spec format_native_amount_exact(binary(), non_neg_integer()) :: binary()
  def format_native_amount_exact(amount_str, decimals)
      when is_binary(amount_str) and is_integer(decimals) and decimals >= 0 do
    amount_str = String.trim(amount_str)
    base_units = Integer.pow(10, decimals)

    case Integer.parse(amount_str) do
      {n, ""} when is_integer(n) and n >= 0 ->
        whole = div(n, base_units)
        frac = rem(n, base_units)

        if frac == 0 do
          Integer.to_string(whole)
        else
          frac_str =
            frac
            |> Integer.to_string()
            |> String.pad_leading(decimals, "0")
            |> String.trim_trailing("0")

          "#{whole}.#{frac_str}"
        end

      _ ->
        "0"
    end
  end

  defp format_native_rounded(amount, dp, base_units)
       when is_integer(amount) and amount >= 0 and dp >= 0 do
    pow10 = Integer.pow(10, dp)

    # Round half-up to the requested decimal places.
    numerator = amount * pow10
    scaled = div(numerator + div(base_units, 2), base_units)

    int_part = div(scaled, pow10)
    frac_part = rem(scaled, pow10)

    if dp == 0 do
      Integer.to_string(int_part)
    else
      frac = frac_part |> Integer.to_string() |> String.pad_leading(dp, "0")
      "#{int_part}.#{frac}"
    end
  end

  @spec format_method_name(binary()) :: binary()
  def format_method_name(method) when is_binary(method) do
    trimmed = String.trim(method)

    cond do
      trimmed == "" ->
        "-"

      String.starts_with?(trimmed, "0x") ->
        trimmed

      true ->
        spaced =
          trimmed
          |> String.graphemes()
          |> Enum.reduce({[], false, false}, fn ch, {acc, prev_lower, prev_digit} ->
            cond do
              ch == "_" or ch == "-" ->
                acc =
                  case acc do
                    [" " | _] -> acc
                    _ -> [" " | acc]
                  end

                {acc, false, false}

              true ->
                is_upper = ch >= "A" and ch <= "Z"
                is_lower = ch >= "a" and ch <= "z"
                is_digit = ch >= "0" and ch <= "9"

                acc =
                  cond do
                    is_upper and (prev_lower or prev_digit) -> [ch, " " | acc]
                    is_digit and prev_lower -> [ch, " " | acc]
                    true -> [ch | acc]
                  end

                {acc, is_lower, is_digit}
            end
          end)
          |> then(fn {acc, _pl, _pd} -> acc |> Enum.reverse() |> Enum.join("") end)

        spaced
        |> String.split(~r/\s+/, trim: true)
        |> Enum.map(fn word ->
          is_all_caps =
            word
            |> String.to_charlist()
            |> Enum.all?(fn c -> not (c >= ?a and c <= ?z) end)

          if is_all_caps do
            word
          else
            [first | rest] = String.graphemes(word)
            String.upcase(first) <> String.downcase(Enum.join(rest, ""))
          end
        end)
        |> Enum.join(" ")
    end
  end

  @spec checksum_eth_address(binary()) :: binary()
  def checksum_eth_address(addr) when is_binary(addr) do
    trimmed = String.trim(addr)

    hex =
      cond do
        String.starts_with?(trimmed, "0x") -> String.slice(trimmed, 2..-1//1)
        String.starts_with?(trimmed, "0X") -> String.slice(trimmed, 2..-1//1)
        true -> nil
      end

    cond do
      is_nil(hex) ->
        trimmed

      String.length(hex) != 40 ->
        trimmed

      not String.match?(hex, ~r/\A[0-9A-Fa-f]{40}\z/) ->
        trimmed

      true ->
        lower = String.downcase(hex)
        hash = keccak256(lower)

        if is_nil(hash) do
          trimmed
        else
          checksummed =
            lower
            |> String.graphemes()
            |> Enum.with_index()
            |> Enum.map(fn {ch, i} ->
              if ch >= "0" and ch <= "9" do
                ch
              else
                byte = :binary.at(hash, div(i, 2))
                nibble = if rem(i, 2) == 0, do: byte >>> 4, else: byte &&& 0x0F
                if nibble >= 8, do: String.upcase(ch), else: ch
              end
            end)
            |> Enum.join("")

          "0x" <> checksummed
        end
    end
  end

  defp keccak256(data) when is_binary(data) do
    case KeccakEx.hash_256(data) do
      <<_::binary-size(32)>> = bin ->
        bin

      hash when is_binary(hash) ->
        hash = String.trim(hash)
        hash = if String.starts_with?(hash, "0x"), do: String.slice(hash, 2..-1//1), else: hash

        case Base.decode16(hash, case: :mixed) do
          {:ok, bin} when byte_size(bin) == 32 -> bin
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @spec format_one_decimal(number()) :: binary()
  def format_one_decimal(v) when is_number(v) do
    # Erlang's `~.1f` expects a float; integer input is a badarg.
    v = if is_integer(v), do: v * 1.0, else: v
    :io_lib.format("~.1f", [v]) |> IO.iodata_to_binary()
  end

  @spec format_number_with_commas(binary()) :: binary()
  def format_number_with_commas(s) when is_binary(s) do
    s = String.trim(s)

    case Integer.parse(s) do
      {n, ""} when n >= 0 ->
        n |> Integer.to_string() |> insert_thousands_commas()

      _ ->
        s
    end
  end

  @doc """
  Formats a chain count that may arrive as either a binary (upstream
  Blockscout shape) or a non-negative JSON integer (2d's API shape). Anything
  else returns `nil` so callers can render a `-` placeholder.
  """
  @spec format_count(term()) :: binary() | nil
  def format_count(v) when is_binary(v), do: format_number_with_commas(v)

  def format_count(v) when is_integer(v) and v >= 0,
    do: v |> Integer.to_string() |> format_number_with_commas()

  def format_count(_), do: nil

  defp format_int_with_commas_str(int_part) when is_binary(int_part) do
    s = String.trim(int_part)
    if s == "", do: "0", else: insert_thousands_commas(s)
  end

  # Insert commas every 3 ASCII digits from the right. O(n) single pass —
  # the prior implementation used 7 Enum passes (graphemes/reverse/chunk/
  # map-reverse/reverse/map-join/join).
  #
  # This operates on raw bytes, so non-ASCII-digit input is passed through
  # unchanged (format_int_with_commas_str may receive non-numeric "int parts"
  # from format_decimal_with_commas; we don't want to split mid-codepoint).
  defp insert_thousands_commas(s) when is_binary(s) do
    if ascii_digits_only?(s) do
      do_insert_commas(s)
    else
      s
    end
  end

  defp ascii_digits_only?(<<>>), do: true

  defp ascii_digits_only?(<<c, rest::binary>>) when c >= ?0 and c <= ?9,
    do: ascii_digits_only?(rest)

  defp ascii_digits_only?(_), do: false

  defp do_insert_commas(s) do
    size = byte_size(s)

    if size <= 3 do
      s
    else
      head_size = rem(size, 3)

      {head, rest} =
        if head_size == 0 do
          {binary_part(s, 0, 3), binary_part(s, 3, size - 3)}
        else
          {binary_part(s, 0, head_size), binary_part(s, head_size, size - head_size)}
        end

      # Build as iodata and materialize once. The earlier form
      # `head <> "," <> comma_every_three(rest)` allocated a fresh binary at
      # every recursion level (each `<>` copies the growing suffix).
      IO.iodata_to_binary([head | comma_every_three(rest)])
    end
  end

  defp comma_every_three(<<a::binary-size(3)>>), do: [",", a]

  defp comma_every_three(<<a::binary-size(3), rest::binary>>),
    do: [",", a | comma_every_three(rest)]

  @spec format_decimal_with_commas(binary()) :: binary()
  def format_decimal_with_commas(value) when is_binary(value) do
    s = String.trim(value)

    case String.split(s, ".", parts: 2) do
      [int_part, frac_part] ->
        int_part = format_int_with_commas_str(int_part)

        if frac_part == "" do
          int_part
        else
          int_part <> "." <> frac_part
        end

      [int_part] ->
        format_int_with_commas_str(int_part)
    end
  end

  @spec unit_to_decimal_value(binary(), non_neg_integer()) :: binary()
  def unit_to_decimal_value(raw, decimals)
      when is_binary(raw) and is_integer(decimals) and decimals >= 0 do
    s =
      raw
      |> String.trim()
      |> String.trim_leading("0")

    cond do
      s == "" ->
        "0"

      decimals == 0 ->
        s

      String.length(s) <= decimals ->
        padded = String.pad_leading(s, decimals, "0")
        frac = String.trim_trailing(padded, "0")

        if frac == "" do
          "0"
        else
          "0." <> frac
        end

      true ->
        split_at = String.length(s) - decimals
        {int_part, frac_part} = String.split_at(s, split_at)
        frac = String.trim_trailing(frac_part, "0")

        if frac == "" do
          int_part
        else
          int_part <> "." <> frac
        end
    end
  end

  @spec format_price_with_commas(binary()) :: binary()
  def format_price_with_commas(s) when is_binary(s) do
    case String.split(s, ".", parts: 2) do
      [int_part, frac_part] ->
        format_number_with_commas(int_part) <> "." <> frac_part

      [int_part] ->
        format_number_with_commas(int_part)
    end
  end

  @spec truncate_hash(binary()) :: binary()
  def truncate_hash(s) when is_binary(s) do
    if byte_size(s) > 12 do
      prefix = binary_part(s, 0, 6)
      suffix = binary_part(s, byte_size(s) - 4, 4)
      prefix <> "..." <> suffix
    else
      s
    end
  end

  @spec truncate_addr(binary()) :: binary()
  def truncate_addr(s) when is_binary(s) do
    if byte_size(s) > 10 do
      prefix = binary_part(s, 0, min(4, byte_size(s)))
      suffix = binary_part(s, max(byte_size(s) - 4, 0), min(4, byte_size(s)))
      prefix <> "..." <> suffix
    else
      s
    end
  end

  @spec truncate_addr_classic(binary()) :: binary()
  def truncate_addr_classic(s) when is_binary(s) do
    prefix_len = 10
    suffix_len = 9

    if byte_size(s) <= prefix_len + suffix_len + 3 do
      s
    else
      prefix = binary_part(s, 0, min(prefix_len, byte_size(s)))
      suffix_start = max(byte_size(s) - suffix_len, 0)
      suffix = binary_part(s, suffix_start, byte_size(s) - suffix_start)
      prefix <> "..." <> suffix
    end
  end

  @spec format_relative_time(binary()) :: binary()
  def format_relative_time(timestamp) when is_binary(timestamp) do
    timestamp = String.trim(timestamp)

    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} ->
        now = Clock.utc_now()
        secs = max(DateTime.diff(now, dt, :second), 0)

        cond do
          secs < 60 ->
            unit = if secs == 1, do: "sec", else: "secs"
            "#{secs} #{unit} ago"

          secs < 3600 ->
            mins = div(secs, 60)
            unit = if mins == 1, do: "min", else: "mins"
            "#{mins} #{unit} ago"

          secs < 86_400 ->
            hours = div(secs, 3600)
            unit = if hours == 1, do: "hr", else: "hrs"
            "#{hours} #{unit} ago"

          true ->
            days = div(secs, 86_400)

            cond do
              days < 30 ->
                unit = if days == 1, do: "day", else: "days"
                "#{days} #{unit} ago"

              days < 365 ->
                months = div(days, 30)
                unit = if months == 1, do: "mth", else: "mths"
                "#{months} #{unit} ago"

              true ->
                years = div(days, 365)
                unit = if years == 1, do: "yr", else: "yrs"
                "#{years} #{unit} ago"
            end
        end

      _ ->
        timestamp
    end
  end

  # Matches Rust `blocks.rs`: always plural `secs/mins/hrs/days`, and stops at days.
  @spec format_blocks_time_ago(binary()) :: binary()
  def format_blocks_time_ago(timestamp) when is_binary(timestamp) do
    timestamp = String.trim(timestamp)

    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} ->
        now = Clock.utc_now()
        secs = max(DateTime.diff(now, dt, :second), 0)

        cond do
          secs < 60 ->
            "#{secs} secs ago"

          true ->
            mins = div(secs, 60)

            cond do
              mins < 60 ->
                "#{mins} mins ago"

              true ->
                hours = div(secs, 3600)

                cond do
                  hours < 24 ->
                    "#{hours} hrs ago"

                  true ->
                    days = div(secs, 86_400)
                    "#{days} days ago"
                end
            end
        end

      _ ->
        timestamp
    end
  end

  @spec format_readable_date(binary()) :: binary()
  def format_readable_date(timestamp) when is_binary(timestamp) do
    timestamp = String.trim(timestamp)

    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} ->
        Calendar.strftime(dt, "%b %d, %Y %H:%M:%S UTC")

      _ ->
        timestamp
    end
  end

  @spec format_readable_date_classic_plus_utc(binary()) :: binary()
  def format_readable_date_classic_plus_utc(timestamp) when is_binary(timestamp) do
    timestamp = String.trim(timestamp)

    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} ->
        Calendar.strftime(dt, "%b-%d-%Y %I:%M:%S %p +UTC")

      _ ->
        timestamp
    end
  end

  @spec format_readable_date_classic(binary()) :: binary()
  def format_readable_date_classic(timestamp) when is_binary(timestamp) do
    timestamp = String.trim(timestamp)

    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} ->
        Calendar.strftime(dt, "%b-%d-%Y %I:%M:%S %p UTC")

      _ ->
        timestamp
    end
  end
end
