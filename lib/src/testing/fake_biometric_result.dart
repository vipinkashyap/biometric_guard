import '../core/biometric_result.dart';
import '../core/biometric_session.dart';
import '../fallback/fallback_type.dart';
import 'fake_biometric_session.dart';

/// Factory for creating [BiometricResult] instances for common test scenarios.
class FakeBiometricResult {
  FakeBiometricResult._();

  /// A successful biometric authentication.
  static BiometricResult success({
    BiometricSession? session,
    String? token = 'fake-token',
  }) =>
      BiometricResult.success(
        session: session ?? FakeBiometricSession.active(),
        token: token,
      );

  /// A successful fallback authentication.
  static BiometricResult fallbackSuccess({
    BiometricFallback method = BiometricFallback.deviceCredential,
    BiometricSession? session,
    String? token = 'fake-token',
  }) =>
      BiometricResult.fallbackSuccess(
        methodUsed: method,
        session: session ?? FakeBiometricSession.deviceCredential(),
        token: token,
      );

  /// An existing valid session.
  static BiometricResult sessionValid({
    BiometricSession? session,
    String? token = 'fake-token',
  }) =>
      BiometricResult.sessionValid(
        session: session ?? FakeBiometricSession.active(),
        token: token,
      );

  /// Token expired result.
  static BiometricResult tokenExpired() =>
      const BiometricResult.tokenExpired();

  /// User cancelled.
  static BiometricResult cancelled() =>
      const BiometricResult.cancelled();

  /// Locked out for 5 minutes.
  static BiometricResult lockedOut({
    Duration lockoutDuration = const Duration(minutes: 5),
  }) =>
      BiometricResult.lockedOut(
        lockedUntil: DateTime.now().add(lockoutDuration),
      );

  /// Biometric unavailable.
  static BiometricResult unavailable({
    BiometricUnavailableReason reason =
        BiometricUnavailableReason.notEnrolled,
  }) =>
      BiometricResult.unavailable(reason: reason);

  /// Biometric keys invalidated.
  static BiometricResult invalidated() =>
      const BiometricResult.invalidated();

  /// Re-authentication required (refresh token expired).
  static BiometricResult reauthenticationRequired({
    String? reason = 'Test: refresh token expired',
  }) =>
      BiometricResult.reauthenticationRequired(reason: reason);

  /// Platform error.
  static BiometricResult error({
    String message = 'Test error',
    Object? cause,
  }) =>
      BiometricResult.error(message: message, cause: cause);
}
