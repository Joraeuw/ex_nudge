defmodule ExampleExNudgeWeb.PushSubscriptionController do
  use ExampleExNudgeWeb, :controller

  alias ExampleExNudge.PushService
  alias ExampleExNudgeWeb.PushToken

  @doc """
  Called by the service worker on `pushsubscriptionchange`.

  The token proves the request comes from a service worker we issued a token
  to, and names the endpoint being replaced. On success a fresh token bound to
  the new endpoint is returned for the service worker to store.
  """
  def refresh(conn, %{"token" => token, "subscription" => subscription_params}) do
    with {:ok, old_endpoint} <- PushToken.verify(token),
         {:ok, %{removed: removed, added: added}} <-
           PushService.refresh_subscription(old_endpoint, subscription_params) do
      if removed, do: broadcast({:device_removed, removed})
      broadcast({:device_added, added})

      json(conn, %{token: PushToken.sign(added.endpoint)})
    else
      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid subscription"})

      {:error, _reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid token"})
    end
  end

  def refresh(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "token and subscription are required"})
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(ExampleExNudge.PubSub, "push_notifications", message)
  end
end
