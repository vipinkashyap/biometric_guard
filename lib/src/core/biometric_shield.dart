import 'package:local_auth/local_auth.dart';

import 'biometric_config.dart';
import 'biometric_preferences.dart';
import 'biometric_result.dart';
import 'biometric_session.dart';
import 'policy_provider.dart';
import 'token_lifecycle.dart';
import '../platform/biometric_capability.dart';
import '../platform/capability_detector.dart';
import '../platform/ios_handler.dart';
import '../platform/android_handler.dart';
import '../fallback/fallback_chain.dart';
import '../session/session_manager.dart';
import '../session/lockout_manager.dart';
import '../session/lockout_state.dart';
import '../analytics/biometric_event.dart';
import '../analytics/event_type.dart';

/// Main entry point for the BiometricShield SDK.
///
/// Create an instance with [BiometricShield()] and call methods like
/// [authenticate], [hasValidSession], [storeToken], etc. throughout your app.
///
/// Instance-based for composability and testing. No Flutter imports — pure Dart.
///
/// ## Quick start:
///
/// ```dart
/// // Minimal — works with zero config
/// final shield = BiometricShield();
///
/// // With backend integration
/// final shield = BiometricShield(BiometricConfig(
///   tokenLifecycle: MyFirebaseTokenLifecycle(),
///   policyProvider: MyApiPolicyProvider(apiClient),
///   onEvent: (event) => analytics.track(event),
/// ));
/// ```
///
/// ## Entry points for authentication:
///
/// | Pattern | Method | When to use |
/// |---------|--------|-------------|
/// | Cold launch | `authenticate()` | App startup, auto-auth |
/// | Login tap | `authenticate(requireFresh: true)` | Explicit user action |
/// | Session gate | `validateOrAuthenticate()` | Protected screens |
/// | Sensitive action | `authenticate(requireFresh: true)` | Transfers, deletes |
/// | Background resume | Handled by [BiometricBuilder] | App lifecycle |
///
/// ## Settings & preferences:
///
/// Use [preferences] to manage user-facing settings:
/// - Enable/disable biometric
/// - Remember me (session persistence)
/// - Custom session timeout
/// - Reauth on resume
class BiometricShield {
  final BiometricConfig config;
  late final SessionManager _sessionManager;
  late final LockoutManager _lockoutManager;
  late final CapabilityDetector _capabilityDetector;
  late final IOSHandler _iosHandler;
  late final AndroidHandler _androidHandler;
  late final FallbackChainExecutor _fallbackChain;
  late final BiometricPreferences _preferences;

  /// Create a new BiometricShield instance with optional config.
  BiometricShield({BiometricConfig config = const BiometricConfig()})
      : config = config {
    _sessionManager = SessionManager(config: config);
    _lockoutManager = LockoutManager(config: config);
    _capabilityDetector = CapabilityDetector();
    _iosHandler = IOSHandler();
    _androidHandler = AndroidHandler();
    _fallbackChain = FallbackChainExecutor(config: config);
    _preferences = BiometricPreferences(
      store: config.tokenStore,
      defaultUserId: config.defaultUserId,
    );
  }

  /// User-facing preferences (remember me, enable/disable, etc).
  ///
  /// Access this to read/write preferences from your settings screen
  /// or login screen. Preferences are persisted and namespaced per user.
  BiometricPreferences get preferences => _preferences;

  // ═══════════════════════════════════════════════════════════
  // Authentication
  // ═══════════════════════════════════════════════════════════

