defmodule ExNudge.EndToEndTest do
  # Uses the application config for VAPID values, so it cannot run async.
  use ExUnit.Case, async: false

  alias ExNudge.Response

  setup do
    original = Application.get_all_env(:ex_nudge)

    on_exit(fn ->
      Enum.each([:vapid_subject, :vapid_public_key, :vapid_private_key], fn key ->
        case Keyword.fetch(original, key) do
          {:ok, value} -> Application.put_env(:ex_nudge, key, value)
          :error -> Application.delete_env(:ex_nudge, key)
        end
      end)
    end)

    %{bypass: Bypass.open()}
  end

  test "sends a notification end-to-end using the application config", %{bypass: bypass} do
    vapid_keys = ExNudge.generate_vapid_keys()

    assert is_binary(vapid_keys.public_key)
    assert is_binary(vapid_keys.private_key)
    assert String.length(vapid_keys.public_key) > 80

    Application.put_env(:ex_nudge, :vapid_subject, "mailto:test@example.com")
    Application.put_env(:ex_nudge, :vapid_public_key, vapid_keys.public_key)
    Application.put_env(:ex_nudge, :vapid_private_key, vapid_keys.private_key)

    browser_subscription_json = %{
      "endpoint" => "http://localhost:#{bypass.port}/fcm/send/ABC123-test-endpoint",
      "keys" => %{
        "p256dh" =>
          "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4",
        "auth" => "BTBZMqHH6r4Tts7J_aSIgg"
      }
    }

    {:ok, subscription} = ExNudge.Subscription.from_map(browser_subscription_json)
    assert ExNudge.Subscription.valid?(subscription)

    Bypass.expect_once(bypass, "POST", "/fcm/send/ABC123-test-endpoint", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert Plug.Conn.get_req_header(conn, "content-encoding") == ["aes128gcm"]
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/octet-stream"]
      assert Plug.Conn.get_req_header(conn, "ttl") == ["300"]
      assert Plug.Conn.get_req_header(conn, "urgency") == ["high"]
      assert Plug.Conn.get_req_header(conn, "topic") == ["test_notification"]

      [authorization] = Plug.Conn.get_req_header(conn, "authorization")
      assert String.starts_with?(authorization, "vapid t=")
      assert String.contains?(authorization, ",k=#{vapid_keys.public_key}")

      assert <<salt::binary-size(16), record_size::unsigned-big-integer-size(32),
               key_length::unsigned-big-integer-size(8), _public_key::binary-size(65),
               _encrypted_content::binary>> = body

      assert byte_size(salt) == 16
      assert record_size > 0
      assert key_length == 65

      conn
      |> Plug.Conn.put_resp_header("location", "http://localhost/d/ABC123")
      |> Plug.Conn.resp(201, "")
    end)

    result =
      ExNudge.send_notification(subscription, "Hello World!",
        ttl: 300,
        urgency: :high,
        topic: "test_notification"
      )

    assert {:ok, %Response{status: 201}} = result
  end
end
