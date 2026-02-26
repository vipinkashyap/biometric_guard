import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;

import '../core/biometric_result.dart';
import '../core/biometric_session.dart';

/// Handles iOS-specific biometric authentication (Face ID / Touch ID).
class IOSHandler {
  final LocalAuthentication _localAuth;

  IOSHandler({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

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
        options: AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: biometricOnly,
        ),
      );

      if (didAuthenticate) {
        return IOSAuthOutcome.success;
      } else {
        return IOSAuthOutcome.failed;
      }
    } on Exception catch (e) {
      final errorString = e.toString();

      if (errorString.contains(auth_error.notAvailable)) {
        return IOSAuthOutcome.notAvailable;
      }
      if (errorString.contains(auth_error.notEnrolled)) {
        return IOSAuthOutcome.notEnrolled;
      }
      if (errorString.contains(auth_error.passcodeNotSet)) {
        return IOSAuthOutcome.passcodeNotSet;
      }
      if (errorString.contains(auth_error.lockedOut) ||
          errorString.contains(auth_error.permanentlyLockedOut)) {
        return IOSAuthOutcome.lockedOut;
      }

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
  success,
  failed,
  cancelled,
  notAvailable,
  notEnrolled,
  passcodeNotSet,
  lockedOut,
  error,
}
