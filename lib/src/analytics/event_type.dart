/// All event types emitted by the BiometricShield SDK.
///
/// Subscribe to these via [BiometricConfig.onEvent] to pipe
/// into your analytics or HIPAA audit store.
enum BiometricEventType {
  /// Biometric authentication was attempted.
  authAttempted,

  /// Biometric authentication succeeded.
  authSucceeded,

  /// Biometric authentication failed (wrong finger, face mismatch, etc).
  authFailed,

  /// User explicitly cancelled the biometric prompt.
  authCancelled,

  /// A fallback method was triggered after biometric failure.
  fallbackTriggered,

  /// A fallback method succeeded.
  fallbackSucceeded,

  /// A fallback method failed.
  fallbackFailed,

  /// A new session was created after successful auth.
  sessionStarted,

  /// An existing session expired.
  sessionExpired,

  /// A session was explicitly cleared (e.g. logout).
  sessionCleared,

  /// User was locked out after exceeding max attempts.
  lockoutStarted,

  /// A lockout period ended (expired naturally).
  lockoutEnded,

  /// A lockout was manually reset (e.g. admin override).
  lockoutReset,

  /// Biometric keys were invalidated (new fingerprint enrolled, etc).
  biometricInvalidated,

  /// A token was stored in secure storage.
  tokenStored,

  /// A token was retrieved from secure storage.
  tokenRetrieved,

  /// A stored token was found to be expired.
  tokenExpired,

  /// A stored token was cleared from secure storage.
  tokenCleared,

  /// Device biometric capabilities were queried.
  capabilityChecked,

  /// The authentication flow exceeded [BiometricConfig.authenticationTimeout].
  authTimeout,

  /// [PolicyProvider.getPolicy] failed (network error, timeout, etc).
  policyFetchFailed,

  /// User completed biometric enrollment.
  enrolled,

  /// User declined biometric enrollment.
  enrollmentDeclined,
}
