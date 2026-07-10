defmodule ExampleExNudgeWeb.PageControllerTest do
  use ExampleExNudgeWeb.ConnCase

  test "GET / renders the notification demo", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Push Notifications"
  end
end
