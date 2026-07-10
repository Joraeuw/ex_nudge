# ExampleExNudge

Demo Phoenix app for [ExNudge](https://hex.pm/packages/ex_nudge). It shows:

  * Subscribing/unsubscribing browsers to Web Push from a LiveView.
  * Sending structured payloads with `ExNudge.Notification` — the service
    worker (`priv/static/pwa-service-worker.js`) passes the JSON payload
    straight into `showNotification`, so everything (icons, actions, URLs)
    is controlled from the Elixir side.
  * Handling `pushsubscriptionchange` without CSRF: service workers cannot
    read the CSRF meta tag, so at subscribe time the server issues a signed
    `Phoenix.Token` bound to the subscription endpoint
    (`ExampleExNudgeWeb.PushToken`), which the page stores in IndexedDB. When
    the push service rotates the subscription, the service worker resubscribes
    and POSTs the new subscription plus that token to
    `/api/push_subscriptions/refresh` (`:api` pipeline, no CSRF plug). The
    server verifies the token, swaps the stored subscription, and responds
    with a fresh token bound to the new endpoint.

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
