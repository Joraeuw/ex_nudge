defmodule ExNudge.EncryptionTest do
  use ExUnit.Case, async: true

  alias ExNudge.Encryption

  setup do
    {public_key, _private_key} = :crypto.generate_key(:ecdh, :prime256v1)
    auth_secret = :crypto.strong_rand_bytes(16)

    valid_keys = %{
      p256dh: Base.url_encode64(public_key, padding: false),
      auth: Base.url_encode64(auth_secret, padding: false)
    }

    %{valid_keys: valid_keys}
  end

  describe "encrypt/2" do
    test "successfully encrypts a simple message", %{valid_keys: valid_keys} do
      message = "Hello, World!"

      assert {:ok, encrypted} = Encryption.encrypt(message, valid_keys)

      assert is_binary(encrypted.ciphertext)
      assert is_binary(encrypted.salt)
      assert is_binary(encrypted.as_public_key)

      assert byte_size(encrypted.salt) == 16

      assert byte_size(encrypted.as_public_key) == 65
      assert binary_part(encrypted.as_public_key, 0, 1) == <<4>>

      # Header: salt(16) + rs(4) + pubkey_len(1) + pubkey(65) = 86 bytes minimum
      assert byte_size(encrypted.ciphertext) >= 86
    end

    test "encrypts empty message", %{valid_keys: valid_keys} do
      message = ""

      assert {:ok, encrypted} = Encryption.encrypt(message, valid_keys)
      assert is_binary(encrypted.ciphertext)

      # header + delimiter + tag
      assert byte_size(encrypted.ciphertext) >= 86 + 1 + 16
    end

    test "produces different ciphertext for same message (randomness)", %{valid_keys: valid_keys} do
      message = "Same message"

      {:ok, encrypted1} = Encryption.encrypt(message, valid_keys)
      {:ok, encrypted2} = Encryption.encrypt(message, valid_keys)

      assert encrypted1.ciphertext != encrypted2.ciphertext
      assert encrypted1.salt != encrypted2.salt
      assert encrypted1.as_public_key != encrypted2.as_public_key
    end

    test "verifies aes128gcm header format compliance", %{valid_keys: valid_keys} do
      message = "Test RFC 8188 compliance"

      {:ok, encrypted} = Encryption.encrypt(message, valid_keys)

      <<salt::binary-size(16), record_size::unsigned-big-integer-size(32),
        key_length::unsigned-big-integer-size(8), public_key::binary-size(65),
        encrypted_data::binary>> = encrypted.ciphertext

      assert byte_size(salt) == 16
      assert record_size > 0

      assert record_size <= 4096
      assert key_length == 65

      assert binary_part(public_key, 0, 1) == <<4>>

      assert byte_size(encrypted_data) >= 16

      expected_min_size = byte_size(message) + 1 + 16
      assert record_size >= expected_min_size
    end

    test "handles Unicode messages correctly", %{valid_keys: valid_keys} do
      message = "Hello 🌍! Ελληνικά 中文"

      assert {:ok, encrypted} = Encryption.encrypt(message, valid_keys)
      assert is_binary(encrypted.ciphertext)

      assert byte_size(encrypted.ciphertext) > byte_size(message)
    end

    test "returns error for invalid p256dh key", %{valid_keys: valid_keys} do
      invalid_keys = %{
        p256dh: "invalid-base64!",
        auth: valid_keys.auth
      }

      assert {:error, :invalid_base64} = Encryption.encrypt("test", invalid_keys)
    end

    test "returns error for invalid auth secret", %{valid_keys: valid_keys} do
      invalid_keys = %{
        p256dh: valid_keys.p256dh,
        auth: "invalid-base64!"
      }

      assert {:error, :invalid_base64} = Encryption.encrypt("test", invalid_keys)
    end

    test "returns error for malformed p256dh key (wrong length)", %{valid_keys: valid_keys} do
      invalid_keys = %{
        p256dh: "dGVzdA",
        auth: valid_keys.auth
      }

      result = Encryption.encrypt("test", invalid_keys)
      assert {:error, {:invalid_ecdh_key, _reason}} = result
    end
  end

  describe "edge cases and security" do
    test "different salt for each encryption", %{valid_keys: valid_keys} do
      message = "Salt uniqueness test"

      salts =
        for _ <- 1..10 do
          {:ok, encrypted} = Encryption.encrypt(message, valid_keys)
          encrypted.salt
        end

      unique_salts = Enum.uniq(salts)
      assert length(unique_salts) == 10
    end

    test "different ephemeral keys for each encryption", %{valid_keys: valid_keys} do
      message = "Key uniqueness test"

      public_keys =
        for _ <- 1..10 do
          {:ok, encrypted} = Encryption.encrypt(message, valid_keys)
          encrypted.as_public_key
        end

      unique_keys = Enum.uniq(public_keys)
      assert length(unique_keys) == 10
    end

    test "handles concurrent encryptions safely", %{valid_keys: valid_keys} do
      message = "Concurrency test"

      tasks =
        for _ <- 1..20 do
          Task.async(fn -> Encryption.encrypt(message, valid_keys) end)
        end

      results = Task.await_many(tasks, 5000)

      assert Enum.all?(results, &match?({:ok, _}, &1))

      ciphertexts = Enum.map(results, fn {:ok, encrypted} -> encrypted.ciphertext end)
      unique_ciphertexts = Enum.uniq(ciphertexts)
      assert length(unique_ciphertexts) == 20
    end
  end
end
