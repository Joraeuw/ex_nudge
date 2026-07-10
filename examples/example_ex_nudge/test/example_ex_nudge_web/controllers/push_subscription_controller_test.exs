defmodule ExampleExNudgeWeb.PushSubscriptionControllerTest do
  use ExampleExNudgeWeb.ConnCase

  alias ExampleExNudge.Models.PushSubscription
  alias ExampleExNudge.Repo
  alias ExampleExNudgeWeb.PushToken

  @old_endpoint "https://push.example.com/old"
  @new_endpoint "https://push.example.com/new"

  @new_subscription %{
    "endpoint" => @new_endpoint,
    "keys" => %{"p256dh" => "new_p256dh", "auth" => "new_auth"}
  }

  defp insert_subscription(endpoint) do
    Repo.insert!(%PushSubscription{endpoint: endpoint, p256dh_key: "key", auth_key: "auth"})
  end

  test "replaces the old subscription and returns a token for the new endpoint", %{conn: conn} do
    insert_subscription(@old_endpoint)
    token = PushToken.sign(@old_endpoint)

    conn =
      post(conn, ~p"/api/push_subscriptions/refresh", %{
        token: token,
        subscription: @new_subscription
      })

    assert %{"token" => new_token} = json_response(conn, 200)
    assert {:ok, @new_endpoint} = PushToken.verify(new_token)

    refute Repo.get_by(PushSubscription, endpoint: @old_endpoint)
    assert Repo.get_by(PushSubscription, endpoint: @new_endpoint)
  end

  test "still stores the new subscription when the old endpoint is already gone", %{conn: conn} do
    token = PushToken.sign(@old_endpoint)

    conn =
      post(conn, ~p"/api/push_subscriptions/refresh", %{
        token: token,
        subscription: @new_subscription
      })

    assert %{"token" => _} = json_response(conn, 200)
    assert Repo.get_by(PushSubscription, endpoint: @new_endpoint)
  end

  test "rejects an invalid token", %{conn: conn} do
    conn =
      post(conn, ~p"/api/push_subscriptions/refresh", %{
        token: "garbage",
        subscription: @new_subscription
      })

    assert json_response(conn, 401)["error"] == "invalid token"
    refute Repo.get_by(PushSubscription, endpoint: @new_endpoint)
  end

  test "rejects malformed subscription data", %{conn: conn} do
    insert_subscription(@old_endpoint)
    token = PushToken.sign(@old_endpoint)

    conn =
      post(conn, ~p"/api/push_subscriptions/refresh", %{
        token: token,
        subscription: %{"not" => "a subscription"}
      })

    assert json_response(conn, 422)["error"] == "invalid subscription"
    # The transaction must roll back the deletion of the old subscription.
    assert Repo.get_by(PushSubscription, endpoint: @old_endpoint)
  end

  test "rejects requests missing token or subscription", %{conn: conn} do
    conn = post(conn, ~p"/api/push_subscriptions/refresh", %{})

    assert json_response(conn, 400)["error"] == "token and subscription are required"
  end
end
