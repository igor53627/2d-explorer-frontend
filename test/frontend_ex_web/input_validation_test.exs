defmodule FrontendExWeb.InputValidationTest do
  use FrontendExWeb.ConnCase, async: true

  describe "AddressController input validation" do
    test "returns 404 for invalid address format", %{conn: conn} do
      conn = get(conn, "/address/not-a-valid-address")
      assert response(conn, 404) =~ "Address not found"
    end

    test "returns 404 for short hex", %{conn: conn} do
      conn = get(conn, "/address/0xdead")
      assert response(conn, 404) =~ "Address not found"
    end

    test "returns 404 for address with extra chars", %{conn: conn} do
      conn = get(conn, "/address/0x" <> String.duplicate("a", 40) <> "xx")
      assert response(conn, 404) =~ "Address not found"
    end
  end

  # 2d-fork: TokenController removed (no ERC-20 surface in 2d).

  describe "BlockController input validation" do
    test "returns 404 for non-numeric non-hash block id", %{conn: conn} do
      conn = get(conn, "/block/abc-not-valid")
      assert response(conn, 404) =~ "Block not found"
    end

    test "returns 404 for invalid block id in txs", %{conn: conn} do
      conn = get(conn, "/block/abc-not-valid/txs")
      assert response(conn, 404) =~ "Block not found"
    end
  end
end
