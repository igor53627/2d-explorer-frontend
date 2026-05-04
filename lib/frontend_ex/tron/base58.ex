defmodule FrontendEx.Tron.Base58 do
  @moduledoc """
  Base58 codec (Bitcoin alphabet, same as Tron). Mirrors `Chain.Tron.Base58`
  in `~/pse/2d` — copied verbatim so the explorer doesn't need a runtime
  dependency on the chain code. If 2d's encoder ever changes, this must too.
  """

  @alphabet "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
  @alphabet_list String.graphemes(@alphabet)

  @doc "Encode a binary to Base58 (Bitcoin alphabet)."
  @spec encode(binary()) :: String.t()
  def encode(data) when is_binary(data) do
    leading_ones =
      data
      |> :binary.bin_to_list()
      |> Enum.take_while(&(&1 == 0))
      |> length()

    num = :binary.decode_unsigned(data, :big)
    body = encode_positive(num)
    String.duplicate("1", leading_ones) <> body
  end

  defp encode_positive(0), do: ""

  defp encode_positive(n) when n > 0 do
    encode_positive(div(n, 58)) <> String.at(@alphabet, rem(n, 58))
  end

  @doc "Decode a Base58 string (Bitcoin alphabet) to binary."
  @spec decode(String.t()) :: {:ok, binary()} | {:error, :invalid_character}
  def decode(""), do: {:error, :invalid_character}

  def decode(str) when is_binary(str) do
    graphemes = String.graphemes(str)

    leading_ones =
      graphemes
      |> Enum.take_while(&(&1 == "1"))
      |> length()

    rest = Enum.drop(graphemes, leading_ones)

    case decode_positive(rest, 0) do
      {:error, _} = e ->
        e

      {:ok, n} ->
        bin =
          if rest == [] do
            <<>>
          else
            int_to_minimal_be(n)
          end

        {:ok, :binary.copy(<<0>>, leading_ones) <> bin}
    end
  end

  defp decode_positive([], acc), do: {:ok, acc}

  defp decode_positive([c | rest], acc) do
    case Enum.find_index(@alphabet_list, &(&1 == c)) do
      nil -> {:error, :invalid_character}
      idx -> decode_positive(rest, acc * 58 + idx)
    end
  end

  defp int_to_minimal_be(0), do: <<>>
  defp int_to_minimal_be(n), do: :binary.encode_unsigned(n, :big)
end
