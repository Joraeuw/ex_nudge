defmodule ExNudge.UtilsTest do
  use ExUnit.Case, async: true

  alias ExNudge.Utils

  describe "url_encode/1" do
    test "encodes binary data to base64url" do
      data = "hello world"
      encoded = Utils.url_encode(data)

      assert is_binary(encoded)
      assert {:ok, ^data} = Base.url_decode64(encoded, padding: false)
    end
  end

  describe "safe_url_decode/1" do
    test "decodes valid base64url strings" do
      data = "hello world"
      encoded = Base.url_encode64(data, padding: false)

      assert {:ok, ^data} = Utils.safe_url_decode(encoded)
    end

    test "returns error for invalid base64url" do
      assert {:error, :invalid_base64} = Utils.safe_url_decode("invalid-base64!")
    end

    test "returns error for non-string input" do
      assert {:error, :invalid_input} = Utils.safe_url_decode(123)
      assert {:error, :invalid_input} = Utils.safe_url_decode(nil)
    end
  end
end
