# Backend Integration Guide

BiometricShield is backend-agnostic by design. It owns the local biometric layer — session management, lockout, fallback chains, token storage. Your backend owns server auth, token refresh, and user identity.

The bridge between them is two optional interfaces: `TokenLifecycle` and `PolicyProvider`.

## TokenLifecycle — automatic token validation and refresh

When you provide a `TokenLifecycle`, the SDK will automatically validate stored tokens after biometric auth succeeds and refresh them if expired. Without it, the SDK simply returns whatever is in storage and you handle expiry yourself.

### Firebase Auth

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:biometric_shield/biometric_shield.dart';

class FirebaseTokenLifecycle implements TokenLifecycle {
  @override
  Future<TokenStatus> validate(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return TokenStatus.missing;

      final result = await user.getIdTokenResult();
      if (result.expirationTime!.isBefore(DateTime.now().toUtc())) {
        return TokenStatus.expired;
      }
      return TokenStatus.valid;
    } catch (_) {
      return TokenStatus.invalid;
    }
  }

  @override
  Future<TokenRefreshResult> refresh(String expiredToken) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return const TokenRefreshResult.reauthRequired();

      // Force refresh the Firebase ID token
      final newToken = await user.getIdToken(true);
      if (newToken == null) return const TokenRefreshResult.reauthRequired();

      return TokenRefreshResult.success(newToken: newToken);
    } catch (e) {
      return TokenRefreshResult.failed(reason: e.toString());
    }
  }
}
```

Wire it up:

```dart
final shield = BiometricShield(
  config: BiometricConfig(
    tokenLifecycle: FirebaseTokenLifecycle(),
    onEvent: (event) => FirebaseAnalytics.instance.logEvent(
      name: 'biometric_${event.type.name}',
      parameters: event.properties.cast<String, Object>(),
    ),
  ),
);

// After Firebase sign-in:
final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
  email: email,
  password: password,
);
final idToken = await credential.user!.getIdToken();
await shield.storeToken(idToken!, userId: credential.user!.uid);
```

### Supabase

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:biometric_shield/biometric_shield.dart';

class SupabaseTokenLifecycle implements TokenLifecycle {
  final SupabaseClient client;
  SupabaseTokenLifecycle(this.client);

  @override
  Future<TokenStatus> validate(String token) async {
    final session = client.auth.currentSession;
    if (session == null) return TokenStatus.missing;
    if (session.isExpired) return TokenStatus.expired;
    return TokenStatus.valid;
  }

  @override
  Future<TokenRefreshResult> refresh(String expiredToken) async {
    try {
      final response = await client.auth.refreshSession();
      final session = response.session;
      if (session == null) return const TokenRefreshResult.reauthRequired();

      return TokenRefreshResult.success(
        newToken: session.accessToken,
        metadata: {
          'refresh_token': session.refreshToken ?? '',
          'expires_at': session.expiresAt?.toString() ?? '',
        },
      );
    } catch (e) {
      if (e.toString().contains('refresh_token_not_found')) {
        return const TokenRefreshResult.reauthRequired();
      }
      return TokenRefreshResult.failed(reason: e.toString());
    }
  }
}
```

Wire it up:

```dart
final supabase = Supabase.instance.client;

final shield = BiometricShield(
  config: BiometricConfig(
    tokenLifecycle: SupabaseTokenLifecycle(supabase),
  ),
);

// After Supabase sign-in:
final response = await supabase.auth.signInWithPassword(
  email: email,
  password: password,
);
await shield.storeToken(
  response.session!.accessToken,
  userId: response.user!.id,
);
```

### REST API with JWT + refresh token

