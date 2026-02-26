# BiometricShield Flutter SDK — SOUL.md

> This document is the source of truth for building the BiometricShield package.
> It defines what we own, what we don't, every public interface, every callback,
> and every integration point. When in doubt, refer here.

---

## What This SDK Is

BiometricShield is a Flutter SDK that wraps all biometric authentication concerns
into an injectable, composable layer. It is designed to be dropped into existing
apps — apps that already have their own auth (Amplify, Firebase, custom JWT, OAuth)
— without conflicting with them.

**We own:** local session management, fallback chain orchestration, lockout state,
audit event emission, and secure token storage.

**We do not own:** server authentication, token refresh, user identity, or anything
that requires a network call. All of those are caller responsibilities, exposed via
typed results.

---

## Core Design Principles

1. **Inject, don't replace.** The SDK wraps the local unlock layer only. It never
   touches server auth flows.

2. **Instance-based, not static.** The SDK is a provided instance, not a static
   singleton. Callers control scope and lifetime via their DI strategy (Provider,
   Riverpod, GetIt, manual injection — we don't care which).

3. **Pure Dart core, optional Flutter UI.** The core package (`biometric_shield`)
   has zero Flutter widget imports. All UI (BiometricBuilder, BiometricGate) lives
   in the optional Flutter layer. The core is testable without WidgetsFlutterBinding.

4. **Typed results, no exceptions.** All public methods return sealed result types.
   No try/catch required by callers.

5. **Namespace-aware.** Multiple users on one device must never share sessions or
   stored tokens. All storage is keyed by `userId`.

6. **Platform-honest.** Capability detection is exposed as a rich object, not a
   boolean. Callers can make informed decisions about what to show.

7. **Reactive by default.** Session state is exposed as a Stream so callers can
   build reactive UIs (countdown timers, auto-lock on expiry) without polling.

8. **Inverted UI control.** The SDK never shows its own UI for fallback flows.
   It *requests* a fallback via a `FallbackHandler` interface. The SDK ships a
   default `MaterialFallbackHandler`, but callers can swap in their own.

---

## Package Structure

```
biometric_shield/
├── lib/
│   ├── biometric_shield.dart              # Public barrel export (core only)
│   ├── biometric_shield_ui.dart           # Optional Flutter UI barrel export
│   ├── biometric_shield_testing.dart      # Testing utilities barrel export
│   ├── src/
│   │   ├── core/
│   │   │   ├── biometric_shield.dart      # Main instance-based entry point
│   │   │   ├── biometric_config.dart      # Configuration object (pure Dart)
│   │   │   ├── biometric_session.dart     # Session state model
│   │   │   └── biometric_result.dart      # Sealed result type
│   │   ├── platform/
│   │   │   ├── biometric_capability.dart  # Device capability model
│   │   │   ├── capability_detector.dart   # Platform-specific detection
│   │   │   ├── ios_handler.dart           # Face ID / Touch ID specifics
│   │   │   └── android_handler.dart       # Strong/weak biometric classes
│   │   ├── fallback/
│   │   │   ├── fallback_handler.dart      # Abstract interface for fallback UI
│   │   │   ├── fallback_chain.dart        # Composable fallback strategy
│   │   │   └── fallback_type.dart         # Enum of fallback types
│   │   ├── storage/
│   │   │   ├── biometric_token_store.dart # Default secure storage impl
│   │   │   └── token_store_interface.dart # Interface for custom storage
│   │   ├── session/
│   │   │   ├── session_manager.dart       # Session lifecycle management
│   │   │   └── lockout_manager.dart       # Attempt tracking + lockout
│   │   ├── analytics/
│   │   │   ├── biometric_event.dart       # Event model
│   │   │   └── event_type.dart            # Enum of all event types
│   │   ├── ui/                            # Optional Flutter layer
│   │   │   ├── biometric_builder.dart     # Reactive builder widget
│   │   │   ├── biometric_gate.dart        # Convenience gate widget
│   │   │   ├── material_fallback_handler.dart # Default Material fallback UI
│   │   │   ├── biometric_theme.dart       # Theming model
│   │   │   └── biometric_strings.dart     # Copy overrides
│   │   └── testing/
│   │       ├── biometric_shield_mock.dart # Full mock
│   │       ├── fake_biometric_session.dart
│   │       ├── fake_biometric_result.dart
│   │       ├── fake_token_store.dart
│   │       └── biometric_test_config.dart
```

---

## BiometricConfig — Full Interface

This is the single configuration object passed at construction. Every field
is optional — the SDK must work with zero configuration.

```dart
class BiometricConfig {

  // --- Session ---

  /// How long a successful auth remains valid before re-auth is required.
  /// Default: 15 minutes. Set to Duration.zero to require auth every time.
  final Duration sessionDuration;

  /// If true, session timer resets on any app interaction.
  /// If false, session expires based on wall clock from last auth.
  /// Default: true
  final bool sessionResetsOnActivity;

  // --- Lockout ---

  /// Max failed biometric attempts before lockout triggers.
  /// Default: 3
  final int maxAttempts;

  /// How long the lockout lasts after maxAttempts is exceeded.
  /// Default: 5 minutes
  final Duration lockoutDuration;

  /// If true, lockout state persists across app restarts.
  /// Default: true
  final bool persistLockout;

  // --- Fallback Chain ---

  /// Ordered list of fallbacks to attempt if biometric fails or is unavailable.
  /// Evaluated in order. Default: [BiometricFallback.deviceCredential]
  final List<BiometricFallback> fallbackChain;

  /// Handler that knows how to present fallback UI.
  /// If null, uses platform device credential prompt only.
  /// Inject a MaterialFallbackHandler or your own implementation.
  final FallbackHandler? fallbackHandler;

  // --- Storage ---

  /// Custom token store implementation.
  /// If null, uses default flutter_secure_storage implementation.
  final TokenStoreInterface? tokenStore;

  // --- Analytics ---

  /// Receives all audit events emitted by the SDK.
  /// Plug directly into your existing analytics or logging service.
  final void Function(BiometricEvent event)? onEvent;

  // --- Multi-user ---

  /// Default userId for storage namespacing.
  /// Can be overridden per-call on authenticate().
  /// If null, uses a device-scoped default (single user scenario).
  final String? defaultUserId;

  const BiometricConfig({
    this.sessionDuration = const Duration(minutes: 15),
    this.sessionResetsOnActivity = true,
    this.maxAttempts = 3,
    this.lockoutDuration = const Duration(minutes: 5),
    this.persistLockout = true,
    this.fallbackChain = const [BiometricFallback.deviceCredential],
    this.fallbackHandler,
    this.tokenStore,
    this.onEvent,
    this.defaultUserId,
  });
}
```

### What changed from v1

Removed from config (now caller responsibility via result handling):
- `onTokenExpired` — callers handle `BiometricResult.tokenExpired` in `.when()`
- `onLockoutStart/End` — callers react to `BiometricResult.lockedOut` or observe
  the session stream
- `onUserCancelled` — callers handle `BiometricResult.cancelled` in `.when()`
- `onBiometricInvalidated` — callers handle `BiometricResult.invalidated`
- `theme`, `strings`, `useCustomPromptUI`, `customPinBuilder` — moved to
  `MaterialFallbackHandler` in the optional UI layer

Rationale: the SDK should surface information, not dictate behavior. Callbacks
that redirect navigation or trigger full login flows are app-level concerns.
The sealed result type already carries all the information the caller needs.

---

## BiometricShield — Main Entry Point (Instance-Based)

```dart
class BiometricShield {

  /// Create a new BiometricShield instance.
  /// Callers provide this to their app via their DI strategy.
  BiometricShield({BiometricConfig config = const BiometricConfig()});

  /// Trigger full authentication flow including fallbacks if needed.
  ///
  /// [reason] — shown in platform biometric prompt
  /// [userId] — overrides config.defaultUserId for this call
  /// [requireFresh] — if true, ignores active session and re-authenticates
  Future<BiometricResult> authenticate({
    required String reason,
    String? userId,
    bool requireFresh = false,
  });

  /// Check if current session is still valid without triggering auth.
  /// Returns true if within session window.
  Future<bool> hasValidSession({String? userId});

  /// Validate session and re-authenticate if expired.
  /// Silent version — only triggers auth if session has expired.
  Future<BiometricResult> validateOrAuthenticate({
    required String reason,
    String? userId,
  });

  /// Reactive stream of session state changes for a user.
  /// Emits null when no active session exists.
  /// Use this to build countdown timers, auto-lock screens, etc.
  Stream<BiometricSession?> sessionStream({String? userId});

  /// Explicitly end the current session (e.g. on logout).
  Future<void> clearSession({String? userId});

  /// Clear all stored tokens and session state for a user.
  Future<void> clearAll({String? userId});

  /// Detect what biometric capabilities this device has.
  Future<BiometricCapability> getCapability();

  /// Store a token securely, namespaced to userId.
  /// Call this after your server auth succeeds on first login.
  Future<void> storeToken(String token, {String? userId});

  /// Retrieve the stored token after successful biometric auth.
  Future<String?> getToken({String? userId});

  /// Check if the user is currently locked out.
  Future<LockoutState> getLockoutState({String? userId});

  /// Manually reset lockout (e.g. after admin override).
  Future<void> resetLockout({String? userId});

  /// Notify the SDK that the user interacted with the app.
  /// Extends session if sessionResetsOnActivity is true.
  void onActivity({String? userId});

  /// Dispose resources (stream controllers, timers).
  void dispose();
}
```

### Key differences from v1

- **Instance, not static.** `BiometricShield(config: config)` instead of
  `BiometricShield.configure(config)`. The caller owns the lifecycle.
- **No BuildContext.** The core never touches Flutter widgets. Fallback UI
  is handled by the injected `FallbackHandler`.
- **sessionStream()** — reactive session observation replaces polling.
- **onActivity()** — explicit activity signal instead of implicit widget lifecycle.
- **dispose()** — clean resource management.

---

## FallbackHandler — Inverted UI Control

The SDK never shows its own UI. Instead, it delegates fallback presentation
to a handler interface. The SDK ships `MaterialFallbackHandler` as a convenience.

```dart
/// Interface for handling fallback authentication UI.
///
/// Implement this to control how custom PIN, password, or other
/// fallback UI is presented to the user.
abstract class FallbackHandler {

  /// Present a fallback authentication flow to the user.
  ///
  /// [type] — which fallback to show
  /// [callbacks] — call onSuccess/onCancel/onFailure to communicate outcome
  ///
  /// Returns a Future that completes with the fallback result.
  Future<FallbackResult> handleFallback({
    required BiometricFallback type,
    required String reason,
  });
}

/// Result of a fallback attempt.
enum FallbackResult {
  success,
  failed,
  cancelled,
}
```

The default `MaterialFallbackHandler` (in the UI layer) does what the old
`FallbackChainExecutor` did — shows bottom sheets and overlays. But callers
can now inject any UI they want without touching SDK internals.

---

## BiometricResult — Sealed Result Type

Unchanged from v1. All authentication outcomes are expressed here.

```dart
sealed class BiometricResult {
  const factory BiometricResult.success({...}) = BiometricSuccess;
  const factory BiometricResult.fallbackSuccess({...}) = BiometricFallbackSuccess;
  const factory BiometricResult.sessionValid({...}) = BiometricSessionValid;
  const factory BiometricResult.tokenExpired() = BiometricTokenExpired;
  const factory BiometricResult.cancelled() = BiometricCancelled;
  const factory BiometricResult.lockedOut({required DateTime lockedUntil}) = BiometricLockedOut;
  const factory BiometricResult.unavailable({required BiometricUnavailableReason reason}) = BiometricUnavailable;
  const factory BiometricResult.invalidated() = BiometricInvalidated;
  const factory BiometricResult.error({required String message, required Object? cause}) = BiometricError;

  T when<T>({...}); // Pattern matching on all variants
}
```

---

## BiometricBuilder — Reactive Widget (Optional UI Layer)

Replaces BiometricGate as the primary widget pattern. More flexible —
the caller controls all UI states.

```dart
/// Reactive widget that rebuilds when auth state changes.
///
/// Like FutureBuilder but for biometric auth. The caller controls
/// every visual state — the SDK provides data, not opinions.
class BiometricBuilder extends StatefulWidget {
  /// The BiometricShield instance to use.
  final BiometricShield shield;

  /// Reason shown in the biometric prompt.
  final String reason;

  /// Override userId for this builder.
  final String? userId;

  /// If true, triggers re-authentication when app resumes from background.
  final bool reauthOnResume;

  /// Builder that receives the current auth state.
  final Widget Function(BuildContext context, AuthState state) builder;

  /// If true, auto-triggers authentication on mount.
  /// If false, waits for the caller to call state.authenticate().
  final bool autoAuthenticate;
}

/// The auth state passed to the builder.
sealed class AuthState {
  const factory AuthState.idle() = AuthIdle;
  const factory AuthState.authenticating() = AuthAuthenticating;
  const factory AuthState.authenticated({
    required BiometricSession session,
    required String? token,
  }) = AuthAuthenticated;
  const factory AuthState.failed({required BiometricResult result}) = AuthFailed;
}
```

### Usage

```dart
BiometricBuilder(
  shield: shield,
  reason: 'Confirm to view health records',
  userId: user.id,
  reauthOnResume: true,
  builder: (context, state) => switch (state) {
    AuthIdle() => MyCustomIdleScreen(),
    AuthAuthenticating() => MyCustomLoadingScreen(),
    AuthAuthenticated(:final session, :final token) => HealthRecordsScreen(),
    AuthFailed(:final result) => MyCustomFailedScreen(result: result),
  },
)
```

---

## BiometricGate — Convenience Widget (Optional UI Layer)

Still available as a simpler alternative to BiometricBuilder for the
common "show child after auth" pattern. Uses BiometricBuilder internally.

```dart
class BiometricGate extends StatelessWidget {
  final BiometricShield shield;
  final Widget child;
  final String reason;
  final Widget? loadingWidget;
  final Widget Function(BiometricResult result)? fallbackWidget;
  final void Function(BiometricResult result)? onAuthenticated;
  final bool reauthOnResume;
  final String? userId;
}
```

---

## MaterialFallbackHandler — Default Fallback UI (Optional UI Layer)

Ships in the UI layer. Presents Material bottom sheets for custom PIN/password.

```dart
class MaterialFallbackHandler extends FallbackHandler {
  /// The BuildContext to use for showing bottom sheets.
  final BuildContext context;

  /// Builder for custom PIN/password UI.
  final CustomFallbackBuilder? customBuilder;

  /// Visual theme overrides.
  final BiometricTheme? theme;

  /// String overrides.
  final BiometricStrings? strings;

  MaterialFallbackHandler({
    required this.context,
    this.customBuilder,
    this.theme,
    this.strings,
  });
}
```

This is where all the UI opinions live — theme, strings, bottom sheet styling.
The core SDK is blissfully unaware of any of it.

---

## Everything Else — Unchanged from v1

These types remain identical:

- `BiometricCapability` — device detection model
- `BiometricSession` — session model with expiry tracking
- `BiometricAuthMethod` — enum of auth methods
- `TokenStoreInterface` — custom storage interface
- `BiometricTokenStore` — default flutter_secure_storage impl
- `LockoutState` — lockout query result
- `BiometricEvent` + `BiometricEventType` — audit trail
- `BiometricFallback` — fallback type enum
- `BiometricTheme` + `BiometricStrings` — UI customization (moved to UI layer)

---

## Integration Patterns

### Pattern 1 — Instance-Based Setup

```dart
// Create and provide the instance however you want.
// Here using a simple global, but Provider/Riverpod/GetIt all work.
final shield = BiometricShield(BiometricConfig(
  sessionDuration: Duration(minutes: 15),
  onEvent: (event) => myAnalytics.track(event.type.name, event.properties),
));

// After server login succeeds, store the token once:
await shield.storeToken(serverJwt, userId: user.id);

// On every subsequent launch:
final result = await shield.authenticate(
  reason: 'Unlock your account',
  userId: user.id,
);

result.when(
  success: (session, token) => proceedWithToken(token),
  fallbackSuccess: (method, session, token) => proceedWithToken(token),
  sessionValid: (session, token) => proceedWithToken(token),
  tokenExpired: () => navigateToLogin(),     // caller decides what to do
  cancelled: () => showCancelledState(),
  lockedOut: (until) => showLockoutScreen(until),
  unavailable: (reason) => fallbackToFullLogin(),
  invalidated: () => promptReenrollment(),
  error: (message, cause) => showError(message),
);
```

### Pattern 2 — Reactive Session Observation

```dart
// Build a reactive session indicator
StreamBuilder<BiometricSession?>(
  stream: shield.sessionStream(userId: user.id),
  builder: (context, snapshot) {
    final session = snapshot.data;
    if (session == null || session.isExpired) {
      return LockScreen();
    }
    return Text('Session expires in ${session.remainingValidity.inMinutes}m');
  },
)
```

### Pattern 3 — BiometricBuilder Widget

```dart
BiometricBuilder(
  shield: shield,
  reason: 'Confirm to view health records',
  userId: currentUser.id,
  reauthOnResume: true,
  builder: (context, state) => switch (state) {
    AuthIdle() || AuthAuthenticating() => LoadingIndicator(),
    AuthAuthenticated() => HealthRecordsScreen(),
    AuthFailed(:final result) => AccessDeniedScreen(result: result),
  },
)
```

### Pattern 4 — Custom Fallback Handler

```dart
// For apps that want full control over fallback UI
class MyCustomFallbackHandler extends FallbackHandler {
  final BuildContext context;

  MyCustomFallbackHandler(this.context);

  @override
  Future<FallbackResult> handleFallback({
    required BiometricFallback type,
    required String reason,
  }) async {
    // Show your own full-screen PIN entry, custom dialog, etc.
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MyPinScreen(reason: reason)),
    );
    return result == true ? FallbackResult.success : FallbackResult.cancelled;
  }
}

// Wire it up
final shield = BiometricShield(BiometricConfig(
  fallbackChain: [BiometricFallback.customPin],
  fallbackHandler: MyCustomFallbackHandler(context),
));
```

### Pattern 5 — AWS Amplify Integration

```dart
// Same as before, but using instance methods
final shield = BiometricShield();

// After Amplify login
if (cognitoResult.isSignedIn) {
  await shield.storeToken('amplify_active', userId: email);
}

// Subsequent launches
final result = await shield.authenticate(
  reason: 'Unlock your account',
  userId: email,
);
// ... handle result.when() as before
```

---

## What We Explicitly Do Not Handle

- Server authentication of any kind
- Token refresh against a server
- User registration or biometric enrollment prompts (we detect + report, not enroll)
- OAuth / PKCE flows
- Multi-factor auth beyond biometric + fallback
- Push notification–based auth
- Anything requiring a network call
- Navigation decisions (login redirects, screen transitions)
- Showing any UI in response to results (caller's job via result.when())

---

## Dependencies

| Package | Purpose |
|---|---|
| `local_auth` | Platform biometric invocation |
| `flutter_secure_storage` | Default token storage implementation |
| `crypto` | Session ID generation |

No other dependencies. Keep it lean.

---

## Platform Requirements

**iOS**
- Minimum deployment target: iOS 12.0
- Required `Info.plist` key: `NSFaceIDUsageDescription`
- Keychain access group configuration may be needed for extensions

**Android**
- Minimum SDK: 23
- Recommended: SDK 28+ for `BiometricPrompt` API (Class 2/3 distinction)
- Required manifest permission: `USE_BIOMETRIC`
- Legacy permission for SDK < 28: `USE_FINGERPRINT`

---

## Testing Strategy

Every public method must have a testable interface. The SDK ships with:

- `BiometricShieldMock` — a mock implementation of the full API surface
- `FakeBiometricResult` helpers — prebuilt result factories for common scenarios
- `FakeBiometricSession` — session presets (active, expired, aboutToExpire)
- `FakeTokenStore` — in-memory token store for assertions
- `BiometricTestConfig` — config preset that disables all persistence

```dart
// In test setup — no WidgetsFlutterBinding needed for core tests
final mock = BiometricShieldMock(
  authenticateResult: BiometricResult.success(
    session: FakeBiometricSession.active(),
    token: 'fake-token',
  ),
);

// Pass mock to your widget/service under test
final result = await mock.authenticate(reason: 'Test');
expect(result, isA<BiometricSuccess>());
```

---

## SDK Distribution Plan

Full API surface on pub.dev (OSS, MIT license). Monetize on hosted services,
not SDK feature gates:

- **Open source (pub.dev):** Full SDK — biometric auth, capability detection,
  typed results, configurable sessions, fallback chains, BiometricBuilder,
  BiometricGate, audit events, multi-user, mock testing helpers.

- **BiometricShield Cloud (SaaS, paid):** HIPAA-compliant audit log aggregation,
  compliance reporting dashboard, remote lockout/wipe, device fleet analytics,
  anomaly detection (unusual auth patterns), SLA support.

Rationale: feature-gating the SDK kills pub.dev adoption. Every successful
Flutter SDK monetizes on volume, support, or dashboard features — not by
withholding API surface from the free tier.

---

*Last updated: February 2026*
*Owner: Vipin — BiometricShield SDK*
