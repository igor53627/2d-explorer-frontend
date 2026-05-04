defmodule FrontendExWeb.ControllerHelpers do
  @moduledoc """
  Helpers shared by parity controllers.

  Controllers gain these via the `use FrontendExWeb, :controller` macro
  (which imports this module).

  Exposes:
    * `safe_empty/0` — `{:safe, ""}` placeholder for pre-rendered HTML assigns
    * `explorer_url/0` — resolves the upstream explorer URL
    * `base_assigns/1` — common assigns map (nav flags, html fragment placeholders, explorer_url)
    * `await_ok/4`, `await_many_ok/3` — task awaiting with consistent Logger.warning on failure
    * `derive_coin_gas/1` — stats-JSON → `{coin_price_string, gas_price_string}`
  """

  require Logger
  alias FrontendEx.Format
  alias FrontendEx.Version

  @default_blockscout_url "http://localhost:4001"
  @default_timeout_ms 10_000
  @safe_empty {:safe, ""}

  @doc "Empty safe iodata placeholder used for unfilled HTML fragments."
  @spec safe_empty() :: {:safe, iodata()}
  def safe_empty, do: @safe_empty

  @doc """
  Resolves the public-facing explorer URL from application env (set by
  `runtime.exs` from `BLOCKSCOUT_URL`), falling back to a local-dev default.
  """
  @spec explorer_url() :: binary()
  def explorer_url do
    Application.get_env(:frontend_ex, :blockscout_url, @default_blockscout_url)
  end

  @doc """
  Common assigns map used by parity renders.

  Fills nav flags, head_meta/styles/scripts/topbar with safe defaults, and
  `explorer_url`. Extra keys merge on top (they win over defaults).
  """
  @spec base_assigns(map() | keyword()) :: map()
  def base_assigns(extras \\ %{}) do
    backend = Version.backend()

    base = %{
      page_title: "",
      explorer_url: explorer_url(),
      head_meta: @safe_empty,
      styles: @safe_empty,
      scripts: @safe_empty,
      topbar: @safe_empty,
      nav_home: "",
      nav_blocks: "",
      nav_txs: "",
      nav_tokens: "",
      nav_nfts: "",
      app_version: Version.app(),
      git_sha: Version.sha(),
      # Default native coin used when a controller didn't pass one (for
      # example error pages, share cards). Real per-page rendering passes
      # the value from `derive_native_coin/1` so the symbol/decimals
      # follow the live `/api/v2/stats.native_coin` shape.
      native_coin: default_native_coin(),
      # `Map.get/2` is defensive: an override with unexpected keys would
      # otherwise crash the request via `backend.version` KeyError.
      backend_version: backend && Map.get(backend, :version),
      backend_sha: backend && Map.get(backend, :sha)
    }

    Map.merge(base, Map.new(extras))
  end

  @doc """
  Awaits a single task that resolves to `{:ok, _} | {:error, _}`.

  On `:error`, crash, or timeout, logs under `log_prefix` (e.g. `"home"`) with
  `endpoint: label` and returns `nil`.

  Uses `Task.yield/2` + `Task.shutdown/2` rather than `Task.await/2` so the
  task is explicitly terminated on timeout (not just abandoned to the linked
  parent-exit mechanism). Matches the pattern in `await_many_ok/3`.
  """
  @spec await_ok(Task.t(), binary(), binary(), pos_integer()) :: term() | nil
  def await_ok(%Task{} = task, log_prefix, label, timeout_ms \\ @default_timeout_ms) do
    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, json}} ->
        json

      {:ok, {:error, reason}} ->
        Logger.warning("#{log_prefix}: upstream request failed",
          endpoint: label,
          reason: inspect(reason)
        )

        nil

      {:ok, other} ->
        Logger.warning("#{log_prefix}: upstream request returned unexpected result",
          endpoint: label,
          result: inspect(other)
        )

        nil

      {:exit, reason} ->
        Logger.warning("#{log_prefix}: upstream task crashed",
          endpoint: label,
          reason: inspect(reason)
        )

        nil

      nil ->
        Logger.warning("#{log_prefix}: upstream request timed out",
          endpoint: label,
          timeout_ms: timeout_ms
        )

        nil
    end
  end

  @doc """
  Awaits a list of `{label, Task.t()}` pairs concurrently.

  Returns values in the same order as the input. Any task that fails, times out,
  or crashes is logged under `log_prefix` and returned as `nil`.
  """
  @spec await_many_ok([{binary(), Task.t()}], binary(), pos_integer()) :: [term() | nil]
  def await_many_ok(labeled_tasks, log_prefix, timeout_ms \\ @default_timeout_ms)
      when is_list(labeled_tasks) and is_integer(timeout_ms) do
    labels_by_ref =
      Map.new(labeled_tasks, fn {label, %Task{ref: ref}} -> {ref, label} end)

    tasks = Enum.map(labeled_tasks, &elem(&1, 1))

    tasks
    |> Task.yield_many(timeout_ms)
    |> Enum.map(fn {task, res} ->
      label = Map.get(labels_by_ref, task.ref, "unknown")

      case res do
        {:ok, {:ok, json}} ->
          json

        {:ok, {:error, reason}} ->
          Logger.warning("#{log_prefix}: upstream request failed",
            endpoint: label,
            reason: inspect(reason)
          )

          nil

        {:ok, other} ->
          Logger.warning("#{log_prefix}: upstream request returned unexpected result",
            endpoint: label,
            result: inspect(other)
          )

          nil

        {:exit, reason} ->
          Logger.warning("#{log_prefix}: upstream task crashed",
            endpoint: label,
            reason: inspect(reason)
          )

          nil

        nil ->
          # `Task.yield_many/2` did not consume the reply message from the
          # mailbox, so `Task.shutdown/2` can still return a late result here
          # (per https://hexdocs.pm/elixir/Task.html#shutdown/2). Pattern-match
          # its return so we don't misclassify a just-in-time reply as a
          # timeout — symmetric with await_ok/4.
          case Task.shutdown(task, :brutal_kill) do
            {:ok, {:ok, json}} ->
              json

            {:ok, {:error, reason}} ->
              Logger.warning("#{log_prefix}: upstream request failed",
                endpoint: label,
                reason: inspect(reason)
              )

              nil

            {:ok, other} ->
              Logger.warning("#{log_prefix}: upstream request returned unexpected result",
                endpoint: label,
                result: inspect(other)
              )

              nil

            {:exit, reason} ->
              Logger.warning("#{log_prefix}: upstream task crashed",
                endpoint: label,
                reason: inspect(reason)
              )

              nil

            nil ->
              Logger.warning("#{log_prefix}: upstream request timed out",
                endpoint: label,
                timeout_ms: timeout_ms
              )

              nil
          end
      end
    end)
  end

  @doc """
  Derives `{coin_price, gas_price}` formatted display strings from a stats JSON
  map (e.g. the response body of `/api/v2/stats`).

  Returns `{nil, nil}` if the input is nil or malformed.
  """
  @spec derive_coin_gas(map() | nil) :: {binary() | nil, binary() | nil}
  def derive_coin_gas(nil), do: {nil, nil}

  def derive_coin_gas(%{} = stats_json) do
    coin_price =
      case stats_json["coin_price"] do
        v when is_binary(v) -> Format.format_price_with_commas(v)
        _ -> nil
      end

    gas_price =
      case get_in(stats_json, ["gas_prices", "average", "price"]) do
        v when is_number(v) -> Format.format_one_decimal(v)
        _ -> nil
      end

    {coin_price, gas_price}
  end

  def derive_coin_gas(_), do: {nil, nil}

  @doc """
  Extract `native_coin: %{symbol, decimals}` from the `/api/v2/stats`
  response body.

  Falls back to the 2d default (`%{symbol: "USDC", decimals: 6}`) when
  the field is missing or malformed — the fork is hard-pinned to 2d, so
  USDC is the right default for every consumer.
  """
  @spec derive_native_coin(map() | nil) :: %{symbol: String.t(), decimals: non_neg_integer()}
  def derive_native_coin(%{"native_coin" => %{"symbol" => sym, "decimals" => dec}})
      when is_binary(sym) and sym != "" and is_integer(dec) and dec >= 0,
      do: %{symbol: sym, decimals: dec}

  # Blank symbol falls back to the default — rendering an empty ticker
  # next to a balance is worse than showing "USDC".
  def derive_native_coin(_), do: default_native_coin()

  @doc "Per-fork default `native_coin` map — 2d uses USDC at 6 decimals."
  @spec default_native_coin() :: %{symbol: String.t(), decimals: non_neg_integer()}
  def default_native_coin, do: %{symbol: "USDC", decimals: 6}
end
