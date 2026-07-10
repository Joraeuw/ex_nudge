defmodule ExNudge.ErrorTest do
  use ExUnit.Case, async: true

  alias ExNudge.Error

  describe "new/2" do
    test "builds an exception struct with a stable reason atom" do
      error = Error.new(:subscription_expired, status: 410)

      assert %Error{reason: :subscription_expired, status: 410} = error
      assert Exception.exception?(error)
    end

    test "carries the push service response when given" do
      response = %ExNudge.Response{status: 410, headers: [], body: "gone"}
      error = Error.new(:subscription_expired, status: 410, response: response)

      assert error.response == response
    end

    test "carries arbitrary context" do
      error = Error.new(:request_failed, context: :timeout)

      assert error.context == :timeout
    end
  end

  describe "message/1" do
    test "builds human-readable messages per reason" do
      assert Exception.message(Error.new(:subscription_expired)) =~ "expired"
      assert Exception.message(Error.new(:payload_too_large)) =~ "payload"
      assert Exception.message(Error.new(:missing_vapid_keys)) =~ "VAPID"
      assert Exception.message(Error.new(:missing_vapid_subject)) =~ "vapid_subject"
      assert Exception.message(Error.new(:invalid_subscription)) =~ "subscription"
      assert Exception.message(Error.new(:invalid_subscription_keys)) =~ "keys"
      assert Exception.message(Error.new(:http_error, status: 500)) =~ "500"
      assert Exception.message(Error.new(:request_failed, context: :timeout)) =~ "timeout"
    end

    test "falls back to the reason for unrecognized reasons" do
      assert Exception.message(Error.new(:something_odd)) =~ "something_odd"
    end
  end

  describe "raising" do
    test "can be raised like any exception" do
      assert_raise Error, ~r/expired/, fn ->
        raise Error.new(:subscription_expired)
      end
    end
  end

  describe "normalize/1" do
    test "passes an existing error through untouched" do
      error = Error.new(:http_error, status: 502)
      assert Error.normalize(error) == error
    end

    test "wraps bare reason atoms" do
      assert %Error{reason: :missing_vapid_keys} = Error.normalize(:missing_vapid_keys)
    end

    test "maps key decoding failures to :invalid_subscription_keys" do
      assert %Error{reason: :invalid_subscription_keys, context: :invalid_base64} =
               Error.normalize(:invalid_base64)

      assert %Error{reason: :invalid_subscription_keys} =
               Error.normalize({:invalid_ecdh_key, :some_detail})

      assert %Error{reason: :invalid_subscription_keys} =
               Error.normalize({:ecdh_failed, :some_detail})
    end

    test "maps AES failures to :encryption_failed" do
      assert %Error{reason: :encryption_failed} =
               Error.normalize({:aes_encryption_failed, :bad})
    end
  end
end
