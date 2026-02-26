import 'package:local_auth/local_auth.dart';

import 'biometric_config.dart';
import 'biometric_result.dart';
import 'biometric_session.dart';
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
/// Unlike the static API in v1, this is instance-based for better composability
/// and testing. No Flutter imports — pure Dart business logic.
class BiometricShield {
  final BiometricConfig config;
  late final SessionManager _sessionManager;
  late final LockoutManager _lockoutManager;
  late final CapabilityDetector _capabilityDetector;
  late final IOSHandler _iosHandler;
  late final AndroidHandler _androidHandler;
  late final FallbackChainExecutor _fallbackChain;

  /// Create a new BiometricShield instance with optional config.
  BiometricShield({BiometricConfig config = const BiometricConfig()})
      : config = config {
    _sessionManager = SessionManager(config: config);
    _lockoutManager = LockoutManager(config: config);
    _capabilityDetector = CapabilityDetector();
    _iosHandler = IOSHandler();
    _androidHandler = AndroidHandler();
    _fallbackChain = FallbackChainExecutor(config: config);
  }

  // --- Authentication ---

  /// Trigger full authentication flow including fallbacks if needed.
  ///
  /// [reason] — shown in platform biometric prompt.
  /// [userId] — overrides [BiometricConfig.defaultUserId] for this call.
  /// [requireFresh] — if true, ignores active session and re-authenticates.
  Future<BiometricResult> authenticate({
    required String reason,
    String? userId,
    bool requireFresh = false,
  }) async {
    // 1. Check lockout state
    final lockoutState = await _lockoutManager.getLockoutState(userId: userId);
    if (lockoutState.isLockedOut) {
      _emitEvent(BiometricEventType.authFailed, userId, properties: {
        'reason': 'locked_out',
      });
      return BiometricResult.lockedOut(
        lockedUntil: lockoutState.lockedUntil!,
      );
    }

    // 2. Check existing session (unless requireFresh)
    if (!requireFresh) {
      final activeSession =
          await _sessionManager.getActiveSession(userId: userId);
      if (activeSession != null && !activeSession.isExpired) {
        final token = await _sessionManager.getToken(userId: userId);
        return BiometricResult.sessionValid(
          session: activeSession,
          token: token,
        );
      }
    }

    // 3. Emit auth attempted event
    _emitEvent(BiometricEventType.authAttempted, userId);

    // 4. Attempt biometric authentication
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
      final token = await _sessionManager.getToken(userId: userId);
      return BiometricResult.sessionValid(
        session: activeSession,
        token: token,
      );
    }

    return authenticate(
      reason: reason,
      userId: userId,
    );
  }

  // --- Session Management ---

  /// Explicitly end the current session (e.g. on logout).
  Future<void> clearSession({String? userId}) async {
    await _sessionManager.clearSession(userId: userId);
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

  // --- Device Capabilities ---

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

  // --- Token Management ---

  /// Store a token securely, namespaced to userId.
  /// Call this after your server auth succeeds on first login.
  Future<void> storeToken(String token, {String? userId}) async {
    await _sessionManager.storeToken(token, userId: userId);
  }

  /// Retrieve the stored token after successful biometric auth.
  Future<String?> getToken({String? userId}) async {
    return _sessionManager.getToken(userId: userId);
  }

  // --- Lockout Management ---

  /// Check if the user is currently locked out.
  Future<LockoutState> getLockoutState({String? userId}) async {
    return _lockoutManager.getLockoutState(userId: userId);
  }

  /// Manually reset lockout (e.g. after admin override).
  Future<void> resetLockout({String? userId}) async {
    await _lockoutManager.resetLockout(userId: userId);
  }

  // --- Resource Management ---

  /// Clean up resources (close streams, timers, etc).
  /// Call this when the SDK instance is no longer needed.
  void dispose() {
    _sessionManager.dispose();
    _lockoutManager.dispose();
  }

  // --- Private Helpers ---

  Future<_PlatformAuthResult> _attemptBiometric({
    required String reason,
  }) async {
    try {
      // Platform detection: try to use iOS handler, fall back to Android
      // If neither platform is available, return notAvailable
      try {
        final outcome = await _iosHandler.authenticate(reason: reason);
        return _mapIOSOutcome(outcome);
      } catch (_) {
        // Not iOS or iOS handler failed; try Android
        try {
          final outcome = await _androidHandler.authenticate(reason: reason);
          return _mapAndroidOutcome(outcome);
        } catch (_) {
          // Both failed
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

    // Retrieve token
    final token = await _sessionManager.getToken(userId: userId);

    // Check for expired/missing token
    if (token == null) {
      _emitEvent(BiometricEventType.tokenExpired, userId);
      return const BiometricResult.tokenExpired();
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
    // Try fallback chain even when biometric is unavailable
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
