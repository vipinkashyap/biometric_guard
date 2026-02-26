import '../core/biometric_config.dart';
import '../core/biometric_result.dart';
import '../core/biometric_session.dart';
import '../core/biometric_shield.dart';
import '../platform/biometric_capability.dart';
import '../session/lockout_state.dart';

/// A base mock implementation of the BiometricShield API for testing.
///
/// Create an instance with predefined results and pass it to your code
/// under test (dependency injection pattern).
///
/// ```dart
/// final mockShield = BiometricShieldMock(
///   authenticateResult: BiometricResult.success(
///     session: FakeBiometricSession.active(),
///     token: 'fake-token',
///   ),
/// );
/// // Pass mockShield to code under test instead of real BiometricShield
/// ```
class BiometricShieldMock extends BiometricShieldMockBase {
  BiometricShieldMock({
    BiometricConfig? config,
    this.authenticateResult = const BiometricResult.cancelled(),
    this.hasValidSessionResult = false,
    BiometricCapability? capabilityResult,
    this.tokenResult,
    LockoutState? lockoutStateResult,
    this.sessionStreamResult,
  })  : config = config ?? const BiometricConfig(),
        capabilityResult = capabilityResult ??
            const BiometricCapability(
              isEnrolled: true,
              hasStrongBiometric: true,
              biometricLabel: 'Fingerprint',
            ),
        lockoutStateResult = lockoutStateResult ??
            const LockoutState(
              isLockedOut: false,
              currentAttemptCount: 0,
              maxAttempts: 3,
            );

  @override
  final BiometricConfig config;

  /// Result returned by [authenticate] and [validateOrAuthenticate].
  final BiometricResult authenticateResult;

  /// Result returned by [hasValidSession].
  final bool hasValidSessionResult;

  /// Result returned by [getCapability].
  final BiometricCapability capabilityResult;

  /// Result returned by [getToken].
  final String? tokenResult;

  /// Result returned by [getLockoutState].
  final LockoutState lockoutStateResult;

  /// Result returned by [sessionStream].
  final BiometricSession? sessionStreamResult;

  /// Tracks calls to [authenticate].
  final List<AuthenticateCall> authenticateCalls = [];

  /// Tracks calls to [storeToken].
  final List<String> storedTokens = [];

  /// Tracks calls to [onActivity].
  final List<String?> onActivityCalls = [];

  /// Simulate [BiometricShield.authenticate].
  Future<BiometricResult> authenticate({
    required String reason,
    String? userId,
    bool requireFresh = false,
  }) async {
    authenticateCalls.add(AuthenticateCall(
      reason: reason,
      userId: userId,
      requireFresh: requireFresh,
    ));
    return authenticateResult;
  }

  /// Simulate [BiometricShield.hasValidSession].
  Future<bool> hasValidSession({String? userId}) async {
    return hasValidSessionResult;
  }

  /// Simulate [BiometricShield.validateOrAuthenticate].
  Future<BiometricResult> validateOrAuthenticate({
    required String reason,
    String? userId,
  }) async {
    return authenticate(reason: reason, userId: userId);
  }

  /// Simulate [BiometricShield.getCapability].
  Future<BiometricCapability> getCapability() async {
    return capabilityResult;
  }

  /// Simulate [BiometricShield.getToken].
  Future<String?> getToken({String? userId}) async {
    return tokenResult;
  }

  /// Simulate [BiometricShield.getLockoutState].
  Future<LockoutState> getLockoutState({String? userId}) async {
    return lockoutStateResult;
  }

  /// Simulate [BiometricShield.storeToken].
  Future<void> storeToken(String token, {String? userId}) async {
    storedTokens.add(token);
  }

  /// Simulate [BiometricShield.clearSession].
  Future<void> clearSession({String? userId}) async {
    // No-op
  }

  /// Simulate [BiometricShield.clearAll].
  Future<void> clearAll({String? userId}) async {
    // No-op
  }

  /// Simulate [BiometricShield.sessionStream].
  Stream<BiometricSession?> sessionStream({String? userId}) async* {
    yield sessionStreamResult;
  }

  /// Simulate [BiometricShield.onActivity].
  void onActivity({String? userId}) {
    onActivityCalls.add(userId);
  }

  /// Simulate [BiometricShield.resetLockout].
  Future<void> resetLockout({String? userId}) async {
    // No-op
  }

  /// Simulate [BiometricShield.dispose].
  void dispose() {
    // No-op
  }

  /// Reset all tracked calls.
  void resetCalls() {
    authenticateCalls.clear();
    storedTokens.clear();
    onActivityCalls.clear();
  }
}

/// Records a call to [authenticate] for verification in tests.
class AuthenticateCall {
  const AuthenticateCall({
    required this.reason,
    this.userId,
    this.requireFresh = false,
  });

  final String reason;
  final String? userId;
  final bool requireFresh;
}
