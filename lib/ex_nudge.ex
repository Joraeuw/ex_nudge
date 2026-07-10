defmodule ExNudge do
  @moduledoc """
  A pure Elixir library for sending Web Push notifications.

  This library implements the Web Push Protocol as defined in RFC 8291
  with support for VAPID authentication and payload encryption as per RFC 8292.

  ## Quick Start

      # Generate VAPID keys once (see also `mix ex_nudge.gen.vapid_keys`)
      # and configure them:
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
      #=> {:ok, %ExNudge.Response{status: 201}}

  ## HTTP client

  ExNudge performs requests through the `ExNudge.HTTPClient` behaviour and
  ships with a dependency-free default adapter built on `:httpc`. Configure
  your own implementation with:

      config :ex_nudge, http_client: MyApp.ExNudgeClient

  ## Sending to many subscriptions

  Batch delivery is intentionally left to the caller so you can pick the
  concurrency, error handling and retry semantics that fit your application:

      subscriptions
      |> Task.async_stream(&ExNudge.send_notification(&1, message),
        max_concurrency: 100,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

  If you need at-least-once delivery or retries, wrap the send in a job
  processor such as Oban.
  """

  alias ExNudge.Encryption
  alias ExNudge.Error
  alias ExNudge.Notification
  alias ExNudge.Response
  alias ExNudge.Subscription
  alias ExNudge.Telemetry
  alias ExNudge.VAPID

  # RFC 8291/RFC 8188: 4096 bytes total per record, minus the 86-byte
  # encryption header, the 16-byte AEAD tag and the 1-byte padding delimiter.
  @max_payload_size 3993

  @type send_result :: {:ok, Response.t()} | {:error, Error.t()}

  @type message :: binary() | Notification.t()

  @type vapid_config :: [
          subject: String.t(),
          public_key: String.t(),
          private_key: String.t()
        ]

  @type send_options :: [
          ttl: pos_integer(),
          urgency: :very_low | :low | :normal | :high,
          topic: String.t(),
          vapid: vapid_config()
        ]

  @doc """
  Sends a web push notification to a single subscription.

  The message can be any binary of at most #{@max_payload_size} bytes, or an
  `ExNudge.Notification` struct, which is JSON-encoded in the format the
  browser's `showNotification` API expects.

  ## Options

    - `:ttl` - Time to live in seconds (default: 60)
    - `:urgency` - Message urgency level (default: :normal)
    - `:topic` - Topic for message replacement
    - `:vapid` - Per-call VAPID overrides (`:subject`, `:public_key`,
      `:private_key`); values not given fall back to the application config.
      Useful for multi-tenant applications with several key pairs.

  ## Return values

    - `{:ok, %ExNudge.Response{}}` - accepted by the push service
    - `{:error, %ExNudge.Error{}}` - see `ExNudge.Error` for the possible
      `:reason` values; `reason: :subscription_expired` means the subscription
      should be deleted

  ## Examples

      iex> subscription = %ExNudge.Subscription{...}
      iex> ExNudge.send_notification(subscription, "Hello!")
      {:ok, %ExNudge.Response{status: 201}}

      iex> ExNudge.send_notification(subscription, "Urgent!", urgency: :high, ttl: 300)
      {:ok, %ExNudge.Response{status: 201}}
  """
  @spec send_notification(Subscription.t(), message(), send_options()) :: send_result()
  def send_notification(%Subscription{} = subscription, message, opts \\ []) do
    payload = encode_message(message)

    with {:ok, vapid} <- VAPID.fetch_keys(opts),
         :ok <- validate_payload_size(payload),
         {:ok, encrypted_payload} <- Encryption.encrypt(payload, subscription.keys),
         {:ok, jwt} <- VAPID.sign_jwt(subscription.endpoint, vapid) do
      send_request(subscription, encrypted_payload, jwt, vapid, payload, opts)
    else
      {:error, reason} -> {:error, Error.normalize(reason)}
    end
  end

  @doc """
  Generates a new VAPID key pair for your application.

  Also available as a Mix task: `mix ex_nudge.gen.vapid_keys`.

  ## Examples

      iex> ExNudge.generate_vapid_keys()
      %{
        public_key: "BK8nBpIE2tsGVt8...",
        private_key: "aBcDeFgHiJkLmNoPqRsTuVwXyZ..."
      }
  """
  @spec generate_vapid_keys() :: %{public_key: String.t(), private_key: String.t()}
  defdelegate generate_vapid_keys(), to: VAPID

  defp encode_message(%Notification{} = notification), do: Jason.encode!(notification)
  defp encode_message(message) when is_binary(message), do: message

  defp validate_payload_size(message) when byte_size(message) > @max_payload_size,
    do: {:error, Error.new(:payload_too_large)}

  defp validate_payload_size(_message), do: :ok

  defp send_request(
         %Subscription{endpoint: endpoint} = subscription,
         encrypted_payload,
         jwt,
         vapid,
         message,
         opts
       ) do
    headers = build_headers(jwt, vapid, opts)
    start_time = System.monotonic_time(:millisecond)

    result =
      case http_client().post(endpoint, encrypted_payload.ciphertext, headers) do
        {:ok, %Response{status: status} = response} when status in 200..299 ->
          {:ok, response}

        {:ok, %Response{status: status} = response} when status in [404, 410] ->
          {:error, Error.new(:subscription_expired, status: status, response: response)}

        {:ok, %Response{status: 413} = response} ->
          {:error, Error.new(:payload_too_large, status: 413, response: response)}

        {:ok, %Response{status: status} = response} ->
          {:error, Error.new(:http_error, status: status, response: response)}

        {:error, reason} ->
          {:error, Error.new(:request_failed, context: reason)}
      end

    Telemetry.emit_notification_sent(start_time, subscription, byte_size(message), result)
    result
  end

  defp http_client do
    Application.get_env(:ex_nudge, :http_client, ExNudge.HTTPClient.Httpc)
  end

  defp build_headers(jwt, vapid, opts) do
    base_headers = [
      {"Authorization", "vapid t=#{jwt},k=#{vapid.encoded_public_key}"},
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
