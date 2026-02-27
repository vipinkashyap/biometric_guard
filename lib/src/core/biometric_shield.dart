import 'dart:async';
import 'package:universal_io/io.dart' show Platform;

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
class BiometricShield implements BiometricShieldInterface {
  /// Create a new BiometricShield instance with optional config.
  BiometricShield({this.config = const BiometricConfig()}) {
    config.validate(); // Runtime validation even in release builds
    _sessionManager = SessionManager(config: config);
    _lockoutManager = LockoutManager(config: config);
    _capabilityDetector = CapabilityDetector();
    _fallbackChain = FallbackChainExecutor(config: config);
    _preferences = BiometricPreferences(
      store: config.tokenStore,
      defaultUserId: config.defaultUserId,
    );

    // Platform handlers — instantiated based on detected platform.
    // On unsupported platforms (desktop, web) both remain null and
    // _attemptBiometric returns notAvailable.
    try {
      if (Platform.isIOS) {
        _iosHandler = IOSHandler();
      } else if (Platform.isAndroid) {
        _androidHandler = AndroidHandler();
      }
    } on UnsupportedError catch (_) {
      // Platform.isIOS/isAndroid throws UnsupportedError on web; ignore.
    }
  }

  @override
  final BiometricConfig config;

  late final SessionManager _sessionManager;
  late final LockoutManager _lockoutManager;
  late final CapabilityDetector _capabilityDetector;
  late final FallbackChainExecutor _fallbackChain;
  late final BiometricPreferences _preferences;

  IOSHandler? _iosHandler;
  AndroidHandler? _androidHandler;

  /// Concurrency guard — prevents double-tap / parallel auth races.
  Completer<BiometricResult>? _authInProgress;

  /// User-facing preferences (remember me, enable/disable, etc).
  @override
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
  ///
  /// Respects [BiometricConfig.authenticationTimeout]. If the full flow
  /// exceeds the timeout, returns [BiometricResult.error] with an
  /// `authTimeout` event.
  @override
  Future<BiometricResult> authenticate({
    required String reason,
    String? userId,
    bool requireFresh = false,
  }) async {
    assert(reason.isNotEmpty, 'reason must not be empty');
    assert(
      reason.length <= 200,
      'reason should be <= 200 characters for platform prompts',
    );

    // Concurrency guard — atomic check-and-set prevents race between
    // two calls arriving before either sets the completer.
    final existing = _authInProgress;
    if (existing != null) {
      _log('authenticate() already in progress — awaiting existing call');
      return existing.future;
    }

    final completer = Completer<BiometricResult>();
    _authInProgress = completer;
    final context = _AuthRunContext();
    final timeoutTimer = Timer(config.authenticationTimeout, () {
      if (!completer.isCompleted) {
        completer.complete(_timeoutResult(userId, context));
      }
    });

    unawaited(
      completer.future.whenComplete(() {
        if (identical(_authInProgress, completer)) {
          _authInProgress = null;
        }
      }),
    );

    unawaited(
      _authenticateImpl(
        reason: reason,
        userId: userId,
        requireFresh: requireFresh,
        context: context,
      ).then(
        (result) {
          if (!completer.isCompleted) {
            completer.complete(result);
          }
        },
        onError: (Object error, StackTrace _) {
          final errorResult = BiometricResult.error(
            message: 'Unexpected error during authentication: $error',
            cause: error,
          );
          if (!completer.isCompleted) {
            completer.complete(errorResult);
          }
        },
      ),
    );

    try {
      return await completer.future;
    } finally {
      timeoutTimer.cancel();
    }
  }

