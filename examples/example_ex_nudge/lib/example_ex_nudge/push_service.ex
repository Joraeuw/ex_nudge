defmodule ExampleExNudge.PushService do
  alias ExampleExNudge.Repo
  alias ExampleExNudge.Models.PushSubscription

  import Ecto.Query
  require Logger

  def list_subscriptions do
    Repo.all(PushSubscription)
  end

  def subscribe_device(sub_data) do
    %PushSubscription{}
    |> PushSubscription.changeset(parse_subscription_data(sub_data))
    |> Repo.insert()
  end

  def remove_device(device_id) do
    entity = Repo.get!(PushSubscription, device_id)
    Repo.delete(entity)
  end

  def broadcast(payload) do
    PushSubscription
    |> Repo.all()
    |> Enum.map(fn subscription ->
      %ExNudge.Subscription{
        endpoint: subscription.endpoint,
        keys: %{
          p256dh: subscription.p256dh_key,
          auth: subscription.auth_key
        }
      }
    end)
    |> ExNudge.send_notifications(payload)
  end

  def send_push_notification(subscription_id, payload) when is_bitstring(subscription_id) do
    send_push_notification(Repo.get!(PushSubscription, subscription_id), payload)
  end

  def send_push_notification(subscription, payload) do
    ExNudge.send_notification(
      %ExNudge.Subscription{
        endpoint: subscription.endpoint,
        keys: %{
          p256dh: subscription.p256dh_key,
          auth: subscription.auth_key
        }
      },
      payload
    )
  end

  def unsubscribe_device(endpoint) do
    from(s in PushSubscription, where: s.endpoint == ^endpoint)
    |> Repo.one!()
    |> Repo.delete()
  end

  defp parse_subscription_data(%{
         "endpoint" => endpoint,
         "keys" => %{"p256dh" => p256dh, "auth" => auth}
       }) do
    %{
      endpoint: endpoint,
      p256dh_key: p256dh,
      auth_key: auth
    }
  end
end