```dart
import 'package:biometric_shield/biometric_shield.dart';

class JwtTokenLifecycle implements TokenLifecycle {
  final ApiClient api;
  final String Function() getRefreshToken;
  final void Function(String) saveRefreshToken;

  JwtTokenLifecycle({
    required this.api,
    required this.getRefreshToken,
    required this.saveRefreshToken,
  });

  @override
  Future<TokenStatus> validate(String token) async {
    // Decode JWT locally — no network call needed
    try {
      final parts = token.split('.');
      if (parts.length != 3) return TokenStatus.invalid;

      // Decode payload (base64)
      final payload = _decodeBase64(parts[1]);
      final exp = payload['exp'] as int?;
      if (exp == null) return TokenStatus.invalid;

      final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      if (expiry.isBefore(DateTime.now().toUtc())) {
        return TokenStatus.expired;
      }
      return TokenStatus.valid;
    } catch (_) {
      return TokenStatus.invalid;
    }
  }

  @override
  Future<TokenRefreshResult> refresh(String expiredToken) async {
    try {
      final refreshToken = getRefreshToken();
      final response = await api.post('/auth/refresh', body: {
        'refresh_token': refreshToken,
      });

      if (response.statusCode == 200) {
        final newRefresh = response.body['refresh_token'] as String?;
        if (newRefresh != null) saveRefreshToken(newRefresh);

        return TokenRefreshResult.success(
          newToken: response.body['access_token'] as String,
          metadata: {
            if (newRefresh != null) 'refresh_token': newRefresh,
          },
        );
      }

      // 401 = refresh token expired, user must log in again
      if (response.statusCode == 401) {
        return const TokenRefreshResult.reauthRequired();
      }

      return TokenRefreshResult.failed(
        reason: 'Server returned ${response.statusCode}',
      );
    } catch (e) {
      return TokenRefreshResult.failed(reason: e.toString());
    }
  }

  Map<String, dynamic> _decodeBase64(String str) {
    // Base64url decode and parse JSON
    var output = str.replaceAll('-', '+').replaceAll('_', '/');
    switch (output.length % 4) {
      case 2: output += '=='; break;
      case 3: output += '='; break;
    }
    // In production, use dart:convert
    throw UnimplementedError('Use a proper JWT library');
  }
}
```

### AWS Amplify

```dart
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:biometric_shield/biometric_shield.dart';

class AmplifyTokenLifecycle implements TokenLifecycle {
  @override
  Future<TokenStatus> validate(String token) async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      if (!session.isSignedIn) return TokenStatus.missing;
      // Amplify handles token refresh internally, so if we have
      // a session, the token is valid
      return TokenStatus.valid;
    } catch (_) {
      return TokenStatus.invalid;
    }
  }

  @override
  Future<TokenRefreshResult> refresh(String expiredToken) async {
    try {
      // Amplify's fetchAuthSession auto-refreshes tokens
      final session = await Amplify.Auth.fetchAuthSession();
      if (!session.isSignedIn) {
        return const TokenRefreshResult.reauthRequired();
      }
      // The token marker stays the same; Amplify manages the actual tokens
      return const TokenRefreshResult.success(newToken: 'amplify_active');
    } catch (_) {
      return const TokenRefreshResult.reauthRequired();
    }
  }
}
```

## PolicyProvider — server-driven security rules

`PolicyProvider` lets your backend enforce biometric rules at runtime. The SDK calls `getPolicy()` before each authentication and merges the server policy with local config using the most restrictive values.

### Typical implementation

