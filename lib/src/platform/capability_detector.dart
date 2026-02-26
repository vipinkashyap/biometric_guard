import 'package:universal_io/io.dart';

import 'package:local_auth/local_auth.dart';

import 'biometric_capability.dart';

/// Detects biometric capabilities of the current device.
///
/// Uses [local_auth] under the hood and translates platform-specific
/// results into a unified [BiometricCapability] model.
class CapabilityDetector {

  CapabilityDetector({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();
  final LocalAuthentication _localAuth;

  /// Queries the device for all biometric capabilities.
  Future<BiometricCapability> detect() async {
    try {
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final availableBiometrics = await _localAuth.getAvailableBiometrics();

      final hasFaceID = availableBiometrics.contains(BiometricType.face);
      final hasFingerprint =
          availableBiometrics.contains(BiometricType.fingerprint);
      final hasStrong = availableBiometrics.contains(BiometricType.strong);
      final hasWeak = availableBiometrics.contains(BiometricType.weak);

      // Determine platform-specific capabilities
      final isIOS = Platform.isIOS;

      return BiometricCapability(
        hasFaceID: isIOS && hasFaceID,
        hasTouchID: isIOS && hasFingerprint,
        hasStrongBiometric: !isIOS && (hasStrong || hasFingerprint),
        hasWeakBiometric: !isIOS && hasWeak,
        isEnrolled: canCheckBiometrics && availableBiometrics.isNotEmpty,
        supportsDeviceCredential: isDeviceSupported,
        biometricLabel: _resolveBiometricLabel(
          isIOS: isIOS,
          hasFaceID: hasFaceID,
          hasFingerprint: hasFingerprint,
          hasStrong: hasStrong,
        ),
      );
    } catch (e) {
      // If detection fails, return a safe default
      return const BiometricCapability();
    }
  }

  String _resolveBiometricLabel({
    required bool isIOS,
    required bool hasFaceID,
    required bool hasFingerprint,
    required bool hasStrong,
  }) {
    if (isIOS) {
      if (hasFaceID) return 'Face ID';
      if (hasFingerprint) return 'Touch ID';
      return 'Biometric';
    }
    // Android
    if (hasFingerprint) return 'Fingerprint';
    if (hasStrong) return 'Biometric';
    return 'Biometric';
  }
}
