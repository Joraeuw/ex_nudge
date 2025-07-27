defmodule ExNudge.Encryption do
  @moduledoc """
  Handles payload encryption according to RFC 8291 and RFC 8292.
  """

  alias ExNudge.Utils

  @salt_length 16
  @key_length 32
  @content_encryption_key_length 16
  @nonce_length 12
  @prime256v1_curve :prime256v1
  @record_size 4096
  @public_key_length 65

  @type encrypted_payload :: %{
          ciphertext: binary(),
          salt: binary(),
          as_public_key: binary()
        }

  @spec encrypt(String.t(), map()) :: {:ok, encrypted_payload()} | {:error, atom()}
  def encrypt(message, %{p256dh: p256dh, auth: auth}) do
    with {:ok, client_public_key} <- Utils.safe_url_decode(p256dh),
         {:ok, client_auth_secret} <- Utils.safe_url_decode(auth) do
      do_encrypt_aes128gcm(message, client_public_key, client_auth_secret)
    else
      error -> error
    end
  end

  defp do_encrypt_aes128gcm(message, client_public_key, client_auth_secret) do
    with {:ok, salt} <- generate_salt(),
         {:ok, {as_public_key, as_private_key}} <- generate_keypair(),
         {:ok, shared_secret} <- compute_shared_secret(client_public_key, as_private_key),
         {:ok, ikm} <-
           derive_ikm(client_auth_secret, shared_secret, client_public_key, as_public_key),
         {:ok, content_encryption_key} <- hkdf_cek(salt, ikm),
         {:ok, nonce} <- hkdf_nonce(salt, ikm),
         {:ok, padded_message} <- pad_message(message),
         {:ok, {cipher_text, cipher_tag}} <-
           encrypt_message(padded_message, content_encryption_key, nonce),
         {:ok, encrypted_body} <-
           build_encrypted_body(salt, as_public_key, cipher_text, cipher_tag) do
      {:ok,
       %{
         ciphertext: encrypted_body,
         salt: salt,
         as_public_key: as_public_key
       }}
    end
  end

  def generate_salt do
    {:ok, :crypto.strong_rand_bytes(@salt_length)}
  end

  def generate_keypair do
    {:ok, :crypto.generate_key(:ecdh, @prime256v1_curve)}
  end

  defp compute_shared_secret(client_public_key, as_private_key) do
    try do
      shared_secret =
        :crypto.compute_key(:ecdh, client_public_key, as_private_key, @prime256v1_curve)

      {:ok, shared_secret}
    catch
      :error, {:error, {_file, _line}, reason} ->
        {:error, {:invalid_ecdh_key, reason}}

      :error, reason ->
        {:error, {:ecdh_failed, reason}}
    end
  end

  defp derive_ikm(client_auth_secret, shared_secret, client_public_key, as_public_key) do
    prk_key = hkdf_extract(client_auth_secret, shared_secret)

    # HKDF-Expand(PRK_key, key_info, L_key=32)
    # key_info = "WebPush: info" || 0x00 || ua_public || as_public
    key_info = "WebPush: info" <> <<0>> <> client_public_key <> as_public_key
    ikm = hkdf_expand(prk_key, key_info, @key_length)

    {:ok, ikm}
  end

  defp hkdf_cek(salt, ikm) do
    # HKDF-Extract(salt, IKM)
    prk = hkdf_extract(salt, ikm)

    # HKDF-Expand(PRK, cek_info, L_cek=16)
    # cek_info = "Content-Encoding: aes128gcm" || 0x00
    cek_info = "Content-Encoding: aes128gcm" <> <<0>>
    cek = hkdf_expand(prk, cek_info, @content_encryption_key_length)

    {:ok, cek}
  end

  defp hkdf_nonce(salt, ikm) do
    prk = hkdf_extract(salt, ikm)

    # HKDF-Expand(PRK, nonce_info, L_nonce=12)
    # nonce_info = "Content-Encoding: nonce" || 0x00
    nonce_info = "Content-Encoding: nonce" <> <<0>>
    nonce = hkdf_expand(prk, nonce_info, @nonce_length)

    {:ok, nonce}
  end

  defp pad_message(message) do
    # 0x02 delimiter
    padded_message = message <> <<0x02>>
    {:ok, padded_message}
  end

  defp encrypt_message(padded_message, content_encryption_key, nonce) do
    case :crypto.crypto_one_time_aead(
           :aes_128_gcm,
           content_encryption_key,
           nonce,
           padded_message,
           <<>>,
           true
         ) do
      {cipher_text, cipher_tag} when is_binary(cipher_text) and is_binary(cipher_tag) ->
        {:ok, {cipher_text, cipher_tag}}

      error ->
        {:error, {:aes_encryption_failed, error}}
    end
  end

  defp build_encrypted_body(salt, as_public_key, cipher_text, cipher_tag) do
    plaintext_size = byte_size(cipher_text)
    auth_tag_size = byte_size(cipher_tag)

    min_record_size = plaintext_size + auth_tag_size + 1
    record_size = max(min_record_size, @record_size)

    # salt (16) + rs (4) + idlen (1) + keyid (65) = 86 bytes total
    header =
      salt <>
        <<record_size::unsigned-big-integer-size(32)>> <>
        <<@public_key_length::unsigned-big-integer-size(8)>> <>
        as_public_key

    encrypted_body = header <> cipher_text <> cipher_tag
    {:ok, encrypted_body}
  end

  defp hkdf_extract(salt, ikm) do
    :crypto.mac(:hmac, :sha256, salt, ikm)
  end

  defp hkdf_expand(prk, info, length) do
    :crypto.mac(:hmac, :sha256, prk, info <> <<1>>)
    |> :binary.part(0, length)
  end
end
