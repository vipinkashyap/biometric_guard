import 'biometric_session.dart';
import '../fallback/fallback_type.dart';

/// Reason why biometric authentication is unavailable on this device.
enum BiometricUnavailableReason {
  /// Device supports biometric but user hasn't enrolled any.
  notEnrolled,

  /// Biometric hardware not present on this device.
  notSupported,

  /// Device has no secure lock screen set.
  passcodeNotSet,

  /// Too many system-level failures; temporarily unavailable.
  temporarilyUnavailable,
}

/// Sealed result type for all biometric authentication outcomes.
///
/// All public authentication methods return this type. No exceptions
/// are thrown — callers use pattern matching to handle each case.
sealed class BiometricResult {
  const BiometricResult();

  /// Biometric auth succeeded. Session is now active.
  const factory BiometricResult.success({
    required BiometricSession session,
    required String? token,
  }) = BiometricSuccess;

  /// Biometric failed but a fallback succeeded.
  const factory BiometricResult.fallbackSuccess({
    required BiometricFallback methodUsed,
    required BiometricSession session,
    required String? token,
  }) = BiometricFallbackSuccess;

  /// Active session was found — no prompt shown.
  const factory BiometricResult.sessionValid({
    required BiometricSession session,
    required String? token,
  }) = BiometricSessionValid;

  /// Auth succeeded but token was expired or missing.
  /// [BiometricConfig.onTokenExpired] callback has been called if configured.
  const factory BiometricResult.tokenExpired() = BiometricTokenExpired;

  /// User explicitly cancelled authentication.
  const factory BiometricResult.cancelled() = BiometricCancelled;

  /// Max attempts exceeded. User is locked out.
  const factory BiometricResult.lockedOut({
    required DateTime lockedUntil,
  }) = BiometricLockedOut;

  /// Biometric is not available or not enrolled on this device.
  const factory BiometricResult.unavailable({
    required BiometricUnavailableReason reason,
  }) = BiometricUnavailable;

  /// Biometric keys were invalidated (new fingerprint enrolled etc).
  const factory BiometricResult.invalidated() = BiometricInvalidated;

  /// An unexpected platform error occurred.
  const factory BiometricResult.error({
    required String message,
    required Object? cause,
  }) = BiometricError;

  /// Pattern-match on all possible outcomes.
  T when<T>({
    required T Function(BiometricSession session, String? token) success,
    required T Function(BiometricFallback methodUsed, BiometricSession session, String? token) fallbackSuccess,
    required T Function(BiometricSession session, String? token) sessionValid,
    required T Function() tokenExpired,
    required T Function() cancelled,
    required T Function(DateTime lockedUntil) lockedOut,
    required T Function(BiometricUnavailableReason reason) unavailable,
    required T Function() invalidated,
    required T Function(String message, Object? cause) error,
  }) {
    final self = this;
    return switch (self) {
      BiometricSuccess() => success(self.session, self.token),
      BiometricFallbackSuccess() => fallbackSuccess(self.methodUsed, self.session, self.token),
      BiometricSessionValid() => sessionValid(self.session, self.token),
      BiometricTokenExpired() => tokenExpired(),
      BiometricCancelled() => cancelled(),
      BiometricLockedOut() => lockedOut(self.lockedUntil),
      BiometricUnavailable() => unavailable(self.reason),
      BiometricInvalidated() => invalidated(),
      BiometricError() => error(self.message, self.cause),
    };
  }
}

/// Biometric auth succeeded. Session is now active.
class BiometricSuccess extends BiometricResult {

  const BiometricSuccess({
    required this.session,
    required this.token,
  });
  final BiometricSession session;
  final String? token;
}

/// Biometric failed but a fallback succeeded.
class BiometricFallbackSuccess extends BiometricResult {

  const BiometricFallbackSuccess({
    required this.methodUsed,
    required this.session,
    required this.token,
  });
  final BiometricFallback methodUsed;
  final BiometricSession session;
  final String? token;
}

/// Active session was found — no prompt shown.
class BiometricSessionValid extends BiometricResult {

  const BiometricSessionValid({
    required this.session,
    required this.token,
  });
  final BiometricSession session;
  final String? token;
}

/// Auth succeeded but token was expired or missing.
class BiometricTokenExpired extends BiometricResult {
  const BiometricTokenExpired();
}

/// User explicitly cancelled authentication.
class BiometricCancelled extends BiometricResult {
  const BiometricCancelled();
}

/// Max attempts exceeded. User is locked out.
class BiometricLockedOut extends BiometricResult {

  const BiometricLockedOut({
    required this.lockedUntil,
  });
  final DateTime lockedUntil;
}

/// Biometric is not available or not enrolled on this device.
class BiometricUnavailable extends BiometricResult {

  const BiometricUnavailable({
    required this.reason,
  });
  final BiometricUnavailableReason reason;
}

/// Biometric keys were invalidated (new fingerprint enrolled etc).
class BiometricInvalidated extends BiometricResult {
  const BiometricInvalidated();
}

/// An unexpected platform error occurred.
class BiometricError extends BiometricResult {

  const BiometricError({
    required this.message,
    required this.cause,
  });
  final String message;
  final Object? cause;
}
