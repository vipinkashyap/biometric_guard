# BiometricShield Example

## Minimal setup (zero config)

```dart
import 'package:biometric_shield/biometric_shield.dart';

final shield = BiometricShield();

// After your server login succeeds, store the token once:
await shield.storeToken(serverJwt, userId: user.id);

// On subsequent launches, authenticate with biometrics:
final result = await shield.authenticate(
  reason: 'Unlock your account',
  userId: user.id,
);

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

## With backend integration

```dart
final shield = BiometricShield(
  config: BiometricConfig(
    tokenLifecycle: FirebaseTokenLifecycle(),    // auto-refresh tokens
    policyProvider: AppPolicyProvider(apiClient), // server-driven rules
    onEvent: (event) => analytics.track(event),  // audit trail
  ),
);
```

## Protect a screen with BiometricGate

```dart
import 'package:biometric_shield/biometric_shield_ui.dart';

BiometricGate(
  shield: shield,
  reason: 'Confirm to view health records',
  reauthOnResume: true,
  child: HealthRecordsScreen(),
  fallbackWidget: (result) => AccessDeniedScreen(),
)
```

## Testing

```dart
import 'package:biometric_shield/biometric_shield_testing.dart';

final mock = BiometricShieldMock(
  authenticateResult: FakeBiometricResult.success(token: 'test-jwt'),
);
final result = await mock.authenticate(reason: 'Test');
expect(result, isA<BiometricSuccess>());
```

See `example/lib/` for a full 7-screen demo app covering all integration patterns.
