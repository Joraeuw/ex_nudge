defmodule ExNudge.SubscriptionTest do
  use ExUnit.Case, async: true

  alias ExNudge.Subscription

  describe "from_map/1" do
    test "creates subscription from valid map" do
      data = %{
        "endpoint" => "https://fcm.googleapis.com/fcm/send/test123",
        "keys" => %{
          "p256dh" => "BK8nBpIE2tsGVt8_test_key_here",
          "auth" => "auth_test_secret_here"
        }
      }

      assert {:ok, %Subscription{} = subscription} = Subscription.from_map(data)
      assert subscription.endpoint == data["endpoint"]
      assert subscription.keys.p256dh == data["keys"]["p256dh"]
      assert subscription.keys.auth == data["keys"]["auth"]
    end

    test "returns error for invalid map" do
      assert {:error, :invalid_subscription} = Subscription.from_map(%{})
      assert {:error, :invalid_subscription} = Subscription.from_map(%{"endpoint" => "test"})
    end
  end

  describe "valid?/1" do
    test "validates correct subscription" do
      subscription = %Subscription{
        endpoint: "https://fcm.googleapis.com/fcm/send/test123",
        keys: %{
          p256dh: "BK8nBpIE2tsGVt8",
          auth: "dGVzdF9hdXRo"
        }
      }

      assert Subscription.valid?(subscription)
    end

    test "invalidates malformed subscription" do
      subscription = %Subscription{
        endpoint: "invalid-url",
        keys: %{
          p256dh: "invalid-base64!",
          auth: "also-invalid!"
        }
      }

      refute Subscription.valid?(subscription)
    end

    test "invalidates malformed subscription when endpoint is invalid type" do
      subscription = %Subscription{
        endpoint: :invalid_url!,
        keys: %{
          p256dh: "invalid-base64!",
          auth: "also-invalid!"
        }
      }

      refute Subscription.valid?(subscription)
    end
  end

  test "invalidates malformed subscription when key is invalid type" do
    subscription = %Subscription{
      endpoint: "https://fcm.googleapis.com/fcm/send/test123",
      keys: %{
        p256dh: :invalid_base64!,
        auth: "also-invalid!"
      }
    }

    refute Subscription.valid?(subscription)
  end
end
