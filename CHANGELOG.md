# Changelog

All notable changes to BiometricShield will be documented in this file.

## [0.1.0] — 2026-02-26

### Added

- **Core SDK** — Instance-based `BiometricShield` with pure Dart core (zero Flutter imports).
- **Sealed result type** — `BiometricResult` with 10 exhaustive variants and `.when()` pattern matching: `success`, `fallbackSuccess`, `sessionValid`, `tokenExpired`, `cancelled`, `lockedOut`, `unavailable`, `invalidated`, `reauthenticationRequired`, `error`.
- **Session management** — Configurable session duration with activity-based reset, reactive `sessionStream()` for countdown timers and auto-lock UI.
- **Lockout system** — Configurable max attempts with persistent lockout state across app restarts.
- **Fallback chains** — Ordered fallback strategies (device credential, custom PIN, custom password) with pluggable `FallbackHandler` interface.
- **Token lifecycle integration** — `TokenLifecycle` interface for backend-agnostic token validation and refresh (Firebase, Supabase, REST JWT examples in docs).
- **Server policy enforcement** — `PolicyProvider` interface for runtime policy overrides (admin kill-switch, compliance rules, role-based session durations).
- **User preferences** — `BiometricPreferences` API for runtime settings (enable/disable biometric, remember me, session timeout override, reauth on resume).
- **Multi-user support** — All storage and sessions namespaced by `userId`. Multiple users on one device never share data.
- **Platform capability detection** — Rich `BiometricCapability` object with Face ID, Touch ID, strong/weak biometric detection.
- **Analytics events** — 29 event types emitted via `onEvent` callback for audit trails and analytics.
- **Authentication timeout** — Configurable timeout (default 60s) wrapping the entire auth flow.
- **Concurrency guard** — Atomic check-and-set prevents duplicate auth prompts.
- **Flutter UI layer** (optional) — `BiometricBuilder` for full state control, `BiometricGate` for simple gate pattern, `MaterialFallbackHandler` for Material Design fallback UI.
- **Testing utilities** — `BiometricShieldMock`, `FakeBiometricResult`, `FakeBiometricSession`, `FakeTokenStore`, `BiometricTestConfig`. No `WidgetsFlutterBinding` needed for core tests.
- **Example app** — 4 screens demonstrating gate-on-launch, widget gate, programmatic re-auth, and user preferences.

### Architecture decisions

- Instance-based, not static singleton — callers control scope via their DI strategy.
- `BiometricShieldInterface` abstract class enables dependency injection and mock substitution.
- UTC-consistent timestamps throughout (all `DateTime.now().toUtc()`).
- `LinkedHashMap` for deterministic insertion-order LRU eviction of stream controllers.
- `on Exception catch` (not bare `catch`) — programming errors propagate instead of being silently swallowed.
- TOCTOU prevention via local variable capture for nullable fields.
- `Map.unmodifiable()` for immutable event properties.

### Platform requirements

- iOS: Minimum deployment target iOS 12.0, requires `NSFaceIDUsageDescription` in Info.plist.
- Android: Minimum SDK 23, recommended 28+ for BiometricPrompt API.
- Dart SDK: ^3.10.8
- Flutter: >=3.29.0
