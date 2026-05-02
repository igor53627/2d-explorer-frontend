defmodule FrontendExWeb.TxSubpagesParityTest do
  # Parity tests mutate global Application env (skin, URLs), so they must be serial.
  use FrontendExWeb.ConnCase, async: false

  alias FrontendEx.TestSupport.Golden

  @success_hash "0xa4e0caea19db95858a73899bf85cb9db999c97dd840a2472ae92d311b84b4126"
  @pending_hash "0x1111111111111111111111111111111111111111111111111111111111111111"

  @golden_logs_path Path.expand("../golden/tx_logs.classic.rust.html", __DIR__)
  @golden_state_path Path.expand("../golden/tx_state.classic.rust.html", __DIR__)
  @golden_card_path Path.expand("../golden/tx_card.53627.rust.html", __DIR__)
  @golden_og_svg_path Path.expand("../golden/tx_og_image.rust.svg", __DIR__)

  @frozen_now ~U[2026-02-01 00:00:00Z]
  @fixture_api_url "http://127.0.0.1:4901"
  @explorer_url "https://sepolia.53627.org"
  @base_url "https://fast.53627.org"

  test "classic /tx/:hash/logs matches Rust HTML byte-for-byte" do
    restore =
      put_env(%{
        ff_skin: "classic",
        blockscout_url: @explorer_url,
        blockscout_api_url: @fixture_api_url,
        blockscout_ws_url: nil,
        base_url: @base_url,
        clock_utc_now: @frozen_now
      })

    on_exit(restore)

    body = html_response(get(build_conn(), "/tx/#{@success_hash}/logs"), 200)

    Golden.assert_golden!(@golden_logs_path, body)
  end

  test "classic /tx/:hash/state matches Rust HTML byte-for-byte" do
    restore =
      put_env(%{
        ff_skin: "classic",
        blockscout_url: @explorer_url,
        blockscout_api_url: @fixture_api_url,
        blockscout_ws_url: nil,
        base_url: @base_url,
        clock_utc_now: @frozen_now
      })

    on_exit(restore)

    body = html_response(get(build_conn(), "/tx/#{@success_hash}/state"), 200)

    Golden.assert_golden!(@golden_state_path, body)
  end

  # 2d-fork: /tx/:hash/internal removed (2d has no nested EVM call frames).

  test "tx share card /tx/:hash/card matches Rust HTML byte-for-byte" do
    restore =
      put_env(%{
        ff_skin: "53627",
        blockscout_url: @explorer_url,
        blockscout_api_url: @fixture_api_url,
        blockscout_ws_url: nil,
        base_url: @base_url,
        clock_utc_now: @frozen_now
      })

    on_exit(restore)

    body = html_response(get(build_conn(), "/tx/#{@pending_hash}/card"), 200)

    Golden.assert_golden!(@golden_card_path, body)
  end

  test "tx OG image /tx/:hash/og-image.svg matches Rust SVG byte-for-byte" do
    restore =
      put_env(%{
        ff_skin: "classic",
        blockscout_url: @explorer_url,
        blockscout_api_url: @fixture_api_url,
        blockscout_ws_url: nil,
        base_url: @base_url,
        clock_utc_now: @frozen_now
      })

    on_exit(restore)

    conn = get(build_conn(), "/tx/#{@success_hash}/og-image.svg")
    body = response(conn, 200)

    [content_type | _] = get_resp_header(conn, "content-type")
    assert String.starts_with?(content_type, "image/svg+xml")
    assert get_resp_header(conn, "cache-control") == ["public, max-age=300"]

    Golden.assert_golden!(@golden_og_svg_path, body)
  end

  defp put_env(kvs) when is_map(kvs) do
    prev =
      for {k, _v} <- kvs, into: %{} do
        {k, Application.get_env(:frontend_ex, k)}
      end

    Enum.each(kvs, fn
      {k, nil} -> Application.delete_env(:frontend_ex, k)
      {k, v} -> Application.put_env(:frontend_ex, k, v)
    end)

    fn ->
      Enum.each(prev, fn
        {k, nil} -> Application.delete_env(:frontend_ex, k)
        {k, v} -> Application.put_env(:frontend_ex, k, v)
      end)
    end
  end
end
