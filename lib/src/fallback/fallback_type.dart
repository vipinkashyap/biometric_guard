/// Available fallback authentication methods when biometric auth
/// fails or is unavailable.
enum BiometricFallback {
  /// Use the device's own PIN / pattern / password prompt (recommended default).
  deviceCredential,

  /// Show a custom PIN UI provided via [BiometricConfig.customPinBuilder].
  customPin,

  /// Show a custom password UI provided via [BiometricConfig.customPinBuilder].
  customPassword,

  /// Do not fall back — surface [BiometricResult.unavailable] immediately.
  none,
}
