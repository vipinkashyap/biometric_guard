/// String overrides for all user-facing text in the SDK.
///
/// Pass this via [BiometricConfig.strings] to customize copy
/// for localization or branding.
class BiometricStrings {

  const BiometricStrings({
    this.authReason,
    this.cancelButton,
    this.useFallbackButton,
    this.lockoutTitle,
    this.lockoutMessage,
    this.biometricUnavailableTitle,
    this.biometricUnavailableMessage,
    this.biometricInvalidatedTitle,
    this.biometricInvalidatedMessage,
  });
  /// Fallback auth reason if none is passed to [authenticate()].
  final String? authReason;

  /// Label for the cancel button.
  final String? cancelButton;

  /// Label for the "use fallback" button.
  final String? useFallbackButton;

  /// Title shown on the lockout screen.
  final String? lockoutTitle;

  /// Message shown on the lockout screen. Receives remaining duration.
  final String Function(Duration remaining)? lockoutMessage;

  /// Title shown when biometric is unavailable.
  final String? biometricUnavailableTitle;

  /// Message shown when biometric is unavailable.
  final String? biometricUnavailableMessage;

  /// Title shown when biometric keys are invalidated.
  final String? biometricInvalidatedTitle;

  /// Message shown when biometric keys are invalidated.
  final String? biometricInvalidatedMessage;
}
