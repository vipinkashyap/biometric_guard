/// All event types emitted by the BiometricShield SDK.
///
/// Subscribe to these via [BiometricConfig.onEvent] to pipe
/// into your analytics or HIPAA audit store.
enum BiometricEventType {
  authAttempted,
  authSucceeded,
  authFailed,
  fallbackTriggered,
  fallbackSucceeded,
  fallbackFailed,
  sessionStarted,
  sessionExpired,
  sessionCleared,
  lockoutStarted,
  lockoutEnded,
  lockoutReset,
  biometricInvalidated,
  tokenStored,
  tokenRetrieved,
  tokenExpired,
  tokenCleared,
  capabilityChecked,
}
