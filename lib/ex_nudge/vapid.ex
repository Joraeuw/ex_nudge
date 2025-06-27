defmodule ExNudge.VAPID do
  @moduledoc """
  Handles VAPID (Voluntary Application Server Identification) authentication.
  """

  alias ExNudge.Utils

  @type vapid_keys :: %{public: binary(), private: binary()}

  @spec get_keys() :: {:ok, vapid_keys()} | {:error, atom()}
  def get_keys do
    with public_key when is_binary(public_key) <- get_config(:vapid_public_key),
         private_key when is_binary(private_key) <- get_config(:vapid_private_key),
         {:ok, decoded_public} <- Utils.safe_url_decode(public_key),
         {:ok, decoded_private} <- Utils.safe_url_decode(private_key) do
      {:ok, %{public: decoded_public, private: decoded_private}}
    else
      nil -> {:error, :missing_vapid_keys}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec sign_jwt(String.t(), vapid_keys()) :: {:ok, String.t()} | {:error, atom()}
  def sign_jwt(endpoint, %{public: vapid_public_key, private: vapid_private_key}) do
    %{scheme: scheme, host: host} = URI.parse(endpoint)

    jwt =
      JOSE.JWT.from_map(%{
        aud: "#{scheme}://#{host}",
        exp: DateTime.to_unix(DateTime.utc_now()) + 12 * 3600,
        sub: get_config(:vapid_subject)
      })

    jwk =
      JOSE.JWK.from_key({
        :ECPrivateKey,
        1,
        vapid_private_key,
        {:namedCurve, {1, 2, 840, 10_045, 3, 1, 7}},
        vapid_public_key,
        nil
      })

    {_jws, signed_token} =
      JOSE.JWS.compact(JOSE.JWT.sign(jwk, %{"alg" => "ES256"}, jwt))

    {:ok, signed_token}
  end

  @spec generate_vapid_keys() :: %{public_key: String.t(), private_key: String.t()}
  def generate_vapid_keys do
    {public_key, private_key} = :crypto.generate_key(:ecdh, :prime256v1)

    %{
      public_key: Utils.url_encode(public_key),
      private_key: Utils.url_encode(private_key)
    }
  end

  defp get_config(key) do
    Application.get_env(:ex_nudge, key)
  end
end