  /// Core authentication implementation, called inside the timeout wrapper.
  Future<BiometricResult> _authenticateImpl({
    required String reason,
    String? userId,
    bool requireFresh = false,
    required _AuthRunContext context,
  }) async {
    final cancelled = _resultIfCancelled(context, userId);
    if (cancelled != null) return cancelled;

    // 1. Check server policy
    final policy = await _resolvePolicy(userId: userId);
    final effectiveMaxAttempts = _effectiveMaxAttempts(policy);
    final effectiveLockoutDuration = _effectiveLockoutDuration(policy);
    final effectiveSessionDuration = _effectiveSessionDuration(policy);
    final shouldForceFresh =
        requireFresh || (policy?.forceReauthOnResume == true);

    final cancelledAfterPolicy = _resultIfCancelled(context, userId);
    if (cancelledAfterPolicy != null) return cancelledAfterPolicy;

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
    final cancelledAfterPrefs = _resultIfCancelled(context, userId);
    if (cancelledAfterPrefs != null) return cancelledAfterPrefs;

    if (!biometricEnabled && (policy?.requireBiometric != true)) {
      return _handleUnavailable(
        reason: reason,
        userId: userId,
        unavailableReason: BiometricUnavailableReason.notSupported,
        context: context,
      );
    }

    // 3. Check lockout state
    final lockoutState = await _lockoutManager.getLockoutStateWithOverrides(
      userId: userId,
      maxAttemptsOverride: effectiveMaxAttempts,
      lockoutDurationOverride: effectiveLockoutDuration,
    );
    final cancelledAfterLockout = _resultIfCancelled(context, userId);
    if (cancelledAfterLockout != null) return cancelledAfterLockout;

    if (lockoutState.isLockedOut) {
      _emitEvent(
        BiometricEventType.authFailed,
        userId,
        properties: {'reason': 'locked_out'},
      );
      return BiometricResult.lockedOut(lockedUntil: lockoutState.lockedUntil!);
    }

    // 4. Check existing session (unless requireFresh)
    if (!shouldForceFresh) {
      final activeSession = await _sessionManager.getActiveSession(
        userId: userId,
      );
      final cancelledAfterSession = _resultIfCancelled(context, userId);
      if (cancelledAfterSession != null) return cancelledAfterSession;

      if (activeSession != null &&
          _isSessionValidForDuration(activeSession, effectiveSessionDuration)) {
        _log('Session still valid — resolving token');
        return _validateAndResolveToken(
          session: activeSession,
          userId: userId,
          context: context,
        );
      }
    }

    // 5. Emit auth attempted event
    _emitEvent(BiometricEventType.authAttempted, userId);

    // 6. Attempt biometric authentication
    final biometricResult = await _attemptBiometric(reason: reason);
    final cancelledAfterPlatform = _resultIfCancelled(context, userId);
    if (cancelledAfterPlatform != null) return cancelledAfterPlatform;

    return switch (biometricResult) {
      _PlatformAuthResult.success => await _handleSuccess(
        userId: userId,
        method: await _detectMethod(),
        context: context,
      ),
      _PlatformAuthResult.failed => await _handleFailure(
        reason: reason,
        userId: userId,
        context: context,
        maxAttemptsOverride: effectiveMaxAttempts,
        lockoutDurationOverride: effectiveLockoutDuration,
      ),
      _PlatformAuthResult.cancelled => _handleCancelled(userId),
      _PlatformAuthResult.notAvailable ||
      _PlatformAuthResult.notEnrolled => await _handleUnavailable(
        reason: reason,
        userId: userId,
        unavailableReason: biometricResult == _PlatformAuthResult.notEnrolled
            ? BiometricUnavailableReason.notEnrolled
            : BiometricUnavailableReason.notSupported,
        context: context,
      ),
      _PlatformAuthResult.passcodeNotSet => const BiometricResult.unavailable(
        reason: BiometricUnavailableReason.passcodeNotSet,
      ),
      _PlatformAuthResult.lockedOut => const BiometricResult.unavailable(
        reason: BiometricUnavailableReason.temporarilyUnavailable,
      ),
      _PlatformAuthResult.error => const BiometricResult.error(
        message: 'Platform authentication error',
        cause: null,
      ),
    };
  }

  /// Check if current session is still valid without triggering auth.
  @override
  Future<bool> hasValidSession({String? userId}) async {
    return _sessionManager.hasValidSession(userId: userId);
  }

