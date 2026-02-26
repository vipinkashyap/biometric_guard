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
  Duration? get remainingLockout =>
      lockedUntil?.difference(DateTime.now());

  /// How many attempts remain before lockout.
  int get remainingAttempts => maxAttempts - currentAttemptCount;

  @override
  String toString() =>
      'LockoutState(locked: $isLockedOut, attempts: $currentAttemptCount/$maxAttempts)';
}