  /// Trigger full authentication flow including fallbacks if needed.
  ///
  /// [reason] — shown in platform biometric prompt.
  /// [userId] — overrides [BiometricConfig.defaultUserId] for this call.
  /// [requireFresh] — if true, ignores active session and re-authenticates.
  ///
  /// ## Flow:
  /// 1. Check server policy (if [PolicyProvider] configured)
  /// 2. Check user preferences (biometric enabled?)
  /// 3. Check lockout state
  /// 4. Check existing session (unless [requireFresh])
  /// 5. Attempt biometric → fallback chain on failure
  /// 6. Validate & refresh token (if [TokenLifecycle] configured)
  /// 7. Create session → return result
  Future<BiometricResult> authenticate({
    required String reason,
    String? userId,
    bool requireFresh = false,
  }) async {
    // 1. Check server policy
    final policy = await _resolvePolicy(userId: userId);
    if (policy?.disabled == true) {
      return BiometricResult.unavailable(
        reason: BiometricUnavailableReason.disabledByPolicy,
        message: policy?.disabledReason,
      );
    }

    // 2. Check user preferences
    final biometricEnabled = await _preferences.isBiometricEnabled(
      userId: userId,
    );
    if (!biometricEnabled && (policy?.requireBiometric != true)) {
      // User disabled biometric, server doesn't force it — go to fallback
      return _handleUnavailable(
        reason: reason,
        userId: userId,
        unavailableReason: BiometricUnavailableReason.notSupported,
      );
    }

    // 3. Check lockout state (use effective max attempts from policy)
    final lockoutState = await _lockoutManager.getLockoutState(userId: userId);
    if (lockoutState.isLockedOut) {
      _emitEvent(BiometricEventType.authFailed, userId, properties: {
        'reason': 'locked_out',
      });
      return BiometricResult.lockedOut(
        lockedUntil: lockoutState.lockedUntil!,
      );
    }

    // 4. Check existing session (unless requireFresh)
    if (!requireFresh) {
      final activeSession =
          await _sessionManager.getActiveSession(userId: userId);
      if (activeSession != null && !activeSession.isExpired) {
        final token = await _resolveToken(userId: userId);
        return token;
      }
    }

    // 5. Emit auth attempted event
    _emitEvent(BiometricEventType.authAttempted, userId);

    // 6. Attempt biometric authentication
    final biometricResult = await _attemptBiometric(reason: reason);

    return switch (biometricResult) {
      _PlatformAuthResult.success => await _handleSuccess(
          userId: userId,
          method: await _detectMethod(),
        ),
      _PlatformAuthResult.failed => await _handleFailure(
          reason: reason,
          userId: userId,
        ),
      _PlatformAuthResult.cancelled => _handleCancelled(userId),
      _PlatformAuthResult.notAvailable ||
      _PlatformAuthResult.notEnrolled =>
        await _handleUnavailable(
          reason: reason,
          userId: userId,
          unavailableReason: biometricResult == _PlatformAuthResult.notEnrolled
              ? BiometricUnavailableReason.notEnrolled
              : BiometricUnavailableReason.notSupported,
        ),
      _PlatformAuthResult.passcodeNotSet => const BiometricResult.unavailable(
          reason: BiometricUnavailableReason.passcodeNotSet,
        ),
      _PlatformAuthResult.lockedOut => const BiometricResult.unavailable(
          reason: BiometricUnavailableReason.temporarilyUnavailable,
        ),
      _PlatformAuthResult.invalidated => _handleInvalidated(userId),
      _PlatformAuthResult.error => const BiometricResult.error(
          message: 'Platform authentication error',
          cause: null,
        ),
    };
  }

  /// Check if current session is still valid without triggering auth.
  Future<bool> hasValidSession({String? userId}) async {
    return _sessionManager.hasValidSession(userId: userId);
  }

