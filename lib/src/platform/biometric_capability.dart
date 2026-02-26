/// Rich capability model describing what biometric features
/// are available on the current device.
///
/// Platform-honest — exposes capabilities as structured data,
/// not a single boolean, so callers can make informed UI decisions.
class BiometricCapability {

  const BiometricCapability({
    this.hasFaceID = false,
    this.hasTouchID = false,
    this.hasStrongBiometric = false,
    this.hasWeakBiometric = false,
    this.isEnrolled = false,
    this.supportsDeviceCredential = false,
    this.biometricLabel = 'Biometric',
  });
  /// iOS: true if Face ID is the primary biometric.
  final bool hasFaceID;

  /// iOS: true if Touch ID is the primary biometric.
  final bool hasTouchID;

  /// Android: Class 3 (strong) biometric available.
  final bool hasStrongBiometric;

  /// Android: Class 2 (weak) biometric available.
  final bool hasWeakBiometric;

  /// Whether the user has enrolled any biometric on the device.
  final bool isEnrolled;

  /// Whether device credential (PIN/pattern/password) is set.
  final bool supportsDeviceCredential;

  /// Human-readable label for the available biometric
  /// e.g. "Face ID", "Fingerprint", "Biometric".
  final String biometricLabel;

  /// Whether any biometric method is available (enrolled and hardware present).
  bool get hasBiometric =>
      hasFaceID || hasTouchID || hasStrongBiometric || hasWeakBiometric;

  /// Whether any form of authentication is possible
  /// (biometric or device credential).
  bool get canAuthenticate => (hasBiometric && isEnrolled) || supportsDeviceCredential;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BiometricCapability &&
          hasFaceID == other.hasFaceID &&
          hasTouchID == other.hasTouchID &&
          hasStrongBiometric == other.hasStrongBiometric &&
          hasWeakBiometric == other.hasWeakBiometric &&
          isEnrolled == other.isEnrolled &&
          supportsDeviceCredential == other.supportsDeviceCredential &&
          biometricLabel == other.biometricLabel;

  @override
  int get hashCode => Object.hash(
        hasFaceID, hasTouchID, hasStrongBiometric, hasWeakBiometric,
        isEnrolled, supportsDeviceCredential, biometricLabel,
      );

  @override
  String toString() =>
      'BiometricCapability(label: $biometricLabel, enrolled: $isEnrolled, '
      'faceID: $hasFaceID, touchID: $hasTouchID, '
      'strong: $hasStrongBiometric, weak: $hasWeakBiometric, '
      'deviceCredential: $supportsDeviceCredential)';
}
