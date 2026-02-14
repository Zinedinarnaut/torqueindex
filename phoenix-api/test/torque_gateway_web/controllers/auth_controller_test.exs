defmodule TorqueGatewayWeb.AuthControllerTest do
  use TorqueGatewayWeb.ConnCase, async: false

  test "signup then signin returns tokens + profile", %{conn: conn} do
    params = %{
      "email" => "zinedin@example.com",
      "username" => "zinedin",
      "password" => "password123"
    }

    conn = post(conn, "/api/auth/signup", params)
    assert conn.status == 200

    %{
      "access_token" => access_token,
      "refresh_token" => refresh_token,
      "profile" => %{"id" => user_id, "email" => "zinedin@example.com", "username" => "zinedin"}
    } = json_response(conn, 200)

    assert is_binary(access_token) and byte_size(access_token) > 20
    assert is_binary(refresh_token) and byte_size(refresh_token) > 20
    assert is_binary(user_id) and byte_size(user_id) > 10

    conn2 = Phoenix.ConnTest.build_conn()
    conn2 = post(conn2, "/api/auth/signin", %{"email" => "zinedin@example.com", "password" => "password123"})
    assert conn2.status == 200

    %{"profile" => %{"id" => ^user_id}} = json_response(conn2, 200)
  end
end

