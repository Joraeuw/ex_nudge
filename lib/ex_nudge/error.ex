defmodule ExNudge.Error do
  @moduledoc """
  The exception returned by all ExNudge functions in `{:error, %ExNudge.Error{}}` tuples.

  Match on `:reason` to branch on failure modes — the reason atoms are a stable
  part of the public API:

    * `:subscription_expired` - the push service returned 404/410; delete the subscription
    * `:payload_too_large` - the payload exceeds the Web Push limit (RFC 8291)
    * `:http_error` - any other unexpected HTTP status, see `:status` and `:response`
    * `:request_failed` - the HTTP request itself failed (network error), see `:context`
    * `:missing_vapid_keys` - `:vapid_public_key`/`:vapid_private_key` not configured
    * `:missing_vapid_subject` - `:vapid_subject` not configured
    * `:invalid_vapid_keys` - configured VAPID keys are not valid base64url
    * `:invalid_subscription` - the subscription map is malformed
    * `:invalid_subscription_keys` - the subscription's `p256dh`/`auth` keys can't be decoded
    * `:encryption_failed` - payload encryption failed unexpectedly

  Since this is an exception, you can also `raise` it directly when you have no
  better way to handle it:

      case ExNudge.send_notification(subscription, message) do
        {:ok, response} -> response
        {:error, error} -> raise error
      end
  """

  defexception [:reason, :status, :response, :context]

  @type t :: %__MODULE__{
          reason: atom(),
          status: pos_integer() | nil,
          response: ExNudge.Response.t() | nil,
          context: term()
        }

  @doc """
  Builds an `ExNudge.Error` for the given reason.

  Accepted fields: `:status`, `:response`, `:context`.
  """
  @spec new(atom(), keyword()) :: t()
  def new(reason, fields \\ []) when is_atom(reason) do
    struct!(__MODULE__, Keyword.put(fields, :reason, reason))
  end

  @doc false
  @spec normalize(term()) :: t()
  def normalize(%__MODULE__{} = error), do: error

  def normalize(reason) when reason in [:invalid_base64, :invalid_input],
    do: new(:invalid_subscription_keys, context: reason)

  def normalize({key_error, detail}) when key_error in [:invalid_ecdh_key, :ecdh_failed],
    do: new(:invalid_subscription_keys, context: {key_error, detail})

  def normalize({:aes_encryption_failed, detail}),
    do: new(:encryption_failed, context: detail)

  def normalize(reason) when is_atom(reason), do: new(reason)

  def normalize(other), do: new(:unknown, context: other)

  @impl true
  def message(%__MODULE__{reason: :subscription_expired}),
    do: "the subscription has expired or is no longer valid; it should be deleted"

  def message(%__MODULE__{reason: :payload_too_large}),
    do: "the payload exceeds the maximum Web Push payload size (RFC 8291)"

  def message(%__MODULE__{reason: :missing_vapid_keys}),
    do:
      "VAPID keys are not configured; set :vapid_public_key and :vapid_private_key " <>
        "in the :ex_nudge config or pass them via the :vapid option"

  def message(%__MODULE__{reason: :missing_vapid_subject}),
    do:
      "the :vapid_subject setting is not configured; set it in the :ex_nudge config " <>
        "or pass it via the :vapid option"

  def message(%__MODULE__{reason: :invalid_vapid_keys}),
    do: "the configured VAPID keys are not valid base64url-encoded values"

  def message(%__MODULE__{reason: :invalid_subscription}),
    do: "the subscription map is missing an endpoint or its p256dh/auth keys"

  def message(%__MODULE__{reason: :invalid_subscription_keys}),
    do: "the subscription's p256dh/auth keys could not be decoded"

  def message(%__MODULE__{reason: :encryption_failed, context: context}),
    do: "payload encryption failed: #{inspect(context)}"

  def message(%__MODULE__{reason: :http_error, status: status}),
    do: "the push service responded with unexpected HTTP status #{status}"

  def message(%__MODULE__{reason: :request_failed, context: context}),
    do: "the HTTP request to the push service failed: #{inspect(context)}"

  def message(%__MODULE__{reason: reason}),
    do: "web push failed: #{inspect(reason)}"
end
