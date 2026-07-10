defmodule ExampleExNudgeWeb.PushToken do
  @moduledoc """
  Signed tokens that let the service worker authenticate the
  `pushsubscriptionchange` refresh request.

  Service workers cannot read the CSRF meta tag from the page, so the refresh
  endpoint sits in the `:api` pipeline (no CSRF plug) and authenticates with a
  `Phoenix.Token` instead. The token is bound to the subscription endpoint it
  was issued for, handed to the page at subscribe time, and stored in
  IndexedDB where the service worker can reach it.
  """

  @salt "push_subscription"
  # Push subscriptions are long-lived; tokens are rotated on every refresh.
  @max_age 60 * 60 * 24 * 180

  def sign(endpoint) when is_binary(endpoint) do
    Phoenix.Token.sign(ExampleExNudgeWeb.Endpoint, @salt, endpoint)
  end

  def verify(token) do
    Phoenix.Token.verify(ExampleExNudgeWeb.Endpoint, @salt, token, max_age: @max_age)
  end
end
