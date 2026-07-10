# ExNudge

[![Hex.pm](https://img.shields.io/hexpm/v/ex_nudge.svg)](https://hex.pm/packages/ex_nudge)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/ex_nudge)
[![CI](https://github.com/Joraeuw/ex_nudge/workflows/CI/badge.svg)](https://github.com/Joraeuw/ex_nudge/actions)
[![Coverage](https://coveralls.io/repos/github/Joraeuw/ex_nudge/badge.svg)](https://coveralls.io/github/Joraeuw/ex_nudge)

ExNudge is a pure Elixir library that allows easy multi-platform integration with web push notifications and encryption of messages described under [RFC 8291](https://www.rfc-editor.org/rfc/rfc8291.html) and [RFC 8292](https://www.rfc-editor.org/rfc/rfc8292.html)

## Features

- **RFC 8291 Compliant** - Full Web Push Protocol implementation
- **VAPID Support/RFC 8292 Compliant** - Voluntary Application Server Identification
- **AES-GCM Encryption** - Secure payload encryption
- **Bring your own HTTP client** - Dependency-free `:httpc` default, pluggable via a small behaviour
- **Structured notifications** - `ExNudge.Notification` mirrors the browser's `showNotification` options
- **Normalized errors** - Every failure is an `%ExNudge.Error{}` with a stable `:reason`
- **Telemetry integration** - Telemetry on sent notifications

## Installation

Add `ex_nudge` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_nudge, "~> 2.0"}
  ]
end
```

Upgrading from 1.x? See the [migration notes](CHANGELOG.md#200).

## Quick Start

### 1. Generate VAPID Keys

```console
$ mix ex_nudge.gen.vapid_keys
```

This prints a ready-to-paste config snippet. Keys can also be generated
programmatically with `ExNudge.generate_vapid_keys/0`.

### 2. Configure Your Application

```elixir
# config/runtime.exs (or config/config.exs)
config :ex_nudge,
  vapid_subject: "mailto:your-email@example.com",
  vapid_public_key: "your_public_key_here",
  vapid_private_key: "your_private_key_here"
```

Keys are validated when sending, so runtime configuration works fine. For
multi-tenant applications you can also pass a different key pair per call via
the `:vapid` option.

### 3. Send a Notification

```elixir
# Create a subscription and store it somewhere (typically in your database)
subscription = %ExNudge.Subscription{
  endpoint: "https://fcm.googleapis.com/fcm/send/...",
  keys: %{
    p256dh: "client_public_key",
    auth: "client_auth_secret"
  },
  metadata: "any metadata"
}

# Send the notification
case ExNudge.send_notification(subscription, "Hello, World!") do
  {:ok, %ExNudge.Response{status: status}} ->
    IO.puts("Notification sent successfully (#{status})!")

  {:error, %ExNudge.Error{reason: :subscription_expired}} ->
    IO.puts("Subscription has expired, remove from database")

  {:error, %ExNudge.Error{} = error} ->
    IO.puts("Failed to send: #{Exception.message(error)}")
end
```

### Structured Notifications

Instead of a raw string you can send an `ExNudge.Notification`, which maps
1:1 to the options of the browser's
[`showNotification`](https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerRegistration/showNotification)
API and is delivered as JSON:

```elixir
notification =
  ExNudge.Notification.new("Order shipped",
    body: "Your package is on the way",
    icon: "/images/icon.png",
    tag: "orders",
    data: %{url: "/orders/42"},
    actions: [%{action: "open", title: "Open order"}]
  )

ExNudge.send_notification(subscription, notification)
```

Your service worker can then pass the payload straight through — see
[Browser Integration](#browser-integration) below.

### Sending to Many Subscriptions

Batch delivery is intentionally left to you, so you control concurrency,
error handling and retries with the primitives you already know:

```elixir
subscriptions
|> Task.async_stream(
  fn subscription -> {subscription, ExNudge.send_notification(subscription, message)} end,
  max_concurrency: 100,
  on_timeout: :kill_task
)
|> Enum.each(fn
  {:ok, {subscription, {:ok, _response}}} ->
    IO.puts("Sent to #{subscription.metadata}")

  {:ok, {subscription, {:error, %ExNudge.Error{reason: :subscription_expired}}}} ->
    MyApp.remove_subscription(subscription)

  {:ok, {subscription, {:error, error}}} ->
    IO.puts("Failed for #{subscription.metadata}: #{Exception.message(error)}")

  {:exit, reason} ->
    IO.puts("Send crashed: #{inspect(reason)}")
end)
```

If you need at-least-once delivery, retries or rate limiting, wrap the send
in a job processor such as [Oban](https://hex.pm/packages/oban).

### Custom Options

```elixir
# Send with custom options
ExNudge.send_notification(subscription, message,
  ttl: 3600,             # Time to live (seconds)
  urgency: :high,        # :very_low, :low, :normal, :high
  topic: "breaking_news" # Replace previous messages with same topic
)

# Multi-tenant: override the configured VAPID values for this call only
ExNudge.send_notification(subscription, message,
  vapid: [
    subject: "mailto:tenant@example.com",
    public_key: tenant.vapid_public_key,
    private_key: tenant.vapid_private_key
  ]
)
```

### HTTP Client

ExNudge performs requests through the `ExNudge.HTTPClient` behaviour. The
default adapter uses Erlang/OTP's built-in `:httpc` with proper TLS
verification (requires OTP 25+), so no HTTP library is forced on you.

To use your favorite client instead, implement the single-callback behaviour
and configure it:

```elixir
config :ex_nudge, http_client: MyApp.ExNudgeClient
```

See the `ExNudge.HTTPClient` docs for a complete `Req`-based example.

### Telemetry

```elixir
# Attach telemetry handler
:telemetry.attach("my-handler", [:ex_nudge, :send_notification], fn name, measurements, metadata, config ->
  case metadata.status do
    :success ->
      Logger.info("Notification sent successfully",
        duration: measurements.duration,
        endpoint: metadata.endpoint)
    :error ->
      Logger.error("Notification failed",
        error: metadata.error_reason,
        http_status: metadata.http_status_code)
  end
end, nil)
```

## Browser Integration

### JavaScript Client Code

```javascript
navigator.serviceWorker.register('/sw.js');

const permission = await Notification.requestPermission();
if (permission === 'granted') {
  const registration = await navigator.serviceWorker.ready;
  const subscription = await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: 'your_vapid_public_key'
  });

  // Send subscription to your server
  await fetch('/api/subscriptions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(subscription)
  });
}
```

### Service Worker (sw.js)

When you send `ExNudge.Notification` structs, the payload already matches the
`showNotification` options, so the service worker is a simple pass-through:

```javascript
self.addEventListener('push', event => {
  if (!event.data) return;

  const payload = event.data.json();

  event.waitUntil(
    self.registration.showNotification(payload.title, payload)
  );
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil(clients.openWindow(url));
});
```

Keep in mind that sw.js and any icon/badge images usually are statically served files. <br>
Take a look into the [ServiceWorkerRegistration documentation](https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerRegistration/showNotification#options) for more details on options.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for your changes
4. Ensure all tests pass: `mix test`
5. Submit a pull request
