defmodule ExampleExNudgeWeb.NotificationLive do
  use ExampleExNudgeWeb, :live_view

  alias ExampleExNudge.PushService

  def render(assigns) do
    ~H"""
    <div id="push-notifications-component" class="space-y-6" phx-hook="PushNotificationHook">
      <div>
        <button
          :if={!@is_pwa}
          id="install-button"
          type="button"
          class="px-4 py-2 bg-green-600 text-white text-sm rounded-md hover:bg-green-700"
        >
          Install PWA
        </button>
      </div>
      <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
        <div class="flex items-center justify-between">
          <div>
            <h3 class="font-medium text-blue-900">Push Notifications</h3>
            <p class="text-sm text-blue-700">Get alerts on your subscriptions</p>
          </div>
          <div id="status-indicator" class="w-3 h-3 rounded-full bg-gray-400"></div>
        </div>
      </div>
      <!-- Quick Controls -->
      <div class="flex space-x-3">
        <button
          id="subscribe-btn"
          type="button"
          class="px-4 py-2 bg-blue-600 text-white text-sm rounded-md hover:bg-blue-700"
        >
          Enable Notifications
        </button>

        <button
          phx-click="broadcast_test_notification"
          type="button"
          class="px-4 py-2 bg-green-600 text-white text-sm rounded-md hover:bg-green-700"
        >
          Broadcast Test
        </button>

        <button
          phx-click="refresh_subscriptions"
          type="button"
          class="px-4 py-2 bg-gray-600 text-white text-sm rounded-md hover:bg-gray-700"
        >
          Refresh
        </button>
      </div>
      <div class="border border-gray-200 rounded-lg divide-y divide-gray-200">
        <div class="px-4 py-2 bg-gray-50">
          <h4 class="font-medium text-gray-900 text-sm">
            Registered subscriptions ({@subscription_size})
          </h4>
        </div>

        <div id="subscription_stream" phx-update="stream">
          <%= for {sub_id, sub} <- @streams.subscriptions do %>
            <div id={sub_id} class="px-4 py-3 flex items-center justify-between">
              <div class="flex items-center space-x-2">
                <span class="text-sm">{sub.id}</span>
              </div>
              <button
                phx-click="remove_device"
                phx-value-subscription_id={sub.id}
                phx-confirm="Remove this device?"
                class="text-xs text-red-600 hover:text-red-800"
              >
                Remove
              </button>

              <button
                phx-click="test_notification"
                phx-value-subscription_id={sub.id}
                class="text-xs text-red-600 hover:text-red-800"
              >
                Send notification
              </button>
            </div>
          <% end %>
        </div>
      </div>
      <input type="hidden" id="vapid-public-key" value={@vapid_public_key} />
    </div>
    """
  end

  def mount(_params, _session, socket) do
    vapid_public_key = Application.get_env(:ex_nudge, :vapid_public_key)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExampleExNudge.PubSub, "push_notifications")
    end

    subscriptions = PushService.list_subscriptions()

    new_socket =
      socket
      |> assign(:vapid_public_key, vapid_public_key)
      |> assign(:is_pwa, false)
      |> assign(:subscription_size, Enum.count(subscriptions))
      |> stream(:subscriptions, subscriptions)

    {:ok, new_socket}
  end

  def handle_event("subscribe", %{"subscription" => subscription_data}, socket) do
    case PushService.subscribe_device(subscription_data) do
      {:ok, subscription} ->
        broadcast_device_added(subscription)

        {:noreply, put_flash(socket, :info, "Device subscribed successfully!")}

      {:error, changeset} ->
        error_msg = format_changeset_errors(changeset)
        socket = put_flash(socket, :error, "Subscription failed: #{error_msg}")
        {:noreply, socket}
    end
  end

  def handle_event("is-pwa", params, socket) do
    {:noreply, assign(socket, :is_pwa, true)}
  end

  def handle_event("unsubscribe", %{"endpoint" => endpoint}, socket) do
    case PushService.unsubscribe_device(endpoint) do
      {:ok, subscription} ->
        broadcast_device_removed(subscription)

        {:noreply, put_flash(socket, :info, "Device removed successfully!")}

      {:error, changeset} ->
        error_msg = format_changeset_errors(changeset)
        socket = put_flash(socket, :error, "Failed to remove device: #{error_msg}")
        {:noreply, socket}
    end
  end

  def handle_event("test_notification", %{"subscription_id" => subscription_id}, socket) do
    new_socket =
      case PushService.send_push_notification(
             subscription_id,
             format_message("Test Message 📩", "Test for subscription #{subscription_id}.")
           ) do
        {:ok, _response} ->
          put_flash(socket, :info, "Test sent to #{subscription_id}!")

        {:error, reason} ->
          put_flash(
            socket,
            :info,
            "Notification to #{subscription_id} failed with reason #{inspect(reason)}"
          )
      end

    {:noreply, new_socket}
  end

  def handle_event("broadcast_test_notification", _params, socket) do
    successful_notification_count =
      PushService.broadcast(
        format_message("Broadcasted Test Message! 📩", "🚀🚀🚀 Broadcasted Test Message 🚀🚀🚀")
      )
      |> Enum.count(fn
        {:ok, _, _} -> true
        {:error, _, _} -> false
      end)

    {:noreply,
     put_flash(socket, :info, "Test sent to #{successful_notification_count} subscriptions")}
  end

  def handle_event(
        "remove_device",
        %{"subscription_id" => subscription_id},
        socket
      ) do
    case PushService.remove_device(subscription_id) do
      {:ok, sub} ->
        broadcast_device_removed(sub)

        {:noreply, put_flash(socket, :info, "Device removed")}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to remove device: #{reason}")
        {:noreply, socket}
    end
  end

  def handle_event("refresh_subscriptions", _params, socket) do
    subscriptions = PushService.list_subscriptions()

    socket = assign(socket, :subscriptions, subscriptions)
    {:noreply, stream(socket, :subscriptions, subscriptions, reset: true)}
  end

  def handle_info({:device_removed, subscription}, socket) do
    new_socket =
      socket
      |> stream_delete(:subscriptions, subscription)
      |> assign(:subscription_size, max(0, socket.assigns.subscription_size - 1))
      |> push_event("device_removed", %{endpoint: subscription.endpoint})

    {:noreply, new_socket}
  end

  def handle_info({:device_added, subscription}, socket) do
    new_socket =
      socket
      |> stream_insert(:subscriptions, subscription)
      |> assign(:subscription_size, socket.assigns.subscription_size + 1)

    {:noreply, new_socket}
  end

  defp broadcast_device_removed(subscription) do
    Phoenix.PubSub.broadcast(
      ExampleExNudge.PubSub,
      "push_notifications",
      {:device_removed, subscription}
    )
  end

  defp broadcast_device_added(subscription) do
    Phoenix.PubSub.broadcast(
      ExampleExNudge.PubSub,
      "push_notifications",
      {:device_added, subscription}
    )
  end

  defp format_changeset_errors(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {message, _}} -> "#{field}: #{message}" end)
  end

  defp format_message(title, body) do
    Jason.encode!(%{title: title, body: body})
  end
end
