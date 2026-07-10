defmodule ExNudge.Notification do
  @moduledoc """
  A structured Web Push payload mirroring the options of the browser's
  [`showNotification`](https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerRegistration/showNotification)
  API.

  Passing this struct to `ExNudge.send_notification/3` encodes it as JSON with
  the camelCase keys `showNotification` expects, so a service worker can use
  the payload directly:

      self.addEventListener('push', event => {
        const payload = event.data.json();
        event.waitUntil(self.registration.showNotification(payload.title, payload));
      });

  ## Example

      notification =
        ExNudge.Notification.new("Order shipped",
          body: "Your package is on the way",
          icon: "/images/icon.png",
          tag: "orders",
          data: %{url: "/orders/42"},
          actions: [%{action: "open", title: "Open order"}]
        )

      ExNudge.send_notification(subscription, notification)

  Field semantics follow the Notification API; all fields except `:title` are
  optional and omitted from the JSON when `nil` (or `[]` for `:actions`).
  """

  @type action :: %{
          required(:action) => String.t(),
          required(:title) => String.t(),
          optional(:icon) => String.t()
        }

  @type t :: %__MODULE__{
          title: String.t(),
          actions: [action()],
          badge: String.t() | nil,
          body: String.t() | nil,
          data: term(),
          dir: String.t() | nil,
          icon: String.t() | nil,
          image: String.t() | nil,
          lang: String.t() | nil,
          renotify: boolean() | nil,
          require_interaction: boolean() | nil,
          silent: boolean() | nil,
          tag: String.t() | nil,
          timestamp: non_neg_integer() | nil,
          vibrate: [non_neg_integer()] | nil
        }

  @enforce_keys [:title]
  defstruct [
    :title,
    :badge,
    :body,
    :data,
    :dir,
    :icon,
    :image,
    :lang,
    :renotify,
    :require_interaction,
    :silent,
    :tag,
    :timestamp,
    :vibrate,
    actions: []
  ]

  # struct key -> showNotification option name
  @json_keys [
    title: "title",
    actions: "actions",
    badge: "badge",
    body: "body",
    data: "data",
    dir: "dir",
    icon: "icon",
    image: "image",
    lang: "lang",
    renotify: "renotify",
    require_interaction: "requireInteraction",
    silent: "silent",
    tag: "tag",
    timestamp: "timestamp",
    vibrate: "vibrate"
  ]

  @doc """
  Builds a notification with the given title.

  ## Examples

      iex> ExNudge.Notification.new("Hello", body: "World")
      %ExNudge.Notification{title: "Hello", body: "World"}
  """
  @spec new(String.t(), keyword()) :: t()
  def new(title, fields \\ []) when is_binary(title) do
    struct!(__MODULE__, Keyword.put(fields, :title, title))
  end

  @doc """
  Converts the notification to a map with the camelCase string keys expected
  by `showNotification`, omitting unset fields.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = notification) do
    @json_keys
    |> Enum.map(fn {key, json_key} -> {json_key, Map.fetch!(notification, key)} end)
    |> Enum.reject(fn {_json_key, value} -> is_nil(value) or value == [] end)
    |> Map.new()
  end

  defimpl Jason.Encoder do
    def encode(notification, opts) do
      notification
      |> ExNudge.Notification.to_map()
      |> Jason.Encode.map(opts)
    end
  end
end
