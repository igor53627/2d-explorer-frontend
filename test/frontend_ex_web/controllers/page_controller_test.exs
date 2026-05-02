defmodule FrontendExWeb.HomeControllerTest do
  use FrontendExWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Sepolia Testnet Explorer"
  end
end