  /// Validate session and re-authenticate if expired.
  /// Silent version — only shows UI if session has expired.
  Future<BiometricResult> validateOrAuthenticate({
    required String reason,
    String? userId,
  }) async {
    final activeSession =
        await _sessionManager.getActiveSession(userId: userId);
    if (activeSession != null && !activeSession.isExpired) {
      return _resolveToken(userId: userId);
    }

    return authenticate(
      reason: reason,
      userId: userId,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Session Management
  // ═══════════════════════════════════════════════════════════

  /// Explicitly end the current session (e.g. on logout).
  ///
  /// If [BiometricPreferences.isRememberMeEnabled] is false, this also
  /// clears the stored token (memory-only session).
  Future<void> clearSession({String? userId}) async {
    await _sessionManager.clearSession(userId: userId);

    // If remember me is disabled, also clear the stored token
    final rememberMe = await _preferences.isRememberMeEnabled(userId: userId);
    if (!rememberMe) {
      await _sessionManager.storeToken('', userId: userId);
    }
  }

  /// Clear all stored tokens and session state for a user.
  Future<void> clearAll({String? userId}) async {
    await _sessionManager.clearAll(userId: userId);
  }

  /// Get a stream of session state changes for a user.
  ///
  /// Emits the current session (or null if none) immediately, then emits
  /// updates whenever the session changes (created, cleared, or expired).
  Stream<BiometricSession?> sessionStream({String? userId}) {
    return _sessionManager.sessionStream(userId: userId);
  }

  /// Notify the SDK that the user has performed an activity.
  ///
  /// If [BiometricConfig.sessionResetsOnActivity] is true, this extends
  /// the session timeout. Otherwise, no effect.
  void onActivity({String? userId}) {
    _sessionManager.onActivity(userId: userId);
  }

  // ═══════════════════════════════════════════════════════════
  // Device Capabilities
  // ═══════════════════════════════════════════════════════════

  /// Detect what biometric capabilities this device has.
  Future<BiometricCapability> getCapability() async {
    final capability = await _capabilityDetector.detect();
    _emitEvent(BiometricEventType.capabilityChecked, null, properties: {
      'hasBiometric': capability.hasBiometric,
      'isEnrolled': capability.isEnrolled,
      'label': capability.biometricLabel,
    });
    return capability;
  }

  // ═══════════════════════════════════════════════════════════
  // Token Management
  // ═══════════════════════════════════════════════════════════

  /// Store a token securely, namespaced to userId.
  ///
  /// Call this after your server auth succeeds on first login.
  /// If [BiometricPreferences.isRememberMeEnabled] is false, the token
  /// is still stored but will be cleared when the session ends.
  Future<void> storeToken(String token, {String? userId}) async {
    await _sessionManager.storeToken(token, userId: userId);
  }

  /// Retrieve the stored token after successful biometric auth.
  Future<String?> getToken({String? userId}) async {
    return _sessionManager.getToken(userId: userId);
  }

  // ═══════════════════════════════════════════════════════════
  // Lockout Management
  // ═══════════════════════════════════════════════════════════

  /// Check if the user is currently locked out.
  Future<LockoutState> getLockoutState({String? userId}) async {
    return _lockoutManager.getLockoutState(userId: userId);
  }

  /// Manually reset lockout (e.g. after admin override).
  Future<void> resetLockout({String? userId}) async {
    await _lockoutManager.resetLockout(userId: userId);
  }

  // ═══════════════════════════════════════════════════════════
  // Resource Management
  // ═══════════════════════════════════════════════════════════

  /// Clean up resources (close streams, timers, etc).
  /// Call this when the SDK instance is no longer needed.
  void dispose() {
    _sessionManager.dispose();
    _lockoutManager.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // Private — Policy Resolution
  // ═══════════════════════════════════════════════════════════

  /// Fetch and cache server policy. Returns null if no provider configured.
  Future<BiometricPolicy?> _resolvePolicy({String? userId}) async {
    if (config.policyProvider == null) return null;
    try {
      return await config.policyProvider!.getPolicy(userId: userId);
    } catch (_) {
      // Policy fetch failed — fall back to local config
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Private — Token Lifecycle
  // ═══════════════════════════════════════════════════════════

  /// Resolve a token using the lifecycle handler if available.
  ///
  /// Flow:
  /// 1. Get token from storage
  /// 2. If [TokenLifecycle] is configured, validate it
  /// 3. If expired, attempt refresh
  /// 4. Return appropriate result
  Future<BiometricResult> _resolveToken({String? userId}) async {
    final session = await _sessionManager.getActiveSession(userId: userId);
    final token = await _sessionManager.getToken(userId: userId);

    // No token and no lifecycle handler — token expired
    if (token == null && config.tokenLifecycle == null) {
      _emitEvent(BiometricEventType.tokenExpired, userId);
      return const BiometricResult.tokenExpired();
    }

    // No lifecycle handler — return whatever we have
    if (config.tokenLifecycle == null) {
      return BiometricResult.sessionValid(
        session: session!,
        token: token,
      );
    }

    // Lifecycle handler configured — validate the token
    if (token == null) {
      _emitEvent(BiometricEventType.tokenExpired, userId);
      return const BiometricResult.tokenExpired();
    }

    final status = await config.tokenLifecycle!.validate(token);

    switch (status) {
      case TokenStatus.valid:
        return BiometricResult.sessionValid(
          session: session!,
          token: token,
        );

      case TokenStatus.expired:
        // Attempt refresh
        return _attemptTokenRefresh(
          expiredToken: token,
          session: session!,
          userId: userId,
        );

      case TokenStatus.invalid:
      case TokenStatus.missing:
        _emitEvent(BiometricEventType.tokenExpired, userId, properties: {
          'tokenStatus': status.name,
        });
        return const BiometricResult.tokenExpired();
    }
  }

  /// Attempt to refresh an expired token using the lifecycle handler.
  Future<BiometricResult> _attemptTokenRefresh({
    required String expiredToken,
    required BiometricSession session,
    String? userId,
  }) async {
    _emitEvent(BiometricEventType.tokenExpired, userId, properties: {
      'action': 'attempting_refresh',
    });

    try {
      final refreshResult =
          await config.tokenLifecycle!.refresh(expiredToken);

      switch (refreshResult) {
        case TokenRefreshSuccess(:final newToken, :final metadata):
          // Store the refreshed token
          await _sessionManager.storeToken(newToken, userId: userId);
          _emitEvent(BiometricEventType.tokenStored, userId, properties: {
            'source': 'token_refresh',
            ...metadata,
          });
          return BiometricResult.sessionValid(
            session: session,
            token: newToken,
          );

        case TokenRefreshFailed(:final reason):
          return BiometricResult.error(
            message: reason ?? 'Token refresh failed',
            cause: null,
          );

        case TokenRefreshReauthRequired():
          // Refresh token itself is expired — user must re-login
          await _sessionManager.clearSession(userId: userId);
          _emitEvent(BiometricEventType.sessionCleared, userId, properties: {
            'reason': 'reauth_required',
          });
          return const BiometricResult.reauthenticationRequired(
            reason: 'Refresh token expired. Please sign in again.',
          );
      }
    } catch (e) {
      return BiometricResult.error(
        message: 'Token refresh error: $e',
        cause: e,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Private — Platform Auth Helpers
  // ═══════════════════════════════════════════════════════════

  Future<_PlatformAuthResult> _attemptBiometric({
    required String reason,
  }) async {
    try {
      try {
        final outcome = await _iosHandler.authenticate(reason: reason);
        return _mapIOSOutcome(outcome);
      } catch (_) {
        try {
          final outcome = await _androidHandler.authenticate(reason: reason);
          return _mapAndroidOutcome(outcome);
        } catch (_) {
          return _PlatformAuthResult.notAvailable;
        }
      }
    } catch (e) {
      return _PlatformAuthResult.error;
    }
  }

  Future<BiometricAuthMethod> _detectMethod() async {
    try {
      try {
        return _iosHandler.detectMethod();
      } catch (_) {
        return _androidHandler.detectMethod();
      }
    } catch (_) {
      return BiometricAuthMethod.fingerprint;
    }
  }

  Future<BiometricResult> _handleSuccess({
    String? userId,
    required BiometricAuthMethod method,
  }) async {
    // Reset lockout counter on success
    await _lockoutManager.onSuccess(userId: userId);

    // Create session
    final session = await _sessionManager.createSession(
      method: method,
      userId: userId,
    );

    // Resolve token (with lifecycle handler if configured)
    final token = await _sessionManager.getToken(userId: userId);

    if (token == null && config.tokenLifecycle == null) {
      _emitEvent(BiometricEventType.tokenExpired, userId);
      return const BiometricResult.tokenExpired();
    }

    // If lifecycle handler is configured, validate & potentially refresh
    if (config.tokenLifecycle != null && token != null) {
      final status = await config.tokenLifecycle!.validate(token);
      if (status == TokenStatus.expired) {
        final refreshed = await _attemptTokenRefresh(
          expiredToken: token,
          session: session,
          userId: userId,
        );
        // If refresh succeeded, return the refreshed result
        if (refreshed is BiometricSessionValid) {
          _emitEvent(BiometricEventType.authSucceeded, userId, properties: {
            'method': method.name,
            'tokenRefreshed': true,
          });
          return BiometricResult.success(
            session: session,
            token: (refreshed as BiometricSessionValid).token,
          );
        }
        // If refresh failed, return that result
        return refreshed;
      }
      if (status == TokenStatus.invalid || status == TokenStatus.missing) {
        _emitEvent(BiometricEventType.tokenExpired, userId);
        return const BiometricResult.tokenExpired();
      }
    }

    _emitEvent(BiometricEventType.authSucceeded, userId, properties: {
      'method': method.name,
    });

    return BiometricResult.success(session: session, token: token);
  }

  Future<BiometricResult> _handleFailure({
    required String reason,
    String? userId,
  }) async {
    _emitEvent(BiometricEventType.authFailed, userId);

    // Record failure and check lockout
    final lockoutState =
        await _lockoutManager.recordFailure(userId: userId);
    if (lockoutState.isLockedOut) {
      return BiometricResult.lockedOut(
        lockedUntil: lockoutState.lockedUntil!,
      );
    }

    // Try fallback chain
    final fallbackResult = await _fallbackChain.execute(
      reason: reason,
      userId: userId,
    );

    return switch (fallbackResult) {
      FallbackSuccessOutcome(:final authMethod) => await _handleSuccess(
          userId: userId,
          method: authMethod,
        ),
      FallbackCancelledOutcome() => _handleCancelled(userId),
      FallbackExhaustedOutcome() => const BiometricResult.unavailable(
          reason: BiometricUnavailableReason.notSupported,
        ),
    };
  }

  BiometricResult _handleCancelled(String? userId) {
    _emitEvent(BiometricEventType.authCancelled, userId);
    return const BiometricResult.cancelled();
  }

  Future<BiometricResult> _handleUnavailable({
    required String reason,
    String? userId,
    required BiometricUnavailableReason unavailableReason,
  }) async {
    if (config.fallbackChain.isNotEmpty) {
      final fallbackResult = await _fallbackChain.execute(
        reason: reason,
        userId: userId,
      );

      return switch (fallbackResult) {
        FallbackSuccessOutcome(:final authMethod) => await _handleSuccess(
            userId: userId,
            method: authMethod,
          ),
        FallbackCancelledOutcome() => _handleCancelled(userId),
        FallbackExhaustedOutcome() =>
          BiometricResult.unavailable(reason: unavailableReason),
      };
    }

    return BiometricResult.unavailable(reason: unavailableReason);
  }

  BiometricResult _handleInvalidated(String? userId) {
    _emitEvent(BiometricEventType.biometricInvalidated, userId);
    return const BiometricResult.invalidated();
  }

  _PlatformAuthResult _mapIOSOutcome(IOSAuthOutcome outcome) {
    return switch (outcome) {
      IOSAuthOutcome.success => _PlatformAuthResult.success,
      IOSAuthOutcome.failed => _PlatformAuthResult.failed,
      IOSAuthOutcome.cancelled => _PlatformAuthResult.cancelled,
      IOSAuthOutcome.notAvailable => _PlatformAuthResult.notAvailable,
      IOSAuthOutcome.notEnrolled => _PlatformAuthResult.notEnrolled,
      IOSAuthOutcome.passcodeNotSet => _PlatformAuthResult.passcodeNotSet,
      IOSAuthOutcome.lockedOut => _PlatformAuthResult.lockedOut,
      IOSAuthOutcome.error => _PlatformAuthResult.error,
    };
  }

  _PlatformAuthResult _mapAndroidOutcome(AndroidAuthOutcome outcome) {
    return switch (outcome) {
      AndroidAuthOutcome.success => _PlatformAuthResult.success,
      AndroidAuthOutcome.failed => _PlatformAuthResult.failed,
      AndroidAuthOutcome.cancelled => _PlatformAuthResult.cancelled,
      AndroidAuthOutcome.notAvailable => _PlatformAuthResult.notAvailable,
      AndroidAuthOutcome.notEnrolled => _PlatformAuthResult.notEnrolled,
      AndroidAuthOutcome.passcodeNotSet => _PlatformAuthResult.passcodeNotSet,
      AndroidAuthOutcome.lockedOut => _PlatformAuthResult.lockedOut,
      AndroidAuthOutcome.error => _PlatformAuthResult.error,
    };
  }

  void _emitEvent(
    BiometricEventType type,
    String? userId, {
    Map<String, dynamic> properties = const {},
  }) {
    config.onEvent?.call(BiometricEvent(
      type: type,
      userId: userId ?? config.defaultUserId ?? '_device_default_',
      timestamp: DateTime.now(),
      properties: properties,
    ));
  }
}

/// Unified platform auth result for cross-platform mapping.
enum _PlatformAuthResult {
  success,
  failed,
  cancelled,
  notAvailable,
  notEnrolled,
  passcodeNotSet,
  lockedOut,
  invalidated,
  error,
}

/// Base class for mock implementations used in testing.
///
/// Extend this to create test doubles for [BiometricShield].
/// Unlike the old static API, tests now pass a mock instance directly
/// to the code under test (dependency injection pattern).
abstract class BiometricShieldMockBase {
  BiometricConfig get config;
}
