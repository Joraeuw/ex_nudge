defmodule ExNudge.EndToEndTest do
  use ExUnit.Case, async: false

  import Mimic

  describe "end-to-end" do
    test "end-to-end notification sending" do
      vapid_keys = ExNudge.generate_vapid_keys()

      assert is_binary(vapid_keys.public_key)
      assert is_binary(vapid_keys.private_key)

      assert String.length(vapid_keys.public_key) > 80

      Application.put_env(:ex_nudge, :vapid_subject, "mailto:test@example.com")
      Application.put_env(:ex_nudge, :vapid_public_key, vapid_keys.public_key)
      Application.put_env(:ex_nudge, :vapid_private_key, vapid_keys.private_key)

      browser_subscription_json = %{
        "endpoint" => "https://fcm.googleapis.com/fcm/send/ABC123-test-endpoint",
        "keys" => %{
          "p256dh" =>
            "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4",
          "auth" => "BTBZMqHH6r4Tts7J_aSIgg"
        }
      }

      {:ok, subscription} = ExNudge.Subscription.from_map(browser_subscription_json)
      assert ExNudge.Subscription.valid?(subscription)

      expect(HTTPoison, :post, fn url, body, headers ->
        assert url == subscription.endpoint

        headers_map = Enum.into(headers, %{})
        assert headers_map["Content-Encoding"] == "aes128gcm"
        assert headers_map["Content-Type"] == "application/octet-stream"
        assert String.starts_with?(headers_map["Authorization"], "vapid ")
        assert headers_map["TTL"] == "300"

        assert is_binary(body)

        <<salt::binary-size(16), record_size::unsigned-big-integer-size(32),
          key_length::unsigned-big-integer-size(8), _public_key::binary-size(65),
          _encrypted_content::binary>> = body

        assert byte_size(salt) == 16
        assert record_size > 0
        assert key_length == 65

        {:ok,
         %HTTPoison.Response{
           status_code: 201,
           headers: [{"Location", "https://fcm.googleapis.com/fcm/send/ABC123"}],
           body: ""
         }}
      end)

      message = "Hello World!"

      result =
        ExNudge.send_notification(subscription, message,
          ttl: 300,
          urgency: :high,
          topic: "test_notification"
        )

      assert {:ok, response} = result
      assert response.status_code == 201
    end

    test "batch notification sending" do
      vapid_keys = ExNudge.generate_vapid_keys()
      Application.put_env(:ex_nudge, :vapid_subject, "mailto:test@example.com")
      Application.put_env(:ex_nudge, :vapid_public_key, vapid_keys.public_key)
      Application.put_env(:ex_nudge, :vapid_private_key, vapid_keys.private_key)

      subscriptions = [
        %ExNudge.Subscription{
          endpoint: "https://fcm.googleapis.com/fcm/send/user1",
          keys: %{
            p256dh:
              "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4",
            auth: "BTBZMqHH6r4Tts7J_aSIgg"
          }
        },
        %ExNudge.Subscription{
          endpoint: "https://fcm.googleapis.com/fcm/send/user2",
          keys: %{
            p256dh:
              "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4",
            auth: "BTBZMqHH6r4Tts7J_aSIgg"
          }
        }
      ]

      expect(HTTPoison, :post, 2, fn _url, _body, _headers ->
        {:ok, %HTTPoison.Response{status_code: 201, body: ""}}
      end)

      results = ExNudge.send_notifications(subscriptions, "Batch notification!")

      assert length(results) == 2

      Enum.each(results, fn result ->
        assert {:ok, _, %HTTPoison.Response{status_code: 201}} = result
      end)
    end

    test "handles expired subscriptions correctly" do
      vapid_keys = ExNudge.generate_vapid_keys()
      Application.put_env(:ex_nudge, :vapid_subject, "mailto:test@example.com")
      Application.put_env(:ex_nudge, :vapid_public_key, vapid_keys.public_key)
      Application.put_env(:ex_nudge, :vapid_private_key, vapid_keys.private_key)

      subscription = %ExNudge.Subscription{
        endpoint: "https://fcm.googleapis.com/fcm/send/expired",
        keys: %{
          p256dh:
            "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4",
          auth: "BTBZMqHH6r4Tts7J_aSIgg"
        }
      }

      expect(HTTPoison, :post, fn _url, _body, _headers ->
        {:ok,
         %HTTPoison.Response{
           status_code: 410,
           body: "subscription expired"
         }}
      end)

      result = ExNudge.send_notification(subscription, "Test message")

      assert {:error, :subscription_expired} = result
    end

    test "handles large payload errors correctly" do
      vapid_keys = ExNudge.generate_vapid_keys()
      Application.put_env(:ex_nudge, :vapid_subject, "mailto:test@example.com")
      Application.put_env(:ex_nudge, :vapid_public_key, vapid_keys.public_key)
      Application.put_env(:ex_nudge, :vapid_private_key, vapid_keys.private_key)

      subscription = %ExNudge.Subscription{
        endpoint: "https://fcm.googleapis.com/fcm/send/expired",
        keys: %{
          p256dh:
            "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4",
          auth: "BTBZMqHH6r4Tts7J_aSIgg"
        }
      }

      expect(HTTPoison, :post, fn _url, _body, _headers ->
        {:ok,
         %HTTPoison.Response{
           status_code: 413,
           body: "Payload too large"
         }}
      end)

      result = ExNudge.send_notification(subscription, String.duplicate("A", 10_000))

      assert {:error, :payload_too_large} = result
    end
  end
end
