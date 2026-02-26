/// Represents the current lockout state for a user.
///
/// Query this via [BiometricShield.getLockoutState] to check
/// if the user is currently locked out and when lockout will end.
class LockoutState {

  const LockoutState({
    required this.isLockedOut,
    this.lockedUntil,
    required this.currentAttemptCount,
    required this.maxAttempts,
  });
  /// Whether the user is currently locked out.
  final bool isLockedOut;

  /// When the lockout will end, if currently locked out.
  final DateTime? lockedUntil;

  /// How many failed attempts have been recorded in the current window.
  final int currentAttemptCount;

  /// Maximum allowed attempts before lockout triggers.
  final int maxAttempts;

  /// How much time remains in the lockout period, or null if not locked out.
  /// Returns [Duration.zero] if lockout has expired.
  Duration? get remainingLockout {
    if (lockedUntil == null) return null;
    final remaining = lockedUntil!.difference(DateTime.now().toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// How many attempts remain before lockout.
  int get remainingAttempts => maxAttempts - currentAttemptCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LockoutState &&
          isLockedOut == other.isLockedOut &&
          currentAttemptCount == other.currentAttemptCount &&
          maxAttempts == other.maxAttempts;

  @override
  int get hashCode => Object.hash(isLockedOut, currentAttemptCount, maxAttempts);

  @override
  String toString() =>
      'LockoutState(locked: $isLockedOut, attempts: $currentAttemptCount/$maxAttempts)';
}
