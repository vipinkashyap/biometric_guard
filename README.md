# BiometricShield

A composable Flutter SDK that wraps biometric authentication into an injectable, namespace-aware layer with typed results, fallback chains, and audit event emission.

**BiometricShield is a bridge** — it sits between your app's existing auth system (Firebase, Supabase, Amplify, custom JWT, whatever) and the device's biometric hardware. You keep your backend. BiometricShield handles the local unlock layer: session management, lockout logic, fallback chains, token storage, and audit events.

## Why

Every Flutter app that adds Face ID or fingerprint ends up writing the same 500+ lines of scattered boilerplate. BiometricShield collapses it into one injectable instance with typed results and zero exceptions.

```dart
final shield = BiometricShield();

final result = await shield.authenticate(reason: 'Unlock your account');

result.when(
  success: (session, token) => proceedWithToken(token),
  tokenExpired: () => navigateToLogin(),
  cancelled: () => showCancelledState(),
  lockedOut: (until) => showLockoutScreen(until),
  unavailable: (reason, _) => fallbackToFullLogin(),
  invalidated: () => promptReenrollment(),
  fallbackSuccess: (method, session, token) => proceedWithToken(token),
  sessionValid: (session, token) => proceedWithToken(token),
  reauthenticationRequired: (reason) => navigateToLogin(),
  error: (message, cause) => showError(message),
);
```

No try/catch. No boolean checks. Every outcome is a named variant you pattern-match on.

## Install

```yaml
# pubspec.yaml
dependencies:
  biometric_shield: ^0.1.0
```

### Platform setup

**iOS** — Add to `ios/Runner/Info.plist`:
```xml
<key>NSFaceIDUsageDescription</key>
<string>This app uses Face ID to securely authenticate your identity.</string>
```
Minimum deployment target: iOS 12.0.

**Android** — Add to `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.USE_BIOMETRIC"/>
```
Minimum SDK: 23. Recommended: 28+ for BiometricPrompt (Class 2/3 distinction).

## Quick start

### 1. Create the instance

```dart
import 'package:biometric_shield/biometric_shield.dart';

// Works with zero config
final shield = BiometricShield();

// Or configure everything
final shield = BiometricShield(
  config: BiometricConfig(
    sessionDuration: const Duration(minutes: 15),
    maxAttempts: 3,
    lockoutDuration: const Duration(minutes: 5),
    fallbackChain: const [BiometricFallback.deviceCredential],
    onEvent: (event) => myAnalytics.track(event.type.name, event.properties),
  ),
);
```

Provide it to your app however you want — Provider, Riverpod, GetIt, or just a global. The SDK doesn't care.

### 2. Store a token after server login

```dart
// After your server auth succeeds (Firebase, Amplify, REST, etc.)
await shield.storeToken(serverJwt, userId: user.id);
```

### 3. Authenticate with biometrics

```dart
final result = await shield.authenticate(
  reason: 'Unlock your account',
  userId: user.id,
);

result.when(
  success: (session, token) => proceedWithToken(token),
  tokenExpired: () => navigateToLogin(),
  // ... handle all 10 outcomes
);
```

### 4. Protect screens with widgets (optional Flutter UI)

```dart
import 'package:biometric_shield/biometric_shield_ui.dart';

// Simple gate — shows child only after auth
BiometricGate(
  shield: shield,
  reason: 'Confirm to view health records',
  reauthOnResume: true,
  child: HealthRecordsScreen(),
  fallbackWidget: (result) => AccessDeniedScreen(),
)

// Full control — you handle every state
BiometricBuilder(
  shield: shield,
  reason: 'Confirm identity',
  builder: (context, state) => switch (state) {
    AuthIdle() || AuthAuthenticating() => LoadingIndicator(),
    AuthAuthenticated(:final token) => SecureContent(token: token),
    AuthFailed(:final result) => FailureScreen(result: result),
  },
)
```

## Architecture

```
┌─────────────────────────────────────────┐
│   Your App                              │
├─────────────────────────────────────────┤
│   UI Layer (optional Flutter)           │
│   BiometricBuilder · BiometricGate      │
│   MaterialFallbackHandler               │
├─────────────────────────────────────────┤
│   Core Layer (pure Dart, no Flutter)    │
│   BiometricShield · BiometricConfig     │
│   BiometricResult (sealed, 10 variants) │
├─────────────────────────────────────────┤
│   Subsystems                            │
│   SessionManager · LockoutManager       │
│   FallbackChain · CapabilityDetector    │
├─────────────────────────────────────────┤
│   Integration Points (you implement)    │
│   TokenLifecycle · PolicyProvider       │
│   FallbackHandler · TokenStoreInterface │
└─────────────────────────────────────────┘
```

The core is pure Dart with zero Flutter imports. All UI lives in the optional `biometric_shield_ui.dart` barrel. The core is testable without `WidgetsFlutterBinding`.

## Three imports, three purposes

```dart
import 'package:biometric_shield/biometric_shield.dart';          // Core (pure Dart)
import 'package:biometric_shield/biometric_shield_ui.dart';       // Flutter widgets
import 'package:biometric_shield/biometric_shield_testing.dart';  // Mocks & fakes
```

## Design principles

1. **Inject, don't replace.** Wraps the local unlock layer only. Never touches your server auth.
2. **Instance-based, not static.** You control scope and lifetime via your DI strategy.
3. **Pure Dart core, optional Flutter UI.** Core has zero widget imports.
4. **Typed results, no exceptions.** Sealed result type with `.when()` exhaustive matching.
5. **Namespace-aware.** Multiple users on one device never share sessions or tokens.
6. **Platform-honest.** Capability detection is a rich object, not a boolean.
7. **Reactive by default.** Session state via Streams for countdown timers and auto-lock.
8. **Inverted UI control.** The SDK never shows its own UI — it delegates to `FallbackHandler`.

