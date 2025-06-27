defmodule ExNudge.Subscription do
  @moduledoc """
  Subscription from a client.
  """

  @type t :: %__MODULE__{
          endpoint: String.t(),
          keys: %{
            p256dh: String.t(),
            auth: String.t()
          },
          metadata: any()
        }

  @enforce_keys [:endpoint, :keys]
  defstruct [:endpoint, :keys, :metadata]

  @doc """
  Creates a new subscription from a JSON.
  You can use metadata to pass around some form of identification of the subscription.
  Metadata is NOT sent with the push notification request.

  ## Examples

      iex> data = %{
      ...>   "endpoint" => "https://fcm.googleapis.com/...",
      ...>   "keys" => %{
      ...>     "p256dh" => "client_public_key",
      ...>     "auth" => "client_auth_secret"
      ...>   }
      ...> }
      iex> ExNudge.Subscription.from_map(data)
      {:ok, %ExNudge.Subscription{...}}

      iex> data = %{
      ...>   "endpoint" => "https://fcm.googleapis.com/...",
      ...>   "keys" => %{
      ...>     "p256dh" => "client_public_key",
      ...>     "auth" => "client_auth_secret"
      ...>   }
      ...> }
      iex> metadata = "subscription_id_1"
      iex> ExNudge.Subscription.from_map(data, metadata)
      {:ok, %ExNudge.Subscription{...}}
  """
  @spec from_map(map(), any()) :: {:ok, t()} | {:error, :invalid_subscription}
  def from_map(
        subscription_map,
        metadata \\ nil
      )

  def from_map(
        %{"endpoint" => endpoint, "keys" => %{"p256dh" => p256dh, "auth" => auth}},
        metadata
      )
      when is_binary(endpoint) and is_binary(p256dh) and is_binary(auth) do
    {:ok,
     %__MODULE__{
       endpoint: endpoint,
       keys: %{p256dh: p256dh, auth: auth},
       metadata: metadata
     }}
  end

  def from_map(_, _), do: {:error, :invalid_subscription}

  @doc """
  Validates that a subscription has all required fields and valid format.
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{endpoint: endpoint, keys: %{p256dh: p256dh, auth: auth}}) do
    valid_url?(endpoint) and valid_key?(p256dh) and valid_key?(auth)
  end

  defp valid_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        true

      _ ->
        false
    end
  end

  defp valid_url?(_), do: false

  defp valid_key?(key) when is_binary(key) do
    case Base.url_decode64(key, padding: false) do
      {:ok, _} -> true
      :error -> false
    end
  end

  defp valid_key?(_), do: false
end
