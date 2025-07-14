defmodule ExampleExNudgeWeb.ErrorJSONTest do
  use ExampleExNudgeWeb.ConnCase, async: true

  test "renders 404" do
    assert ExampleExNudgeWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert ExampleExNudgeWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
