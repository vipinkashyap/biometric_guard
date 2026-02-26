import 'dart:io';

import 'package:flutter/widgets.dart';

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
import '../ui/biometric_gate.dart';

/// Main entry point for the BiometricShield SDK.
///
/// Call [configure] once at app startup, then use [authenticate],
/// [hasValidSession], [storeToken], etc. throughout your app.
///
/// All methods are static for ergonomic access. The singleton
/// pattern is internal — callers just call `BiometricShield.authenticate()`.
class BiometricShield {
  BiometricShield._();

  static BiometricConfig? _config;
  static SessionManager? _sessionManager;
  static LockoutManager? _lockoutManager;
  static CapabilityDetector? _capabilityDetector;
  static IOSHandler? _iosHandler;
  static AndroidHandler? _androidHandler;
  static FallbackChainExecutor? _fallbackChain;

  /// Whether the SDK has been configured.
  static bool get isConfigured => _config != null;

  // --- Initialization ---

  /// Initialize the SDK. Call once in `main()` or your auth module.
  /// Must be called before any other method.
  static Future<void> configure(BiometricConfig config) async {
    _config = config;
    _sessionManager = SessionManager(config: config);
    _lockoutManager = LockoutManager(config: config);
    _capabilityDetector = CapabilityDetector();
    _iosHandler = IOSHandler();
    _androidHandler = AndroidHandler();
    _fallbackChain = FallbackChainExecutor(config: config);

    // Wire up BiometricGate to use our authenticate method
    setGateAuthenticateCallback(({
      required String reason,
      String? userId,
      BuildContext? context,
    }) =>
        authenticate(
          reason: reason,
          userId: userId,
          context: context,
        ));
  }

  // --- Authentication ---

