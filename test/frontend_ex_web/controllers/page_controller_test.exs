defmodule FrontendExWeb.HomeControllerTest do
  use FrontendExWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "2D Explorer"
  end

  describe "home block tile metadata flag (FF_HOME_BLOCK_META_FULL)" do
    setup do
      original = Application.get_env(:frontend_ex, :home, [])
      on_exit(fn -> Application.put_env(:frontend_ex, :home, original) end)
      :ok
    end

    test "hides Proposer and Fees rows by default", %{conn: conn} do
      Application.put_env(:frontend_ex, :home, block_meta_full: false)
      html = conn |> get(~p"/") |> html_response(200)
      refute html =~ ~s(<div class="block-miner">)
      refute html =~ ~s(<div class="block-reward">)
    end

    test "shows Proposer and Fees rows when flag is true", %{conn: conn} do
      Application.put_env(:frontend_ex, :home, block_meta_full: true)
      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ ~s(<div class="block-miner">)
      assert html =~ ~s(<div class="block-reward">)
      assert html =~ "Proposer"
      assert html =~ ~r/Fees 0 [A-Z]+/
    end
  end
end
