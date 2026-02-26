import 'package:flutter/widgets.dart';

import '../core/biometric_config.dart';
import '../core/biometric_result.dart';
import '../core/biometric_shield.dart';
import '../platform/biometric_capability.dart';
import '../session/lockout_state.dart';

/// A full mock implementation of the BiometricShield API for testing.
///
/// Configure the mock with predefined results, then call
/// [BiometricShield.configureMock] to inject it.
///
/// ```dart
/// BiometricShield.configureMock(BiometricShieldMock(
///   authenticateResult: BiometricResult.success(
///     session: FakeBiometricSession.active(),
///     token: 'fake-token',
///   ),
/// ));
/// ```
class BiometricShieldMock extends BiometricShieldMockBase {
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

  /// Tracks calls to [authenticate].
  final List<AuthenticateCall> authenticateCalls = [];

  /// Tracks calls to [storeToken].
  final List<String> storedTokens = [];

  BiometricShieldMock({
    BiometricConfig? config,
    this.authenticateResult = const BiometricResult.cancelled(),
    this.hasValidSessionResult = false,
    BiometricCapability? capabilityResult,
    this.tokenResult,
    LockoutState? lockoutStateResult,
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

  /// Simulate [BiometricShield.authenticate].
  Future<BiometricResult> authenticate({
    required String reason,
    String? userId,
    BuildContext? context,
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

  /// Reset all tracked calls.
  void resetCalls() {
    authenticateCalls.clear();
    storedTokens.clear();
  }
}

/// Records a call to [authenticate] for verification in tests.
class AuthenticateCall {
  final String reason;
  final String? userId;
  final bool requireFresh;

  const AuthenticateCall({
    required this.reason,
    this.userId,
    this.requireFresh = false,
  });
}
