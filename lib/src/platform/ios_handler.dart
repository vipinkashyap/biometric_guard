import 'package:local_auth/local_auth.dart';

import '../core/biometric_session.dart';

/// Handles iOS-specific biometric authentication (Face ID / Touch ID).
class IOSHandler {

  IOSHandler({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();
  final LocalAuthentication _localAuth;

  /// Attempt biometric authentication on iOS.
  ///
  /// Returns a raw result indicating success, cancellation, or failure.
  /// Session creation is handled by the caller.
  Future<IOSAuthOutcome> authenticate({
    required String reason,
    bool biometricOnly = true,
  }) async {
    try {
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
        biometricOnly: biometricOnly,
      );

      if (didAuthenticate) {
        return IOSAuthOutcome.success;
      } else {
        return IOSAuthOutcome.failed;
      }
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
          IOSAuthOutcome.notAvailable,
        LocalAuthExceptionCode.noBiometricsEnrolled =>
          IOSAuthOutcome.notEnrolled,
        LocalAuthExceptionCode.noCredentialsSet =>
          IOSAuthOutcome.passcodeNotSet,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout =>
          IOSAuthOutcome.lockedOut,
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback =>
          IOSAuthOutcome.cancelled,
        _ => IOSAuthOutcome.error,
      };
    } on Exception catch (_) {
      return IOSAuthOutcome.error;
    }
  }

  /// Determine the [BiometricAuthMethod] for iOS based on available biometrics.
  Future<BiometricAuthMethod> detectMethod() async {
    final biometrics = await _localAuth.getAvailableBiometrics();
    if (biometrics.contains(BiometricType.face)) {
      return BiometricAuthMethod.faceID;
    }
    if (biometrics.contains(BiometricType.fingerprint)) {
      return BiometricAuthMethod.touchID;
    }
    return BiometricAuthMethod.faceID; // default on modern iOS
  }
}

/// Raw outcome of an iOS biometric authentication attempt.
enum IOSAuthOutcome {
  /// Authentication succeeded (Face ID or Touch ID matched).
  success,

  /// Authentication failed (biometric did not match).
  failed,

  /// User or system cancelled the authentication prompt.
  cancelled,

  /// Biometric hardware is not available on this device.
  notAvailable,

  /// No biometric data is enrolled on this device.
  notEnrolled,

  /// No device passcode is set (required for biometric).
  passcodeNotSet,

  /// Too many failed attempts; device-level lockout active.
  lockedOut,

  /// An unexpected platform error occurred.
  error,
}