```dart
class AppPolicyProvider implements PolicyProvider {
  final ApiClient api;
  BiometricPolicy? _cached;
  DateTime? _cachedAt;

  AppPolicyProvider(this.api);

  @override
  Future<BiometricPolicy> getPolicy({String? userId}) async {
    // Cache for 5 minutes to avoid hitting the server every auth
    if (_cached != null &&
        _cachedAt != null &&
        DateTime.now().toUtc().difference(_cachedAt!) <
            const Duration(minutes: 5)) {
      return _cached!;
    }

    try {
      final response = await api.get(
        '/auth/biometric-policy',
        headers: {'X-User-Id': userId ?? ''},
      );

      _cached = BiometricPolicy(
        requireBiometric: response['require_biometric'] as bool?,
        maxSessionDuration: response['max_session_minutes'] != null
            ? Duration(minutes: response['max_session_minutes'] as int)
            : null,
        maxAttempts: response['max_attempts'] as int?,
        lockoutDuration: response['lockout_minutes'] != null
            ? Duration(minutes: response['lockout_minutes'] as int)
            : null,
        forceReauthOnResume: response['force_reauth_resume'] as bool?,
        disabled: response['biometric_disabled'] as bool?,
        disabledReason: response['disabled_reason'] as String?,
      );
      _cachedAt = DateTime.now().toUtc();
      return _cached!;
    } catch (_) {
      // Network failure — fall back to local config (all nulls)
      return const BiometricPolicy();
    }
  }
}
```

### Use cases

**Kill-switch during maintenance:**
```json
{ "biometric_disabled": true, "disabled_reason": "Under maintenance until 3 PM" }
```
The SDK returns `BiometricResult.unavailable(reason: disabledByPolicy)`.

**Tighter sessions after a breach:**
```json
{ "max_session_minutes": 5, "force_reauth_resume": true }
```
Sessions last 5 minutes max, and the user must re-auth every time they return to the app.

**Role-based security:**
```json
{ "max_attempts": 1, "lockout_minutes": 30, "require_biometric": true }
```
High-privilege users get stricter lockout rules and can't opt out of biometric.

## Custom FallbackHandler

When the built-in `MaterialFallbackHandler` doesn't match your design system, implement `FallbackHandler` directly:

```dart
class BrandedPinHandler extends FallbackHandler {
  final BuildContext context;
  BrandedPinHandler(this.context);

  @override
  Future<FallbackResult> handleFallback({
    required BiometricFallback type,
    required String reason,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => YourBrandedPinDialog(reason: reason),
    );

    if (result == null) return FallbackResult.cancelled;
    return result ? FallbackResult.success : FallbackResult.failed;
  }
}
```

Wire it up:

```dart
final shield = BiometricShield(
  config: BiometricConfig(
    fallbackChain: [
      BiometricFallback.deviceCredential,
      BiometricFallback.customPin,
    ],
    fallbackHandler: BrandedPinHandler(context),
  ),
);
```

## Custom TokenStore

Replace the default `flutter_secure_storage` implementation:

```dart
class EncryptedBoxTokenStore implements TokenStoreInterface {
  final Box<String> _box; // Hive encrypted box, for example

  EncryptedBoxTokenStore(this._box);

  @override
  Future<void> store(String token, {required String userId}) async {
    await _box.put('token_$userId', token);
  }

  @override
  Future<String?> retrieve({required String userId}) async {
    return _box.get('token_$userId');
  }

  @override
  Future<void> delete({required String userId}) async {
    await _box.delete('token_$userId');
  }

  @override
  Future<void> deleteAll() async {
    await _box.clear();
  }
}
```

## Analytics / HIPAA audit trail

Pipe all 29 event types to your analytics service:

```dart
final shield = BiometricShield(
  config: BiometricConfig(
    onEvent: (event) {
      // Firebase Analytics
      FirebaseAnalytics.instance.logEvent(
        name: 'biometric_${event.type.name}',
        parameters: {
          'user_id': event.userId,
          'timestamp': event.timestamp.toIso8601String(),
          ...event.properties.cast<String, Object>(),
        },
      );

      // Or your HIPAA-compliant audit log
      auditLogger.log(
        action: event.type.name,
        userId: event.userId,
        metadata: event.properties,
      );
    },
  ),
);
```

Event types include: `authStarted`, `authSuccess`, `authFailed`, `authCancelled`, `fallbackStarted`, `fallbackSuccess`, `sessionCreated`, `sessionExpired`, `lockoutStarted`, `lockoutEnded`, `tokenStored`, `tokenRetrieved`, `tokenRefreshed`, `tokenRefreshFailed`, `policyFetched`, and more.
