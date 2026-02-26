/// The authentication method used to establish a session.
enum BiometricAuthMethod {
  faceID,
  touchID,
  fingerprint,
  iris,
  deviceCredential,
  customPin,
  customPassword,
}

/// Represents an active biometric authentication session.
///
/// Created when authentication succeeds. Callers can inspect
/// [isExpired] and [remainingValidity] to decide whether to
/// trigger re-authentication.
class BiometricSession {

  const BiometricSession({
    required this.sessionId,
    required this.userId,
    required this.authenticatedAt,
    required this.expiresAt,
    required this.methodUsed,
    this.isActive = true,
  });
  /// Unique identifier for this session.
  final String sessionId;

  /// The userId this session belongs to.
  final String userId;

  /// When authentication was completed.
  final DateTime authenticatedAt;

  /// When this session will expire.
  final DateTime expiresAt;

  /// Which authentication method was used.
  final BiometricAuthMethod methodUsed;

  /// Whether this session is currently considered active.
  final bool isActive;

  /// Whether this session has expired based on the current time.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// How much time remains before this session expires.
  /// Returns [Duration.zero] if already expired.
  Duration get remainingValidity {
    final remaining = expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BiometricSession &&
          sessionId == other.sessionId &&
          userId == other.userId &&
          methodUsed == other.methodUsed;

  @override
  int get hashCode => Object.hash(sessionId, userId, methodUsed);

  @override
  String toString() =>
      'BiometricSession(id: $sessionId, user: $userId, '
      'method: $methodUsed, active: $isActive, expired: $isExpired)';
}
