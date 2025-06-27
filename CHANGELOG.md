# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- Send batch notifications with `ExNudge.send_notifications/3`
- Generate VAPID keys with `ExNudge.generate_vapid_keys/0`
- Support for TTL, urgency, and topic headers
- Automatic subscription validation
- Detailed error reporting