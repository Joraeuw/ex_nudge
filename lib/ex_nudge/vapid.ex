defmodule ExNudge.VAPID do
  @moduledoc false
  # Handles VAPID (Voluntary Application Server Identification) authentication
  # as defined in RFC 8292.

  alias ExNudge.Error
  alias ExNudge.Utils

  @type keys :: %{
          public_key: binary(),
          private_key: binary(),
          encoded_public_key: String.t(),
          subject: String.t()
        }

  @doc """
  Resolves the VAPID configuration for a send.

  Values given under the `:vapid` option take precedence; anything not given
  falls back to the `:ex_nudge` application config. Validation happens here,
  at send time, so keys may be configured at runtime (e.g. `config/runtime.exs`).
  """
  @spec fetch_keys(keyword()) :: {:ok, keys()} | {:error, Error.t()}
  def fetch_keys(opts \\ []) do
    vapid = Keyword.get(opts, :vapid) || []

    public_key = vapid[:public_key] || get_config(:vapid_public_key)
    private_key = vapid[:private_key] || get_config(:vapid_private_key)
    subject = vapid[:subject] || get_config(:vapid_subject)

    with :ok <- validate_keys_present(public_key, private_key),
         :ok <- validate_subject(subject),
         {:ok, decoded_public} <- decode_key(public_key),
         {:ok, decoded_private} <- decode_key(private_key) do
      {:ok,
       %{
         public_key: decoded_public,
         private_key: decoded_private,
         encoded_public_key: public_key,
         subject: subject
       }}
    end
  end

  @spec sign_jwt(String.t(), keys()) :: {:ok, String.t()}
  def sign_jwt(endpoint, %{public_key: public_key, private_key: private_key, subject: subject}) do
    jwt =
      JOSE.JWT.from_map(%{
        aud: audience(endpoint),
        exp: DateTime.to_unix(DateTime.utc_now()) + 12 * 3600,
        sub: subject
      })

    jwk =
      JOSE.JWK.from_key({
        :ECPrivateKey,
        1,
        private_key,
        {:namedCurve, {1, 2, 840, 10_045, 3, 1, 7}},
        public_key,
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

  defp validate_keys_present(public_key, private_key)
       when is_binary(public_key) and is_binary(private_key),
       do: :ok

  defp validate_keys_present(_public_key, _private_key),
    do: {:error, Error.new(:missing_vapid_keys)}

  defp validate_subject(subject) when is_binary(subject) and subject != "", do: :ok
  defp validate_subject(_subject), do: {:error, Error.new(:missing_vapid_subject)}

  defp decode_key(key) do
    case Utils.safe_url_decode(key) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, Error.new(:invalid_vapid_keys)}
    end
  end

  # RFC 8292: the JWT audience is the origin of the push resource, which
  # includes the port when it is not the default for the scheme.
  defp audience(endpoint) do
    case URI.parse(endpoint) do
      %URI{scheme: scheme, host: host, port: port}
      when is_binary(scheme) and is_integer(port) ->
        if port == URI.default_port(scheme) do
          "#{scheme}://#{host}"
        else
          "#{scheme}://#{host}:#{port}"
        end

      %URI{scheme: scheme, host: host} ->
        "#{scheme}://#{host}"
    end
  end

  defp get_config(key) do
    Application.get_env(:ex_nudge, key)
  end
end
