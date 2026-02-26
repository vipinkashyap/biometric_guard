import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;

import '../core/biometric_session.dart';

/// Handles Android-specific biometric authentication.
///
/// Supports both Class 3 (strong) and Class 2 (weak) biometric
/// via the [BiometricPrompt] API (SDK 28+), with fallback to
/// the legacy fingerprint API for older devices.
class AndroidHandler {

  AndroidHandler({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();
  final LocalAuthentication _localAuth;

  /// Attempt biometric authentication on Android.
  Future<AndroidAuthOutcome> authenticate({
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
        return AndroidAuthOutcome.success;
      } else {
        return AndroidAuthOutcome.failed;
      }
    } on Exception catch (e) {
      final errorString = e.toString();

      if (errorString.contains(auth_error.notAvailable)) {
        return AndroidAuthOutcome.notAvailable;
      }
      if (errorString.contains(auth_error.notEnrolled)) {
        return AndroidAuthOutcome.notEnrolled;
      }
      if (errorString.contains(auth_error.passcodeNotSet)) {
        return AndroidAuthOutcome.passcodeNotSet;
      }
      if (errorString.contains(auth_error.lockedOut) ||
          errorString.contains(auth_error.permanentlyLockedOut)) {
        return AndroidAuthOutcome.lockedOut;
      }

      return AndroidAuthOutcome.error;
    }
  }

  /// Determine the [BiometricAuthMethod] for Android based on available biometrics.
  Future<BiometricAuthMethod> detectMethod() async {
    final biometrics = await _localAuth.getAvailableBiometrics();
    if (biometrics.contains(BiometricType.fingerprint)) {
      return BiometricAuthMethod.fingerprint;
    }
    if (biometrics.contains(BiometricType.face)) {
      // Some Android devices have face recognition (iris on Samsung etc)
      return BiometricAuthMethod.iris;
    }
    return BiometricAuthMethod.fingerprint; // default on Android
  }
}

/// Raw outcome of an Android biometric authentication attempt.
enum AndroidAuthOutcome {
  success,
  failed,
  cancelled,
  notAvailable,
  notEnrolled,
  passcodeNotSet,
  lockedOut,
  error,
}
