import '../core/biometric_session.dart';

/// Factory for creating fake [BiometricSession] instances in tests.
///
/// Provides convenient presets for common test scenarios.
class FakeBiometricSession {
  FakeBiometricSession._();

  /// An active, non-expired session.
  static BiometricSession active({
    String sessionId = 'fake-session-001',
    String userId = 'test-user',
    BiometricAuthMethod method = BiometricAuthMethod.fingerprint,
    Duration validity = const Duration(minutes: 15),
  }) {
    final now = DateTime.now();
    return BiometricSession(
      sessionId: sessionId,
      userId: userId,
      authenticatedAt: now,
      expiresAt: now.add(validity),
      methodUsed: method,
      isActive: true,
    );
  }

  /// An expired session.
  static BiometricSession expired({
    String sessionId = 'fake-session-expired',
    String userId = 'test-user',
    BiometricAuthMethod method = BiometricAuthMethod.fingerprint,
  }) {
    final past = DateTime.now().subtract(const Duration(hours: 1));
    return BiometricSession(
      sessionId: sessionId,
      userId: userId,
      authenticatedAt: past.subtract(const Duration(minutes: 15)),
      expiresAt: past,
      methodUsed: method,
      isActive: false,
    );
  }

  /// A session that's about to expire (1 second remaining).
  static BiometricSession aboutToExpire({
    String sessionId = 'fake-session-expiring',
    String userId = 'test-user',
    BiometricAuthMethod method = BiometricAuthMethod.fingerprint,
  }) {
    final now = DateTime.now();
    return BiometricSession(
      sessionId: sessionId,
      userId: userId,
      authenticatedAt: now.subtract(const Duration(minutes: 14, seconds: 59)),
      expiresAt: now.add(const Duration(seconds: 1)),
      methodUsed: method,
      isActive: true,
    );
  }

  /// A Face ID session.
  static BiometricSession faceID({
    String sessionId = 'fake-session-faceid',
    String userId = 'test-user',
    Duration validity = const Duration(minutes: 15),
  }) =>
      active(
        sessionId: sessionId,
        userId: userId,
        method: BiometricAuthMethod.faceID,
        validity: validity,
      );

  /// A device credential (PIN/pattern) session.
  static BiometricSession deviceCredential({
    String sessionId = 'fake-session-credential',
    String userId = 'test-user',
    Duration validity = const Duration(minutes: 15),
  }) =>
      active(
        sessionId: sessionId,
        userId: userId,
        method: BiometricAuthMethod.deviceCredential,
        validity: validity,
      );
}
