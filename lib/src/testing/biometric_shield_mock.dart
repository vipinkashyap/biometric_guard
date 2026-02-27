import '../core/biometric_config.dart';
import '../core/biometric_preferences.dart';
import '../core/biometric_result.dart';
import '../core/biometric_session.dart';
import '../core/biometric_shield.dart';
import '../platform/biometric_capability.dart';
import '../session/lockout_state.dart';

/// A mock implementation of [BiometricShieldInterface] for testing.
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
class BiometricShieldMock implements BiometricShieldInterface {
  BiometricShieldMock({
    BiometricConfig? config,
    this.authenticateResult = const BiometricResult.cancelled(),
    this.hasValidSessionResult = false,
    BiometricCapability? capabilityResult,
    this.tokenResult,
    LockoutState? lockoutStateResult,
    this.sessionStreamResult,
    this.isEnrolledResult = true,
    this.enrollResult = true,
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

  /// Result returned by [isEnrolled].
  final bool isEnrolledResult;

  /// Result returned by [enroll].
  final bool enrollResult;

  /// Tracks calls to [authenticate].
  final List<AuthenticateCall> authenticateCalls = [];

  /// Tracks calls to [storeToken].
  final List<String> storedTokens = [];

  /// Tracks calls to [onActivity].
  final List<String?> onActivityCalls = [];

  /// Tracks calls to [disposeUser].
  final List<String> disposedUsers = [];

  @override
  BiometricPreferences get preferences => BiometricPreferences();

  /// Simulate [BiometricShield.authenticate].
  @override
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
  @override
  Future<bool> hasValidSession({String? userId}) async {
    return hasValidSessionResult;
  }

  /// Simulate [BiometricShield.validateOrAuthenticate].
  @override
  Future<BiometricResult> validateOrAuthenticate({
    required String reason,
    String? userId,
  }) async {
    return authenticate(reason: reason, userId: userId);
  }

  /// Simulate [BiometricShield.isEnrolled].
  @override
  Future<bool> isEnrolled() async {
    return isEnrolledResult;
  }

  /// Simulate [BiometricShield.enroll].
  @override
  Future<bool> enroll({String? userId}) async {
    return enrollResult;
  }

  /// Simulate [BiometricShield.getCapability].
  @override
  Future<BiometricCapability> getCapability() async {
    return capabilityResult;
  }

  /// Simulate [BiometricShield.getToken].
  @override
  Future<String?> getToken({String? userId}) async {
    return tokenResult;
  }

  /// Simulate [BiometricShield.getLockoutState].
  @override
  Future<LockoutState> getLockoutState({String? userId}) async {
    return lockoutStateResult;
  }

  /// Simulate [BiometricShield.storeToken].
  @override
  Future<void> storeToken(String token, {String? userId}) async {
    storedTokens.add(token);
  }

  /// Simulate [BiometricShield.clearSession].
  @override
  Future<void> clearSession({String? userId}) async {
    // No-op
  }

  /// Simulate [BiometricShield.clearAll].
  @override
  Future<void> clearAll({String? userId}) async {
    // No-op
  }

  /// Simulate [BiometricShield.sessionStream].
  @override
  Stream<BiometricSession?> sessionStream({String? userId}) async* {
    yield sessionStreamResult;
  }

  /// Simulate [BiometricShield.onActivity].
  @override
  void onActivity({String? userId}) {
    onActivityCalls.add(userId);
  }

  /// Simulate [BiometricShield.resetLockout].
  @override
  Future<void> resetLockout({String? userId}) async {
    // No-op
  }

  /// Simulate [BiometricShield.dispose].
  @override
  void dispose() {
    // No-op
  }

  /// Simulate [BiometricShield.disposeUser].
  @override
  Future<void> disposeUser({required String userId}) async {
    disposedUsers.add(userId);
  }

  /// Reset all tracked calls.
  void resetCalls() {
    authenticateCalls.clear();
    storedTokens.clear();
    onActivityCalls.clear();
    disposedUsers.clear();
  }
}

/// Records a call to [authenticate] for verification in tests.
class AuthenticateCall {
  const AuthenticateCall({
    required this.reason,
    this.userId,
    this.requireFresh = false,
  });

  /// The reason string passed to [authenticate].
  final String reason;

  /// The userId passed to [authenticate], if any.
  final String? userId;

  /// Whether [requireFresh] was set to true.
  final bool requireFresh;
}
