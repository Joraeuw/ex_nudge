defmodule ExNudgeTest do
  # Several tests manipulate the :ex_nudge application environment.
  use ExUnit.Case, async: false

  alias ExNudge.Error
  alias ExNudge.Response
  alias ExNudge.Subscription

  @p256dh "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4"
  @auth "BTBZMqHH6r4Tts7J_aSIgg"

  # RFC 8291/8188: 4096 bytes total - 86 header - 16 auth tag - 1 padding delimiter
  @max_payload_size 3993

  setup do
    bypass = Bypass.open()
    keys = ExNudge.generate_vapid_keys()

    vapid = [
      subject: "mailto:test@example.com",
      public_key: keys.public_key,
      private_key: keys.private_key
    ]

    subscription = %Subscription{
      endpoint: "http://localhost:#{bypass.port}/push/abc123",
      keys: %{p256dh: @p256dh, auth: @auth}
    }

    %{bypass: bypass, vapid: vapid, subscription: subscription}
  end

  describe "send_notification/3 success" do
    test "delivers an encrypted payload and returns a normalized response", ctx do
      Bypass.expect_once(ctx.bypass, "POST", "/push/abc123", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert Plug.Conn.get_req_header(conn, "content-encoding") == ["aes128gcm"]
        assert Plug.Conn.get_req_header(conn, "content-type") == ["application/octet-stream"]
        assert Plug.Conn.get_req_header(conn, "ttl") == ["60"]

        assert <<_salt::binary-size(16), _record_size::unsigned-big-integer-size(32),
                 65::unsigned-big-integer-size(8), _as_public_key::binary-size(65),
                 _encrypted::binary>> = body

        conn
        |> Plug.Conn.put_resp_header("location", "http://push.example.com/d/1")
        |> Plug.Conn.resp(201, "")
      end)

      assert {:ok, %Response{status: 201, headers: headers}} =
               ExNudge.send_notification(ctx.subscription, "hello", vapid: ctx.vapid)

      assert {"location", "http://push.example.com/d/1"} in headers
    end

    test "sets TTL, Urgency and Topic headers from options", ctx do
      Bypass.expect_once(ctx.bypass, "POST", "/push/abc123", fn conn ->
        assert Plug.Conn.get_req_header(conn, "ttl") == ["300"]
        assert Plug.Conn.get_req_header(conn, "urgency") == ["high"]
        assert Plug.Conn.get_req_header(conn, "topic") == ["news"]
        Plug.Conn.resp(conn, 201, "")
      end)

      assert {:ok, %Response{status: 201}} =
               ExNudge.send_notification(ctx.subscription, "hello",
                 vapid: ctx.vapid,
                 ttl: 300,
                 urgency: :high,
                 topic: "news"
               )
    end

    test "signs a VAPID JWT whose aud includes the endpoint's non-default port", ctx do
      test_pid = self()

      Bypass.expect_once(ctx.bypass, "POST", "/push/abc123", fn conn ->
        [authorization] = Plug.Conn.get_req_header(conn, "authorization")
        send(test_pid, {:authorization, authorization})
        Plug.Conn.resp(conn, 201, "")
      end)

      assert {:ok, _} = ExNudge.send_notification(ctx.subscription, "hello", vapid: ctx.vapid)

      assert_receive {:authorization, authorization}
      assert [_, jwt, k] = Regex.run(~r/^vapid t=([^,]+),k=(.+)$/, authorization)
      assert k == Keyword.fetch!(ctx.vapid, :public_key)

      [_header, payload, _signature] = String.split(jwt, ".")
      claims = payload |> Base.url_decode64!(padding: false) |> Jason.decode!()

      assert claims["aud"] == "http://localhost:#{ctx.bypass.port}"
      assert claims["sub"] == "mailto:test@example.com"
      assert claims["exp"] > System.os_time(:second)
    end

    test "accepts a payload of exactly the RFC 8291 maximum size", ctx do
      Bypass.expect_once(ctx.bypass, "POST", "/push/abc123", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert byte_size(body) == 4096
        Plug.Conn.resp(conn, 201, "")
      end)

      payload = String.duplicate("a", @max_payload_size)

      assert {:ok, %Response{status: 201}} =
               ExNudge.send_notification(ctx.subscription, payload, vapid: ctx.vapid)
    end
  end

  describe "send_notification/3 push service errors" do
    test "maps 410 to :subscription_expired", ctx do
      Bypass.expect_once(ctx.bypass, "POST", "/push/abc123", fn conn ->
        Plug.Conn.resp(conn, 410, "gone")
      end)

      assert {:error, %Error{reason: :subscription_expired, status: 410}} =
               ExNudge.send_notification(ctx.subscription, "hello", vapid: ctx.vapid)
    end

    test "maps 404 to :subscription_expired", ctx do
      Bypass.expect_once(ctx.bypass, "POST", "/push/abc123", fn conn ->
        Plug.Conn.resp(conn, 404, "not found")
      end)

      assert {:error, %Error{reason: :subscription_expired, status: 404}} =
               ExNudge.send_notification(ctx.subscription, "hello", vapid: ctx.vapid)
    end

    test "maps 413 to :payload_too_large", ctx do
      Bypass.expect_once(ctx.bypass, "POST", "/push/abc123", fn conn ->
        Plug.Conn.resp(conn, 413, "too large")
      end)

      assert {:error, %Error{reason: :payload_too_large, status: 413}} =
               ExNudge.send_notification(ctx.subscription, "hello", vapid: ctx.vapid)
    end

    test "maps any other status to :http_error with the response attached", ctx do
      Bypass.expect_once(ctx.bypass, "POST", "/push/abc123", fn conn ->
        Plug.Conn.resp(conn, 500, "boom")
      end)

      assert {:error, %Error{reason: :http_error, status: 500, response: response}} =
               ExNudge.send_notification(ctx.subscription, "hello", vapid: ctx.vapid)

      assert %Response{status: 500, body: "boom"} = response
    end

    test "maps network failures to :request_failed", ctx do
      Bypass.down(ctx.bypass)

      assert {:error, %Error{reason: :request_failed, context: context}} =
               ExNudge.send_notification(ctx.subscription, "hello", vapid: ctx.vapid)

      assert context != nil
    end
  end

  describe "send_notification/3 local validation" do
    test "rejects oversized payloads without contacting the push service", ctx do
      payload = String.duplicate("a", @max_payload_size + 1)

      assert {:error, %Error{reason: :payload_too_large, status: nil}} =
               ExNudge.send_notification(ctx.subscription, payload, vapid: ctx.vapid)
    end

    test "rejects undecodable subscription keys", ctx do
      subscription = %Subscription{
        endpoint: ctx.subscription.endpoint,
        keys: %{p256dh: "not-base64!", auth: "also-not!"}
      }

      assert {:error, %Error{reason: :invalid_subscription_keys}} =
               ExNudge.send_notification(subscription, "hello", vapid: ctx.vapid)
    end
  end

  describe "send_notification/3 VAPID configuration" do
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

      :ok
    end

    test "returns :missing_vapid_keys when no keys are configured or passed", ctx do
      Application.delete_env(:ex_nudge, :vapid_public_key)
      Application.delete_env(:ex_nudge, :vapid_private_key)

      assert {:error, %Error{reason: :missing_vapid_keys}} =
               ExNudge.send_notification(ctx.subscription, "hello")
    end

    test "returns :missing_vapid_subject when no subject is configured or passed", ctx do
      Application.delete_env(:ex_nudge, :vapid_subject)

      assert {:error, %Error{reason: :missing_vapid_subject}} =
               ExNudge.send_notification(ctx.subscription, "hello",
                 vapid: [
                   public_key: Keyword.fetch!(ctx.vapid, :public_key),
                   private_key: Keyword.fetch!(ctx.vapid, :private_key)
                 ]
               )
    end

    test "returns :invalid_vapid_keys when keys are not valid base64url", ctx do
      assert {:error, %Error{reason: :invalid_vapid_keys}} =
               ExNudge.send_notification(ctx.subscription, "hello",
                 vapid: Keyword.put(ctx.vapid, :public_key, "!!!not-base64!!!")
               )
    end

    test "per-call vapid values take precedence over the application config", ctx do
      Application.put_env(:ex_nudge, :vapid_subject, "mailto:config@example.com")

      test_pid = self()

      Bypass.expect_once(ctx.bypass, "POST", "/push/abc123", fn conn ->
        [authorization] = Plug.Conn.get_req_header(conn, "authorization")
        send(test_pid, {:authorization, authorization})
        Plug.Conn.resp(conn, 201, "")
      end)

      assert {:ok, _} =
               ExNudge.send_notification(ctx.subscription, "hello",
                 vapid: Keyword.put(ctx.vapid, :subject, "mailto:override@example.com")
               )

      assert_receive {:authorization, authorization}
      [_, jwt, _k] = Regex.run(~r/^vapid t=([^,]+),k=(.+)$/, authorization)
      [_header, payload, _signature] = String.split(jwt, ".")
      claims = payload |> Base.url_decode64!(padding: false) |> Jason.decode!()

      assert claims["sub"] == "mailto:override@example.com"
    end

    test "partial per-call vapid values fall back to the application config", ctx do
      Application.put_env(:ex_nudge, :vapid_subject, "mailto:config@example.com")

      test_pid = self()

      Bypass.expect_once(ctx.bypass, "POST", "/push/abc123", fn conn ->
        [authorization] = Plug.Conn.get_req_header(conn, "authorization")
        send(test_pid, {:authorization, authorization})
        Plug.Conn.resp(conn, 201, "")
      end)

      assert {:ok, _} =
               ExNudge.send_notification(ctx.subscription, "hello",
                 vapid: Keyword.delete(ctx.vapid, :subject)
               )

      assert_receive {:authorization, authorization}
      [_, jwt, _k] = Regex.run(~r/^vapid t=([^,]+),k=(.+)$/, authorization)
      [_header, payload, _signature] = String.split(jwt, ".")
      claims = payload |> Base.url_decode64!(padding: false) |> Jason.decode!()

      assert claims["sub"] == "mailto:config@example.com"
    end
  end

  describe "telemetry" do
    setup do
      handler_id = "ex-nudge-test-#{System.unique_integer([:positive])}"
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:ex_nudge, :send_notification],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)
      :ok
    end

    test "emits a success event with the response status", ctx do
      Bypass.expect_once(ctx.bypass, "POST", "/push/abc123", fn conn ->
        Plug.Conn.resp(conn, 201, "")
      end)

      {:ok, _} = ExNudge.send_notification(ctx.subscription, "hello", vapid: ctx.vapid)

      assert_receive {:telemetry, measurements, metadata}
      assert measurements.payload_size == byte_size("hello")
      assert metadata.status == :success
      assert metadata.http_status_code == 201
      assert metadata.error_reason == nil
    end

    test "emits an error event with the error reason", ctx do
      Bypass.expect_once(ctx.bypass, "POST", "/push/abc123", fn conn ->
        Plug.Conn.resp(conn, 410, "gone")
      end)

      {:error, _} = ExNudge.send_notification(ctx.subscription, "hello", vapid: ctx.vapid)

      assert_receive {:telemetry, _measurements, metadata}
      assert metadata.status == :error
      assert metadata.http_status_code == 410
      assert metadata.error_reason == :subscription_expired
    end
  end

  describe "batch sending removal" do
    test "send_notifications/2,3 is no longer part of the API" do
      refute function_exported?(ExNudge, :send_notifications, 2)
      refute function_exported?(ExNudge, :send_notifications, 3)
    end
  end
end
