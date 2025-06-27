defmodule ExNudge.VapidTest do
  use ExUnit.Case, async: true

  describe "generate_vapid_keys/0" do
    test "generates valid VAPID key pair" do
      keys = ExNudge.generate_vapid_keys()

      assert is_binary(keys.public_key)
      assert is_binary(keys.private_key)
      assert String.length(keys.public_key) > 0
      assert String.length(keys.private_key) > 0

      assert {:ok, _} = Base.url_decode64(keys.public_key, padding: false)
      assert {:ok, _} = Base.url_decode64(keys.private_key, padding: false)
    end
  end
end
