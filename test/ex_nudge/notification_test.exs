defmodule ExNudge.NotificationTest do
  use ExUnit.Case, async: true

  alias ExNudge.Notification
  alias ExNudge.Subscription

  describe "new/2" do
    test "builds a notification with a title and optional fields" do
      notification =
        Notification.new("Order shipped",
          body: "Your package is on the way",
          icon: "/images/icon.png",
          tag: "orders",
          require_interaction: true,
          data: %{url: "/orders/42"}
        )

      assert %Notification{
               title: "Order shipped",
               body: "Your package is on the way",
               icon: "/images/icon.png",
               tag: "orders",
               require_interaction: true,
               data: %{url: "/orders/42"}
             } = notification
    end

    test "title is mandatory on the struct" do
      assert_raise ArgumentError, fn -> struct!(Notification, body: "no title") end
    end
  end

  describe "to_map/1" do
    test "uses the camelCase keys expected by showNotification and drops nils" do
      map =
        "Hi"
        |> Notification.new(require_interaction: true, badge: "/badge.png")
        |> Notification.to_map()

      assert map == %{
               "title" => "Hi",
               "requireInteraction" => true,
               "badge" => "/badge.png"
             }
    end

    test "keeps actions as given" do
      map =
        "Hi"
        |> Notification.new(actions: [%{action: "open", title: "Open", icon: "/open.png"}])
        |> Notification.to_map()

      assert map["actions"] == [%{action: "open", title: "Open", icon: "/open.png"}]
    end

    test "empty actions list is omitted" do
      map = "Hi" |> Notification.new() |> Notification.to_map()

      refute Map.has_key?(map, "actions")
    end
  end

  describe "JSON encoding" do
    test "encodes via Jason with camelCase keys" do
      json =
        "Hi"
        |> Notification.new(body: "there", silent: false, vibrate: [200, 100, 200])
        |> Jason.encode!()

      assert Jason.decode!(json) == %{
               "title" => "Hi",
               "body" => "there",
               "silent" => false,
               "vibrate" => [200, 100, 200]
             }
    end
  end

  describe "sending a notification struct" do
    test "send_notification/3 JSON-encodes a Notification payload" do
      bypass = Bypass.open()
      keys = ExNudge.generate_vapid_keys()

      vapid = [
        subject: "mailto:test@example.com",
        public_key: keys.public_key,
        private_key: keys.private_key
      ]

      subscription = %Subscription{
        endpoint: "http://localhost:#{bypass.port}/push/abc",
        keys: %{
          p256dh:
            "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4",
          auth: "BTBZMqHH6r4Tts7J_aSIgg"
        }
      }

      Bypass.expect_once(bypass, "POST", "/push/abc", fn conn ->
        Plug.Conn.resp(conn, 201, "")
      end)

      notification = Notification.new("Hello", body: "World")

      assert {:ok, %ExNudge.Response{status: 201}} =
               ExNudge.send_notification(subscription, notification, vapid: vapid)
    end
  end
end