  /// Validate session and re-authenticate if expired.
  /// Silent version — only shows UI if session has expired.
  @override
  Future<BiometricResult> validateOrAuthenticate({
    required String reason,
    String? userId,
  }) async {
    final policy = await _resolvePolicy(userId: userId);
    if (policy?.disabled == true) {
      return BiometricResult.unavailable(
        reason: BiometricUnavailableReason.disabledByPolicy,
        message: policy?.disabledReason,
      );
    }

    if (policy?.forceReauthOnResume == true) {
      return authenticate(reason: reason, userId: userId, requireFresh: true);
    }

    final effectiveSessionDuration = _effectiveSessionDuration(policy);
    final activeSession = await _sessionManager.getActiveSession(
      userId: userId,
    );
    if (activeSession != null &&
        _isSessionValidForDuration(activeSession, effectiveSessionDuration)) {
      return _validateAndResolveToken(session: activeSession, userId: userId);
    }

    return authenticate(reason: reason, userId: userId);
  }

  // ═══════════════════════════════════════════════════════════
  // Enrollment
  // ═══════════════════════════════════════════════════════════

  /// Check whether biometric enrollment has been completed.
  ///
  /// This checks the device's own enrollment status, not the app's.
  /// Use [getCapability] for a richer picture.
  @override
  Future<bool> isEnrolled() async {
    final capability = await _capabilityDetector.detect();
    return capability.isEnrolled;
  }

  /// First-class enrollment: guide the user to enroll biometrics.
  ///
  /// On most platforms this means directing the user to system settings.
  /// Emits [BiometricEventType.enrolled] on success or
  /// [BiometricEventType.enrollmentDeclined] on failure/cancellation.
  @override
  Future<bool> enroll({String? userId}) async {
    _log('enroll() called');
    final capability = await _capabilityDetector.detect();
    if (capability.isEnrolled) {
      _emitEvent(
        BiometricEventType.enrolled,
        userId,
        properties: {'alreadyEnrolled': true},
      );
      return true;
    }

    // Can't programmatically enroll — we can only check.
    // Emit declined event and return false so the caller can show instructions.
    _emitEvent(
      BiometricEventType.enrollmentDeclined,
      userId,
      properties: {'reason': 'not_enrolled_on_device'},
    );
    return false;
  }

  // ═══════════════════════════════════════════════════════════
  // Session Management
  // ═══════════════════════════════════════════════════════════

  /// Explicitly end the current session (e.g. on logout).
  ///
  /// If [BiometricPreferences.isRememberMeEnabled] is false, this also
  /// clears the stored token (memory-only session).
  @override
  Future<void> clearSession({String? userId}) async {
    await _sessionManager.clearSession(userId: userId);

    // If remember me is disabled, also clear the stored token
    final rememberMe = await _preferences.isRememberMeEnabled(userId: userId);
    if (!rememberMe) {
      await _sessionManager.deleteToken(userId: userId);
    }
  }

  /// Clear all stored tokens and session state for a user.
  @override
  Future<void> clearAll({String? userId}) async {
    await _sessionManager.clearAll(userId: userId);
  }

  /// Get a stream of session state changes for a user.
  @override
  Stream<BiometricSession?> sessionStream({String? userId}) {
    return _sessionManager.sessionStream(userId: userId);
  }

  /// Notify the SDK that the user has performed an activity.
  @override
  void onActivity({String? userId}) {
    _sessionManager.onActivity(userId: userId);
  }

  // ═══════════════════════════════════════════════════════════
  // Device Capabilities
  // ═══════════════════════════════════════════════════════════

  /// Detect what biometric capabilities this device has.
  @override
  Future<BiometricCapability> getCapability() async {
    final capability = await _capabilityDetector.detect();
    _emitEvent(
      BiometricEventType.capabilityChecked,
      null,
      properties: {
        'hasBiometric': capability.hasBiometric,
        'isEnrolled': capability.isEnrolled,
        'label': capability.biometricLabel,
      },
    );
    return capability;
  }

  // ═══════════════════════════════════════════════════════════
  // Token Management
  // ═══════════════════════════════════════════════════════════

  /// Store a token securely, namespaced to userId.
  @override
  Future<void> storeToken(String token, {String? userId}) async {
    await _sessionManager.storeToken(token, userId: userId);
  }

  /// Retrieve the stored token after successful biometric auth.
  @override
  Future<String?> getToken({String? userId}) async {
    return _sessionManager.getToken(userId: userId);
  }

  // ═══════════════════════════════════════════════════════════
  // Lockout Management
  // ═══════════════════════════════════════════════════════════