## Backend integration

BiometricShield is backend-agnostic by design. Wire up any backend through two optional interfaces:

### TokenLifecycle — token refresh

```dart
class FirebaseTokenLifecycle implements TokenLifecycle {
  @override
  Future<TokenStatus> validate(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    final result = await user?.getIdTokenResult();
    if (result == null) return TokenStatus.missing;
    if (result.expirationTime!.isBefore(DateTime.now())) {
      return TokenStatus.expired;
    }
    return TokenStatus.valid;
  }

  @override
  Future<TokenRefreshResult> refresh(String expiredToken) async {
    final user = FirebaseAuth.instance.currentUser;
    final newToken = await user?.getIdToken(true);
    if (newToken == null) return TokenRefreshResult.reauthRequired();
    return TokenRefreshResult.success(newToken: newToken);
  }
}
```

### PolicyProvider — server-driven rules

```dart
class AppPolicyProvider implements PolicyProvider {
  final ApiClient api;
  AppPolicyProvider(this.api);

  @override
  Future<BiometricPolicy> getPolicy({String? userId}) async {
    try {
      final response = await api.get('/auth/biometric-policy');
      return BiometricPolicy(
        maxSessionDuration: Duration(minutes: response['max_session_min']),
        disabled: response['biometric_disabled'],
        disabledReason: response['disabled_reason'],
      );
    } catch (_) {
      return const BiometricPolicy(); // Fall back to local config
    }
  }
}
```

Wire them in:

```dart
final shield = BiometricShield(
  config: BiometricConfig(
    tokenLifecycle: FirebaseTokenLifecycle(),
    policyProvider: AppPolicyProvider(apiClient),
  ),
);
```

See [docs/INTEGRATION.md](docs/INTEGRATION.md) for complete Firebase, Supabase, and REST JWT walkthroughs.

## Common patterns

### Gate on app launch
```dart
final result = await shield.authenticate(reason: 'Unlock', userId: user.id);
```

### Protect a sensitive action
```dart
final result = await shield.authenticate(
  reason: 'Confirm transfer',
  requireFresh: true, // Ignores active session, forces re-auth
);
```

### Silent session check
```dart
final result = await shield.validateOrAuthenticate(reason: 'Verify session');
// Only prompts if session is expired
```

### Reactive session stream
```dart
StreamBuilder<BiometricSession?>(
  stream: shield.sessionStream(userId: user.id),
  builder: (context, snapshot) {
    final session = snapshot.data;
    if (session == null || session.isExpired) return LockScreen();
    return Text('Expires in ${session.remainingValidity.inMinutes}m');
  },
)
```

### Custom fallback handler
```dart
class MyPinHandler extends FallbackHandler {
  final BuildContext context;
  MyPinHandler(this.context);

  @override
  Future<FallbackResult> handleFallback({
    required BiometricFallback type,
    required String reason,
  }) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MyPinScreen(reason: reason)),
    );
    return ok == true ? FallbackResult.success : FallbackResult.cancelled;
  }
}
```

### User preferences (settings screen)
```dart
await shield.preferences.setBiometricEnabled(false, userId: user.id);
await shield.preferences.setSessionDurationOverride(
  Duration(minutes: 30), userId: user.id,
);
```

## Testing

The SDK ships with first-class testing support. No `WidgetsFlutterBinding` needed.

```dart
import 'package:biometric_shield/biometric_shield_testing.dart';

final mock = BiometricShieldMock(
  authenticateResult: FakeBiometricResult.success(token: 'test-jwt'),
);

// Pass to your widget or service under test
final result = await mock.authenticate(reason: 'Test');
expect(result, isA<BiometricSuccess>());

// Verify calls
expect(mock.authenticateCalls, hasLength(1));
expect(mock.authenticateCalls.first.reason, 'Test');
```

Available test helpers: `BiometricShieldMock`, `FakeBiometricResult`, `FakeBiometricSession`, `FakeTokenStore`, `BiometricTestConfig`.

## API reference

| Method | Description |
|--------|-------------|
| `authenticate()` | Full auth flow with fallbacks |
| `validateOrAuthenticate()` | Silent check, prompts only if expired |
| `hasValidSession()` | Boolean session check |
| `sessionStream()` | Reactive session state stream |
| `getCapability()` | Device biometric capabilities |
| `storeToken()` / `getToken()` | Secure token storage (per-user) |
| `clearSession()` / `clearAll()` | Session and data cleanup |
| `getLockoutState()` / `resetLockout()` | Lockout management |
| `onActivity()` | Extend session on interaction |
| `preferences` | User-facing settings (enable/disable, timeout, etc.) |
| `dispose()` / `disposeUser()` | Resource cleanup |

## What this SDK does NOT do

- Server authentication of any kind
- Token refresh against a server (unless you provide a `TokenLifecycle`)
- User registration or biometric enrollment
- OAuth / PKCE flows
- Push notification auth
- Navigation decisions
- Show any UI in response to results (that's your job via `.when()`)

## Dependencies

| Package | Purpose |
|---------|---------|
| `local_auth` | Platform biometric invocation |
| `flutter_secure_storage` | Default secure token storage |
| `crypto` | Session ID generation |
| `universal_io` | Cross-platform detection |

Four dependencies. That's it.

## License

MIT — see [LICENSE](LICENSE).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and contribution guidelines.

---

*Built by Vipin Kumar Kashyap — [SOUL.md](SOUL.md) is the design source of truth.*
