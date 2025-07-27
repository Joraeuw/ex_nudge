defmodule ExNudge do
  @moduledoc """
  A pure Elixir library for sending Web Push notifications.

  This library implements the Web Push Protocol as defined in RFC 8291
  with support for VAPID authentication and payload encryption as per RFC 8292.

  ## Quick Start

      # Configure VAPID keys in your config
      config :ex_nudge,
        vapid_subject: "mailto:your-email@example.com",
        vapid_public_key: "your_public_key",
        vapid_private_key: "your_private_key"

      # Send a notification
      subscription = %ExNudge.Subscription{
        endpoint: "https://fcm.googleapis.com/fcm/send/...",
        keys: %{
          p256dh: "client_public_key",
          auth: "client_auth_secret"
        },
        metadata: "some_internal_id_or_map"
      }

      ExNudge.send_notification(subscription, "Hello, World!")
  """

  alias ExNudge.Encryption
  alias ExNudge.Subscription
  alias ExNudge.VAPID
  alias ExNudge.Telemetry

  @type send_result :: {:ok, HTTPoison.Response.t()} | {:error, atom() | String.t() | known_error()}
  @type send_options :: [
          ttl: pos_integer(),
          concurrency: pos_integer(),
          urgency: :very_low | :low | :normal | :high,
          topic: String.t()
        ]

  @type known_error ::
          :subscription_expired
          | :payload_too_large
          | {:request_failed, any()}
          | {:http_error, pos_integer()}

  @spec send_notification(ExNudge.Subscription.t(), binary()) ::
          {:error, atom()} | {:ok, HTTPoison.Response.t()}
  @doc """
  Sends a web push notification to a single subscription.

  ## Options

    - `:ttl` - Time to live in seconds (default: 60)
    - `:urgency` - Message urgency level (default: :normal)
    - `:topic` - Topic for message replacement

  ## Examples

      iex> subscription = %ExNudge.Subscription{...}
      iex> ExNudge.send_notification(subscription, "Hello!")
      {:ok, %HTTPoison.Response{status_code: 201}}

      iex> ExNudge.send_notification(subscription, "Urgent!", urgency: :high, ttl: 300)
      {:ok, %HTTPoison.Response{status_code: 201}}
  """

  @spec send_notification(Subscription.t(), String.t(), send_options()) :: send_result()
  def send_notification(%Subscription{} = subscription, message, opts \\ []) do
    with {:ok, vapid_keys} <- VAPID.get_keys(),
         {:ok, encrypted_payload} <- Encryption.encrypt(message, subscription.keys),
         {:ok, jwt} <- VAPID.sign_jwt(subscription.endpoint, vapid_keys) do
      send_request(subscription, encrypted_payload, jwt, message, opts)
    end
  end

  @doc """
  Sends web push notifications to multiple subscriptions concurrently.

  Returns a list of results in the same order as the input subscriptions.

  ## Examples

      iex> subscriptions = [sub1, sub2, sub3, sub4]
      iex> ExNudge.send_notifications(subscriptions, "Broadcast message")
      [
        {:ok, %ExNudge.Subscription{}, %HTTPoison.Response{}},
        {:error, :subscription_expired},
        {:error, :invalid_subscription},
        {:error, %ExNudge.Subscription{}, %HTTPoison.Response{}},
        {:ok, %ExNudge.Subscription{}, %HTTPoison.Response{}}
      ]
  """
  @spec send_notifications([Subscription.t()], String.t(), send_options()) ::
          [
            {:ok, Subscription.t(), HTTPoison.Response.t()}
            | {:error, Subscription.t(), HTTPoison.Response.t()}
            | {:error, Subscription.t(), known_error()}
          ]

  def send_notifications(subscriptions, message, opts \\ []) when is_list(subscriptions) do
    subscriptions
    |> Task.async_stream(
      fn subscription -> {subscription, send_notification(subscription, message, opts)} end,
      max_concurrency: Keyword.get(opts, :concurrency, System.schedulers_online() * 2),
      timeout: 30_000,
      zip_input_on_exit: true
    )
    |> Enum.map(fn
      {:ok, {subscription, {status, result}}} ->
        {status, subscription, result}

      {:exit, subscription, reason} ->
        {:error, subscription, reason}
    end)
  end

  @doc """
  Generates a new VAPID key pair for your application.

  ## Examples

      iex> ExNudge.generate_vapid_keys()
      %{
        public_key: "BK8nBpIE2tsGVt8...",
        private_key: "aBcDeFgHiJkLmNoPqRsTuVwXyZ..."
      }
  """
  @spec generate_vapid_keys() :: %{public_key: String.t(), private_key: String.t()}
  defdelegate generate_vapid_keys(), to: VAPID

  defp send_request(
         %Subscription{endpoint: endpoint} = subscription,
         encrypted_payload,
         jwt,
         message,
         opts
       ) do
    headers = build_headers(jwt, opts)
    start_time = System.monotonic_time(:millisecond)

    case HTTPoison.post(endpoint, encrypted_payload.ciphertext, headers) do
      {:ok, %HTTPoison.Response{status_code: status} = response} when status in 200..299 ->
        Telemetry.emit_notification_sent(
          start_time,
          subscription,
          byte_size(message),
          response
        )

        {:ok, response}

      {:ok, %HTTPoison.Response{status_code: 410}} ->
        Telemetry.emit_notification_sent(
          start_time,
          subscription,
          byte_size(message),
          {:error, :subscription_expired}
        )

        {:error, :subscription_expired}

      {:ok, %HTTPoison.Response{status_code: 413}} ->
        Telemetry.emit_notification_sent(
          start_time,
          subscription,
          byte_size(message),
          {:error, :payload_too_large}
        )

        {:error, :payload_too_large}

      {:ok, %HTTPoison.Response{status_code: status} = response} ->
        Telemetry.emit_notification_sent(
          start_time,
          subscription,
          byte_size(message),
          response
        )

        {:error, {:http_error, status}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Telemetry.emit_notification_sent(
          start_time,
          subscription,
          byte_size(message),
          {:error, {:request_failed, reason}}
        )

        {:error, {:request_failed, reason}}
    end
  end

  defp build_headers(jwt, opts) do
    vapid_public_key = Application.get_env(:ex_nudge, :vapid_public_key)

    base_headers = [
      {"Authorization", "vapid t=#{jwt},k=#{vapid_public_key}"},
      {"Content-Encoding", "aes128gcm"},
      {"Content-Type", "application/octet-stream"},
      {"TTL", "#{Keyword.get(opts, :ttl, 60)}"}
    ]

    base_headers
    |> maybe_add_urgency(opts[:urgency])
    |> maybe_add_topic(opts[:topic])
  end

  defp maybe_add_urgency(headers, nil), do: headers

  defp maybe_add_urgency(headers, urgency) do
    [{"Urgency", Atom.to_string(urgency)} | headers]
  end

  defp maybe_add_topic(headers, nil), do: headers

  defp maybe_add_topic(headers, topic) do
    [{"Topic", topic} | headers]
  end
end