  /// Check if the user is currently locked out.
  @override
  Future<LockoutState> getLockoutState({String? userId}) async {
    return _lockoutManager.getLockoutState(userId: userId);
  }

  /// Manually reset lockout (e.g. after admin override).
  @override
  Future<void> resetLockout({String? userId}) async {
    await _lockoutManager.resetLockout(userId: userId);
  }

  // ═══════════════════════════════════════════════════════════
  // Resource Management
  // ═══════════════════════════════════════════════════════════

  /// Clean up resources (close streams, timers, etc).
  /// Call this when the SDK instance is no longer needed.
  @override
  void dispose() {
    _sessionManager.dispose();
    _lockoutManager.dispose();
  }

  /// Dispose resources for a single user without shutting down the SDK.
  ///
  /// Useful in multi-user scenarios when one user logs out but the SDK
  /// continues to serve other users.
  @override
  Future<void> disposeUser({required String userId}) async {
    await _sessionManager.clearAll(userId: userId);
    await _preferences.clearAll(userId: userId);
    await _lockoutManager.resetLockout(userId: userId);
    _log('disposeUser($userId) — all data cleared');
  }

  // ═══════════════════════════════════════════════════════════
  // Private — Policy Resolution
  // ═══════════════════════════════════════════════════════════

  /// Fetch and cache server policy. Returns null if no provider configured.
  Future<BiometricPolicy?> _resolvePolicy({String? userId}) async {
    if (config.policyProvider == null) return null;
    try {
      return await config.policyProvider!.getPolicy(userId: userId);
    } on Exception catch (e) {
      // Policy fetch failed (network, timeout, etc) — fall back to local config.
      // Only catches Exception; programming errors (Error) still propagate.
      _emitEvent(
        BiometricEventType.policyFetchFailed,
        userId,
        properties: {'error': e.toString()},
      );
      _log('Policy fetch failed: $e — using local config');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Private — Token Lifecycle (deduplicated)
  // ═══════════════════════════════════════════════════════════

  /// Single method for token validation + lifecycle resolution.
  ///
  /// Used by both the "existing session" path and the "fresh auth" path
  /// to eliminate the duplicated token validation logic.
  Future<BiometricResult> _validateAndResolveToken({
    required BiometricSession session,
    String? userId,
    _AuthRunContext? context,
  }) async {
    final cancelled = _resultIfCancelled(context, userId);
    if (cancelled != null) return cancelled;

    final token = await _sessionManager.getToken(userId: userId);
    final cancelledAfterLoad = _resultIfCancelled(context, userId);
    if (cancelledAfterLoad != null) return cancelledAfterLoad;

    // Capture locally to avoid TOCTOU null dereference if config were
    // ever swapped between the null check and the dereference.
    final lifecycle = config.tokenLifecycle;

    // No lifecycle handler — return whatever we have.
    if (lifecycle == null) {
      if (token == null || token.isEmpty) {
        _emitEvent(BiometricEventType.tokenExpired, userId);
        return const BiometricResult.tokenExpired();
      }
      return BiometricResult.sessionValid(session: session, token: token);
    }

    // Lifecycle handler configured — validate.
    if (token == null || token.isEmpty) {
      _emitEvent(BiometricEventType.tokenExpired, userId);
      return const BiometricResult.tokenExpired();
    }

    final status = await lifecycle.validate(token);

    return switch (status) {
      TokenStatus.valid => BiometricResult.sessionValid(
        session: session,
        token: token,
      ),
      TokenStatus.expired => _attemptTokenRefresh(
        expiredToken: token,
        session: session,
        userId: userId,
        context: context,
      ),
      TokenStatus.invalid || TokenStatus.missing => () {
        _emitEvent(
          BiometricEventType.tokenExpired,
          userId,
          properties: {'tokenStatus': status.name},
        );
        return const BiometricResult.tokenExpired();
      }(),
    };
  }

  /// Attempt to refresh an expired token using the lifecycle handler.
  Future<BiometricResult> _attemptTokenRefresh({
    required String expiredToken,
    required BiometricSession session,
    String? userId,
    _AuthRunContext? context,
  }) async {
    final cancelled = _resultIfCancelled(context, userId);
    if (cancelled != null) return cancelled;

    _emitEvent(
      BiometricEventType.tokenExpired,
      userId,
      properties: {'action': 'attempting_refresh'},
    );

    final lifecycle = config.tokenLifecycle;
    if (lifecycle == null) {
      return const BiometricResult.tokenExpired();
    }

    try {
      final refreshResult = await lifecycle.refresh(expiredToken);

      switch (refreshResult) {
        case TokenRefreshSuccess(:final newToken, :final metadata):
          final cancelledAfterRefresh = _resultIfCancelled(context, userId);
          if (cancelledAfterRefresh != null) return cancelledAfterRefresh;

          await _sessionManager.storeToken(newToken, userId: userId);
          _emitEvent(
            BiometricEventType.tokenStored,
            userId,
            properties: {'source': 'token_refresh', ...metadata},
          );
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
          final cancelledBeforeClear = _resultIfCancelled(context, userId);
          if (cancelledBeforeClear != null) return cancelledBeforeClear;

          await _sessionManager.clearSession(userId: userId);
          _emitEvent(
            BiometricEventType.sessionCleared,
            userId,
            properties: {'reason': 'reauth_required'},
          );
          return const BiometricResult.reauthenticationRequired(
            reason: 'Refresh token expired. Please sign in again.',
          );
      }
    } on Exception catch (e) {
      // Only catches Exception; programming errors (Error) still propagate.
      _emitEvent(
        BiometricEventType.authFailed,
        userId,
        properties: {'error': 'token_refresh_error', 'message': e.toString()},
      );
      return BiometricResult.error(
        message: 'Token refresh error: $e',
        cause: e,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Private — Platform Auth Helpers
  // ═══════════════════════════════════════════════════════════

  /// Attempt biometric auth using the correct platform handler.
  ///
  /// Uses [Platform.isIOS] / [Platform.isAndroid] to select the handler
  /// rather than nested try/catch.
  Future<_PlatformAuthResult> _attemptBiometric({
    required String reason,
  }) async {
    try {
      if (_iosHandler != null) {
        final outcome = await _iosHandler!.authenticate(reason: reason);
        return _mapIOSOutcome(outcome);
      }
      if (_androidHandler != null) {
        final outcome = await _androidHandler!.authenticate(reason: reason);
        return _mapAndroidOutcome(outcome);
      }
      // Neither handler available (desktop, web, unsupported platform)
      return _PlatformAuthResult.notAvailable;
    } on Exception catch (e) {
      // Platform communication errors. Programming errors still propagate.
      _emitEvent(
        BiometricEventType.authFailed,
        null,
        properties: {'error': 'platform_auth_error', 'message': e.toString()},
      );
      _log('Platform auth error: $e');
      return _PlatformAuthResult.error;
    }
  }

  Future<BiometricAuthMethod> _detectMethod() async {
    try {
      if (_iosHandler != null) return _iosHandler!.detectMethod();
      if (_androidHandler != null) return _androidHandler!.detectMethod();
      return BiometricAuthMethod.fingerprint;
    } on Exception catch (_) {
      return BiometricAuthMethod.fingerprint;
    }
  }

  Future<BiometricResult> _handleSuccess({
    String? userId,
    required BiometricAuthMethod method,
    required _AuthRunContext context,
  }) async {
    final cancelled = _resultIfCancelled(context, userId);
    if (cancelled != null) return cancelled;

    // Reset lockout counter on success
    await _lockoutManager.onSuccess(userId: userId);
    final cancelledAfterReset = _resultIfCancelled(context, userId);
    if (cancelledAfterReset != null) return cancelledAfterReset;

    // Create session
    final session = await _sessionManager.createSession(
      method: method,
      userId: userId,
    );
    final cancelledAfterSession = _resultIfCancelled(context, userId);
    if (cancelledAfterSession != null) {
      await _sessionManager.clearSession(userId: userId);
      return cancelledAfterSession;
    }

    // Validate & resolve token through the single code path
    final tokenResult = await _validateAndResolveToken(
      session: session,
      userId: userId,
      context: context,
    );

    // Wrap sessionValid into success for fresh auth responses
    if (tokenResult is BiometricSessionValid) {
      _emitEvent(
        BiometricEventType.authSucceeded,
        userId,
        properties: {'method': method.name},
      );
      return BiometricResult.success(
        session: session,
        token: tokenResult.token,
      );
    }

    // Token expired or error — return as-is
    return tokenResult;
  }

  Future<BiometricResult> _handleFailure({
    required String reason,
    String? userId,
    required _AuthRunContext context,
    required int maxAttemptsOverride,
    required Duration lockoutDurationOverride,
  }) async {
    final cancelled = _resultIfCancelled(context, userId);
    if (cancelled != null) return cancelled;

    _emitEvent(BiometricEventType.authFailed, userId);

    // Record failure and check lockout
    final lockoutState = await _lockoutManager.recordFailureWithOverrides(
      userId: userId,
      maxAttemptsOverride: maxAttemptsOverride,
      lockoutDurationOverride: lockoutDurationOverride,
    );
    final cancelledAfterLockout = _resultIfCancelled(context, userId);
    if (cancelledAfterLockout != null) return cancelledAfterLockout;

    if (lockoutState.isLockedOut) {
      return BiometricResult.lockedOut(lockedUntil: lockoutState.lockedUntil!);
    }

    // Try fallback chain
    final fallbackResult = await _fallbackChain.execute(
      reason: reason,
      userId: userId,
    );
    final cancelledAfterFallback = _resultIfCancelled(context, userId);
    if (cancelledAfterFallback != null) return cancelledAfterFallback;

    return switch (fallbackResult) {
      FallbackSuccessOutcome(:final authMethod) => await _handleSuccess(
        userId: userId,
        method: authMethod,
        context: context,
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
    required _AuthRunContext context,
  }) async {
    final cancelled = _resultIfCancelled(context, userId);
    if (cancelled != null) return cancelled;

    if (config.fallbackChain.isNotEmpty) {
      final fallbackResult = await _fallbackChain.execute(
        reason: reason,
        userId: userId,
      );
      final cancelledAfterFallback = _resultIfCancelled(context, userId);
      if (cancelledAfterFallback != null) return cancelledAfterFallback;

      return switch (fallbackResult) {
        FallbackSuccessOutcome(:final authMethod) => await _handleSuccess(
          userId: userId,
          method: authMethod,
          context: context,
        ),
        FallbackCancelledOutcome() => _handleCancelled(userId),
        FallbackExhaustedOutcome() => BiometricResult.unavailable(
          reason: unavailableReason,
        ),
      };
    }

    return BiometricResult.unavailable(reason: unavailableReason);
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

  // ═══════════════════════════════════════════════════════════
  // Private — Utilities
  // ═══════════════════════════════════════════════════════════

  BiometricResult _timeoutResult(String? userId, _AuthRunContext context) {
    if (context.cancel()) {
      _emitEvent(BiometricEventType.authTimeout, userId);
      _log('authenticate() timed out after ${config.authenticationTimeout}');
    }
    return const BiometricResult.error(
      message: 'Authentication timed out',
      cause: null,
    );
  }

  BiometricResult? _resultIfCancelled(
    _AuthRunContext? context,
    String? userId,
  ) {
    if (context == null || !context.isCancelled) return null;
    return _timeoutResult(userId, context);
  }

  Duration _effectiveSessionDuration(BiometricPolicy? policy) {
    final policyDuration = policy?.maxSessionDuration;
    if (policyDuration == null) return config.sessionDuration;
    return policyDuration < config.sessionDuration
        ? policyDuration
        : config.sessionDuration;
  }

  int _effectiveMaxAttempts(BiometricPolicy? policy) {
    final policyAttempts = policy?.maxAttempts;
    if (policyAttempts == null || policyAttempts <= 0) {
      return config.maxAttempts;
    }
    return policyAttempts < config.maxAttempts
        ? policyAttempts
        : config.maxAttempts;
  }

  Duration _effectiveLockoutDuration(BiometricPolicy? policy) {
    final policyDuration = policy?.lockoutDuration;
    if (policyDuration == null) return config.lockoutDuration;
    return policyDuration > config.lockoutDuration
        ? policyDuration
        : config.lockoutDuration;
  }

  bool _isSessionValidForDuration(
    BiometricSession session,
    Duration effectiveSessionDuration,
  ) {
    if (!session.isActive) return false;
    final now = DateTime.now().toUtc();
    final sessionExpiryByPolicy = session.authenticatedAt.toUtc().add(
      effectiveSessionDuration,
    );
    final effectiveExpiry = sessionExpiryByPolicy.isBefore(session.expiresAt)
        ? sessionExpiryByPolicy
        : session.expiresAt;
    return now.isBefore(effectiveExpiry);
  }

  void _emitEvent(
    BiometricEventType type,
    String? userId, {
    Map<String, dynamic> properties = const {},
  }) {
    config.onEvent?.call(
      BiometricEvent(
        type: type,
        userId: userId ?? config.defaultUserId ?? '_device_default_',
        timestamp: DateTime.now().toUtc(),
        properties: Map<String, dynamic>.unmodifiable(properties),
      ),
    );
  }

  /// Log a message when [BiometricConfig.verbose] is enabled.
  void _log(String message) {
    if (config.verbose) {
      // ignore: avoid_print
      print('[BiometricShield] $message');
    }
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
  error,
}

class _AuthRunContext {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  bool cancel() {
    if (_cancelled) return false;
    _cancelled = true;
    return true;
  }
}

// ═══════════════════════════════════════════════════════════
// Interface for DI & Mock Substitution
// ═══════════════════════════════════════════════════════════

/// Contract for [BiometricShield] that enables proper dependency injection
/// and mock substitution in tests.
///
/// Implement or mock this interface instead of depending on the concrete
/// [BiometricShield] class directly:
///
/// ```dart
/// class AuthService {
///   AuthService(this._shield);
///   final BiometricShieldInterface _shield;
///
///   Future<bool> login() async {
///     final result = await _shield.authenticate(reason: 'Login');
///     return result is BiometricSuccess;
///   }
/// }
/// ```
abstract class BiometricShieldInterface {
  /// The configuration this instance was created with.
  BiometricConfig get config;

  /// User-facing preferences (enable/disable biometric, remember me, etc).
  BiometricPreferences get preferences;

  /// Trigger the full authentication flow including fallbacks.
  ///
  /// See [BiometricShield.authenticate] for full documentation.
  Future<BiometricResult> authenticate({
    required String reason,
    String? userId,
    bool requireFresh = false,
  });

  /// Check if a valid (non-expired) session exists without prompting.
  Future<bool> hasValidSession({String? userId});

  /// Validate session silently; only prompt if session has expired.
  Future<BiometricResult> validateOrAuthenticate({
    required String reason,
    String? userId,
  });

  /// Check whether biometric enrollment has been completed on this device.
  Future<bool> isEnrolled();

  /// Guide the user to enroll biometrics (checks enrollment status).
  Future<bool> enroll({String? userId});

  /// End the current session (e.g. on logout).
  Future<void> clearSession({String? userId});

  /// Clear all stored tokens and session state for a user.
  Future<void> clearAll({String? userId});

  /// Get a reactive stream of session state changes.
  Stream<BiometricSession?> sessionStream({String? userId});

  /// Notify the SDK of user activity (extends session if configured).
  void onActivity({String? userId});

  /// Detect what biometric capabilities this device has.
  Future<BiometricCapability> getCapability();

  /// Store a token securely, namespaced to userId.
  Future<void> storeToken(String token, {String? userId});

  /// Retrieve the stored token for a user.
  Future<String?> getToken({String? userId});

  /// Check if the user is currently locked out.
  Future<LockoutState> getLockoutState({String? userId});

  /// Manually reset lockout (e.g. after admin override).
  Future<void> resetLockout({String? userId});

  /// Clean up resources (close streams, timers, etc).
  void dispose();

  /// Dispose resources for a single user without shutting down the SDK.
  Future<void> disposeUser({required String userId});
}

/// Base class for mock implementations used in testing.
///
/// Extend this to create test doubles for [BiometricShield].
/// Unlike the old static API, tests now pass a mock instance directly
/// to the code under test (dependency injection pattern).
abstract class BiometricShieldMockBase {
  BiometricConfig get config;
}
