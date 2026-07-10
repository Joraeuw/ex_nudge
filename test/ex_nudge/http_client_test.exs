defmodule ExNudge.HTTPClient.HttpcTest do
  use ExUnit.Case, async: true

  alias ExNudge.HTTPClient.Httpc
  alias ExNudge.Response

  setup do
    %{bypass: Bypass.open()}
  end

  test "posts the body and headers and returns a normalized response", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/push", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert body == "payload"
      assert Plug.Conn.get_req_header(conn, "ttl") == ["60"]
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/octet-stream"]
      assert Plug.Conn.get_req_header(conn, "content-encoding") == ["aes128gcm"]

      conn
      |> Plug.Conn.put_resp_header("location", "https://push.example.com/d/123")
      |> Plug.Conn.resp(201, "created")
    end)

    assert {:ok, %Response{status: 201, body: "created", headers: headers}} =
             Httpc.post("http://localhost:#{bypass.port}/push", "payload", [
               {"Content-Type", "application/octet-stream"},
               {"Content-Encoding", "aes128gcm"},
               {"TTL", "60"}
             ])

    assert {"location", "https://push.example.com/d/123"} in headers
  end

  test "returns the raw response for non-2xx statuses", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/push", fn conn ->
      Plug.Conn.resp(conn, 410, "gone")
    end)

    assert {:ok, %Response{status: 410, body: "gone"}} =
             Httpc.post("http://localhost:#{bypass.port}/push", "payload", [])
  end

  test "returns an error tuple when the connection fails", %{bypass: bypass} do
    Bypass.down(bypass)

    assert {:error, _reason} =
             Httpc.post("http://localhost:#{bypass.port}/push", "payload", [])
  end

  test "implements the ExNudge.HTTPClient behaviour" do
    behaviours =
      :attributes
      |> Httpc.module_info()
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    assert ExNudge.HTTPClient in behaviours
  end
end
