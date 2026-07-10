# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0]

### Changed (breaking)
- **HTTPoison is no longer a dependency.** Requests go through the new
  `ExNudge.HTTPClient` behaviour; the default adapter uses Erlang/OTP's
  `:httpc` with TLS verification against the OS trust store (requires
  OTP 25+). Configure a custom client with `config :ex_nudge, http_client: MyClient`.
- **Normalized responses.** Success is now `{:ok, %ExNudge.Response{status: ..., headers: ..., body: ...}}`
  instead of `{:ok, %HTTPoison.Response{}}`.
- **Normalized errors.** All failures return `{:error, %ExNudge.Error{}}`, an
  exception struct with a stable `:reason` atom (`:subscription_expired`,
  `:payload_too_large`, `:http_error`, `:request_failed`, `:missing_vapid_keys`,
  `:missing_vapid_subject`, `:invalid_vapid_keys`, `:invalid_subscription`,
  `:invalid_subscription_keys`, `:encryption_failed`), plus `:status`,
  `:response` and `:context` fields. `ExNudge.Subscription.from_map/2` returns
  `{:error, %ExNudge.Error{reason: :invalid_subscription}}` instead of a bare atom.
- HTTP 404 responses from push services are now treated as
  `:subscription_expired` (matching 410), as FCM uses 404 for stale subscriptions.
- A missing `:vapid_subject` is now rejected at send time with
  `:missing_vapid_subject` instead of silently signing a JWT with `sub: nil`.
- The VAPID JWT `aud` claim now includes the endpoint's port when it is not
  the default for the scheme.

### Removed (breaking)
- `ExNudge.send_notifications` (batch sending). Use `Task.async_stream/3`
  (see the README recipe) or a job processor like Oban. The removed
  implementation also crashed the caller on task timeouts.
- The `Encryption`, `VAPID` and `Utils` modules are now private
  (`@moduledoc false`); the public API is `ExNudge`, `ExNudge.Subscription`,
  `ExNudge.Notification`, `ExNudge.HTTPClient`, `ExNudge.Response`,
  `ExNudge.Error` and `ExNudge.Telemetry`.

### Added
- `ExNudge.Notification` — a structured payload mirroring the browser's
  `showNotification` options (camelCase JSON, unset fields omitted), accepted
  by `ExNudge.send_notification/3` alongside plain binaries.
- `mix ex_nudge.gen.vapid_keys` — generates a key pair and prints a
  ready-to-paste config snippet.
- Per-call VAPID override: `ExNudge.send_notification(sub, msg, vapid: [subject: ..., public_key: ..., private_key: ...])`
  for multi-tenant applications; unset values fall back to the app config.
- Oversized payloads (> 3993 bytes, per RFC 8291) are rejected locally with
  `:payload_too_large` before contacting the push service.

### Migration from 1.x

```elixir
# Success — before:
{:ok, %HTTPoison.Response{status_code: 201}} = ExNudge.send_notification(sub, msg)
# after:
{:ok, %ExNudge.Response{status: 201}} = ExNudge.send_notification(sub, msg)

# Errors — before:
{:error, :subscription_expired} = ExNudge.send_notification(sub, msg)
# after:
{:error, %ExNudge.Error{reason: :subscription_expired}} = ExNudge.send_notification(sub, msg)

# Batch — before:
ExNudge.send_notifications(subs, msg)
# after (README has a fuller recipe):
Task.async_stream(subs, &ExNudge.send_notification(&1, msg), max_concurrency: 100)
```

## [1.0.0]

### Added
- Initial release
- RFC 8291 compliant Web Push Protocol implementation
- VAPID (RFC 8292) authentication support
- AES-GCM payload encryption
- Error handling
- Telemetry integration
- Concurrent batch sending support
- Complete test suite
- Documentation and examples

### Features
- Send individual notifications with `ExNudge.send_notification/3`
- Send batch notifications with `send_notifications/3` (removed in 2.0.0)
- Generate VAPID keys with `ExNudge.generate_vapid_keys/0`
- Support for TTL, urgency, and topic headers
- Automatic subscription validation
- Detailed error reporting