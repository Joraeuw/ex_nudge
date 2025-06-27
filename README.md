# ExNudge

[![Hex.pm](https://img.shields.io/hexpm/v/ex_nudge.svg)](https://hex.pm/packages/ex_nudge)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/ex_nudge)
[![CI](https://github.com/Joraeuw/ex_nudge/workflows/CI/badge.svg)](https://github.com/Joraeuw/ex_nudge/actions)
[![Coverage](https://coveralls.io/repos/github/Joraeuw/ex_nudge/badge.svg)](https://coveralls.io/github/Joraeuw/ex_nudge)

ExNudge is a pure elixir library that allows easy multi-platform integration with web push notifications and encryption of messages described under [RFC 8291](https://www.rfc-editor.org/rfc/rfc8291.html) and [RFC 8292](https://www.rfc-editor.org/rfc/rfc8292.html)

## Features

- **RFC 8291 Compliant** - Full Web Push Protocol implementation
- **VAPID Support/RFC 8292 Compliant** - Voluntary Application Server Identification  
- **AES-GCM Encryption** - Secure payload encryption
- **Concurrent Sending** - Send to multiple subscriptions simultaneously
- **Telemetry integration** - Telemetry on sent notifications

## Installation

Add `ex_nudge` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_nudge, "~> 1.0"}
  ]
end
```

## Quick Start

### 1. Generate VAPID Keys

```elixir
keys = ExNudge.generate_vapid_keys()
IO.puts("Public Key: #{keys.public_key}")
IO.puts("Private Key: #{keys.private_key}")
```

### 2. Configure Your Application

```elixir
# config/config.exs
config :ex_nudge,
  vapid_subject: "mailto:your-email@example.com",
  vapid_public_key: "your_public_key_here",
  vapid_private_key: "your_private_key_here"
```

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
  {:ok, response} -> 
    IO.puts("Notification sent successfully!")
  {:error, :subscription_expired} -> 
    IO.puts("Subscription has expired, remove from database")
  {:error, reason} -> 
    IO.puts("Failed to send: #{inspect(reason)}")
end
```

### Batch Sending

```elixir
subscriptions = [subscription1, subscription2, subscription3]
results = ExNudge.send_notifications(subscriptions, "Multicast message")

# Process results
results
|> Enum.each(fn 
  {:ok, subscription, _response} -> 
    IO.puts("Successfully sent notification for #{subscription.metadata}")
    
  {:error, subscription, :subscription_expired} -> 
    # Remove expired subscription from database
    MyApp.remove_subscription(subscription)
    IO.puts("Removed expired subscription: #{subscription.metadata}")
    
  {:error, subscription, %HTTPoison.Response{status_code: status_code}} -> 
    IO.puts("HTTP error #{status_code} for #{subscription.metadata}")
    
  {:error, subscription, reason} -> 
    IO.puts("Failed to send to #{subscription.metadata}: #{inspect(reason)}")
end)

# You can also configure concurrency which defaults to System.schedulers_online() * 2
results = ExNudge.send_notifications(
  subscriptions, 
  "Multicast message", 
  concurrency: 10
)
```

### Custom Options

```elixir
# Send with custom options
ExNudge.send_notification(subscription, message, [
  ttl: 3600,                    # Time to live (seconds)
  urgency: :high,               # :very_low, :low, :normal, :high
  topic: "breaking_news"        # Replace previous messages with same topic
])
```

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

Keep in mind that sw.js, icon-192x192.png and badge-72x72.png usually are statically served files. <br>
Take a look into the [ServiceWorkerRegistration documentation](https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerRegistration/showNotification#options) for more details on options.

```javascript
self.addEventListener('push', event => {
  const data = event.data ? event.data.text() : 'Default message';
  
  const options = {
    body: data,
    icon: '/icon-192x192.png',
    badge: '/badge-72x72.png',
    vibrate: [100, 50, 100],
    data: { url: "/" }
  };
  
  event.waitUntil(
    self.registration.showNotification('App Name', options)
  );
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil(clients.openWindow(event.notification.data.url));
});
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for your changes
4. Ensure all tests pass: `mix test`
5. Submit a pull request