  /// Trigger full authentication flow including fallbacks if needed.
  ///
  /// [reason] — shown in platform biometric prompt.
  /// [userId] — overrides [BiometricConfig.defaultUserId] for this call.
  /// [context] — required if fallback flow may show custom UI.
  /// [requireFresh] — if true, ignores active session and re-authenticates.
  static Future<BiometricResult> authenticate({
    required String reason,
    String? userId,
    BuildContext? context,
    bool requireFresh = false,
  }) async {
    _assertConfigured();

    final sessionMgr = _sessionManager!;
    final lockoutMgr = _lockoutManager!;

    // 1. Check lockout state
    final lockoutState = await lockoutMgr.getLockoutState(userId: userId);
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
          await sessionMgr.getActiveSession(userId: userId);
      if (activeSession != null && !activeSession.isExpired) {
        final token = await sessionMgr.getToken(userId: userId);
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
          context: context, // ignore: use_build_context_synchronously
        ),
      _PlatformAuthResult.cancelled => _handleCancelled(userId),
      _PlatformAuthResult.notAvailable ||
      _PlatformAuthResult.notEnrolled =>
        await _handleUnavailable(
          reason: reason,
          userId: userId,
          context: context, // ignore: use_build_context_synchronously
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
  static Future<bool> hasValidSession({String? userId}) async {
    _assertConfigured();
    return _sessionManager!.hasValidSession(userId: userId);
  }

  /// Validate session and re-authenticate if expired.
  /// Silent version — only shows UI if session has expired.
  static Future<BiometricResult> validateOrAuthenticate({
    required String reason,
    String? userId,
    BuildContext? context,
  }) async {
    _assertConfigured();

    final activeSession =
        await _sessionManager!.getActiveSession(userId: userId);
    if (activeSession != null && !activeSession.isExpired) {
      final token = await _sessionManager!.getToken(userId: userId);
      return BiometricResult.sessionValid(
        session: activeSession,
        token: token,
      );
    }

    return authenticate(
      reason: reason,
      userId: userId,
      context: context,
    );
  }

  // --- Session Management ---

  /// Explicitly end the current session (e.g. on logout).
  static Future<void> clearSession({String? userId}) async {
    _assertConfigured();
    await _sessionManager!.clearSession(userId: userId);
  }

  /// Clear all stored tokens and session state for a user.
  static Future<void> clearAll({String? userId}) async {
    _assertConfigured();
    await _sessionManager!.clearAll(userId: userId);
  }

  // --- Device Capabilities ---

  /// Detect what biometric capabilities this device has.
  static Future<BiometricCapability> getCapability() async {
    _assertConfigured();
    final capability = await _capabilityDetector!.detect();
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
  static Future<void> storeToken(String token, {String? userId}) async {
    _assertConfigured();
    await _sessionManager!.storeToken(token, userId: userId);
  }

  /// Retrieve the stored token after successful biometric auth.
  static Future<String?> getToken({String? userId}) async {
    _assertConfigured();
    return _sessionManager!.getToken(userId: userId);
  }

  // --- Lockout Management ---

  /// Check if the user is currently locked out.
  static Future<LockoutState> getLockoutState({String? userId}) async {
    _assertConfigured();
    return _lockoutManager!.getLockoutState(userId: userId);
  }

  /// Manually reset lockout (e.g. after admin override).
  static Future<void> resetLockout({String? userId}) async {
    _assertConfigured();
    await _lockoutManager!.resetLockout(userId: userId);
  }

  // --- Testing Support ---

  /// Replace the SDK internals with a mock for testing.
  /// @visibleForTesting
  static void configureMock(BiometricShieldMockBase mock) {
    _config = mock.config;
  }

  /// Reset all state. For testing only.
  /// @visibleForTesting
  static void reset() {
    _config = null;
    _sessionManager = null;
    _lockoutManager = null;
    _capabilityDetector = null;
    _iosHandler = null;
    _androidHandler = null;
    _fallbackChain = null;
  }

  // --- Private Helpers ---

  static void _assertConfigured() {
    if (_config == null) {
      throw StateError(
        'BiometricShield not configured. '
        'Call BiometricShield.configure() before using the SDK.',
      );
    }
  }

  static Future<_PlatformAuthResult> _attemptBiometric({
    required String reason,
  }) async {
    try {
      if (Platform.isIOS) {
        final outcome =
            await _iosHandler!.authenticate(reason: reason);
        return _mapIOSOutcome(outcome);
      } else if (Platform.isAndroid) {
        final outcome =
            await _androidHandler!.authenticate(reason: reason);
        return _mapAndroidOutcome(outcome);
      }
      return _PlatformAuthResult.notAvailable;
    } catch (e) {
      return _PlatformAuthResult.error;
    }
  }

  static Future<BiometricAuthMethod> _detectMethod() async {
    try {
      if (Platform.isIOS) {
        return _iosHandler!.detectMethod();
      } else {
        return _androidHandler!.detectMethod();
      }
    } catch (_) {
      return BiometricAuthMethod.fingerprint;
    }
  }

  static Future<BiometricResult> _handleSuccess({
    String? userId,
    required BiometricAuthMethod method,
  }) async {
    // Reset lockout counter on success
    await _lockoutManager!.onSuccess(userId: userId);

    // Create session
    final session = await _sessionManager!.createSession(
      method: method,
      userId: userId,
    );

    // Retrieve token
    final token = await _sessionManager!.getToken(userId: userId);

    // Check for expired/missing token
    if (token == null) {
      _emitEvent(BiometricEventType.tokenExpired, userId);
      if (_config!.onTokenExpired != null) {
        await _config!.onTokenExpired!();
        return const BiometricResult.tokenExpired();
      }
      return const BiometricResult.tokenExpired();
    }

    _emitEvent(BiometricEventType.authSucceeded, userId, properties: {
      'method': method.name,
    });

    return BiometricResult.success(session: session, token: token);
  }

  static Future<BiometricResult> _handleFailure({
    required String reason,
    String? userId,
    BuildContext? context,
  }) async {
    _emitEvent(BiometricEventType.authFailed, userId);

    // Record failure and check lockout
    final lockoutState =
        await _lockoutManager!.recordFailure(userId: userId);
    if (lockoutState.isLockedOut) {
      return BiometricResult.lockedOut(
        lockedUntil: lockoutState.lockedUntil!,
      );
    }

    // Try fallback chain
    final fallbackResult = await _fallbackChain!.execute(
      reason: reason,
      context: context,
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

  static BiometricResult _handleCancelled(String? userId) {
    _config?.onUserCancelled?.call();
    return const BiometricResult.cancelled();
  }

  static Future<BiometricResult> _handleUnavailable({
    required String reason,
    String? userId,
    BuildContext? context,
    required BiometricUnavailableReason unavailableReason,
  }) async {
    // Try fallback chain even when biometric is unavailable
    if (_config!.fallbackChain.isNotEmpty) {
      final fallbackResult = await _fallbackChain!.execute(
        reason: reason,
        context: context,
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

  static BiometricResult _handleInvalidated(String? userId) {
    _config?.onBiometricInvalidated?.call();
    _emitEvent(BiometricEventType.biometricInvalidated, userId);
    return const BiometricResult.invalidated();
  }

  static _PlatformAuthResult _mapIOSOutcome(IOSAuthOutcome outcome) {
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

  static _PlatformAuthResult _mapAndroidOutcome(AndroidAuthOutcome outcome) {
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

  static void _emitEvent(
    BiometricEventType type,
    String? userId, {
    Map<String, dynamic> properties = const {},
  }) {
    _config?.onEvent?.call(BiometricEvent(
      type: type,
      userId: userId ?? _config?.defaultUserId ?? '_device_default_',
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
abstract class BiometricShieldMockBase {
  BiometricConfig get config;
}
