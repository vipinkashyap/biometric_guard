import 'package:flutter_test/flutter_test.dart';
import 'package:biometric_shield/biometric_shield.dart';
import 'package:biometric_shield/biometric_shield_testing.dart';

void main() {
  group('BiometricResult', () {
    group('.when() exhaustive matching', () {
      test('success variant calls success handler', () {
        final result = FakeBiometricResult.success(token: 'jwt-123');

        final output = result.when(
          success: (session, token) => 'success:$token',
          fallbackSuccess: (_, __, ___) => 'fallback',
          sessionValid: (_, __) => 'sessionValid',
          tokenExpired: () => 'tokenExpired',
          cancelled: () => 'cancelled',
          lockedOut: (_) => 'lockedOut',
          unavailable: (_, __) => 'unavailable',
          invalidated: () => 'invalidated',
          reauthenticationRequired: (_) => 'reauth',
          error: (_, __) => 'error',
        );

        expect(output, 'success:jwt-123');
      });

      test('tokenExpired variant calls tokenExpired handler', () {
        final result = FakeBiometricResult.tokenExpired();

        final output = result.when(
          success: (_, __) => 'success',
          fallbackSuccess: (_, __, ___) => 'fallback',
          sessionValid: (_, __) => 'sessionValid',
          tokenExpired: () => 'tokenExpired',
          cancelled: () => 'cancelled',
          lockedOut: (_) => 'lockedOut',
          unavailable: (_, __) => 'unavailable',
          invalidated: () => 'invalidated',
          reauthenticationRequired: (_) => 'reauth',
          error: (_, __) => 'error',
        );

        expect(output, 'tokenExpired');
      });

      test('lockedOut variant provides lockedUntil DateTime', () {
        final result = FakeBiometricResult.lockedOut(
          lockoutDuration: const Duration(minutes: 10),
        );

        final output = result.when(
          success: (_, __) => null,
          fallbackSuccess: (_, __, ___) => null,
          sessionValid: (_, __) => null,
          tokenExpired: () => null,
          cancelled: () => null,
          lockedOut: (until) => until,
          unavailable: (_, __) => null,
          invalidated: () => null,
          reauthenticationRequired: (_) => null,
          error: (_, __) => null,
        );

        expect(output, isA<DateTime>());
        expect(output!.isAfter(DateTime.now()), isTrue);
      });

      test('error variant provides message and cause', () {
        const result = BiometricResult.error(
          message: 'Platform error',
          cause: 'PlatformException',
        );

        final output = result.when(
          success: (_, __) => '',
          fallbackSuccess: (_, __, ___) => '',
          sessionValid: (_, __) => '',
          tokenExpired: () => '',
          cancelled: () => '',
          lockedOut: (_) => '',
          unavailable: (_, __) => '',
          invalidated: () => '',
          reauthenticationRequired: (_) => '',
          error: (message, cause) => '$message|$cause',
        );

        expect(output, 'Platform error|PlatformException');
      });

      test('reauthenticationRequired variant provides reason', () {
        final result = FakeBiometricResult.reauthenticationRequired(
          reason: 'Refresh token revoked',
        );

        final output = result.when(
          success: (_, __) => '',
          fallbackSuccess: (_, __, ___) => '',
          sessionValid: (_, __) => '',
          tokenExpired: () => '',
          cancelled: () => '',
          lockedOut: (_) => '',
          unavailable: (_, __) => '',
          invalidated: () => '',
          reauthenticationRequired: (reason) => reason ?? 'no reason',
          error: (_, __) => '',
        );

        expect(output, 'Refresh token revoked');
      });

      test('unavailable variant provides reason enum', () {
        final result = FakeBiometricResult.unavailable(
          reason: BiometricUnavailableReason.notEnrolled,
        );

        final output = result.when(
          success: (_, __) => null,
          fallbackSuccess: (_, __, ___) => null,
          sessionValid: (_, __) => null,
          tokenExpired: () => null,
          cancelled: () => null,
          lockedOut: (_) => null,
          unavailable: (reason, _) => reason,
          invalidated: () => null,
          reauthenticationRequired: (_) => null,
          error: (_, __) => null,
        );

        expect(output, BiometricUnavailableReason.notEnrolled);
      });
    });

    group('type checks', () {
      test('success is BiometricSuccess', () {
        final result = FakeBiometricResult.success();
        expect(result, isA<BiometricSuccess>());
      });

      test('cancelled is BiometricCancelled', () {
        final result = FakeBiometricResult.cancelled();
        expect(result, isA<BiometricCancelled>());
      });

      test('fallbackSuccess is BiometricFallbackSuccess', () {
        final result = FakeBiometricResult.fallbackSuccess();
        expect(result, isA<BiometricFallbackSuccess>());
      });
    });
  });

  group('BiometricSession', () {
    test('isExpired returns false for future session', () {
      final session = FakeBiometricSession.active(
        validity: const Duration(minutes: 15),
      );
      expect(session.isExpired, isFalse);
    });

    test('isExpired returns true for past session', () {
      final session = FakeBiometricSession.expired();
      expect(session.isExpired, isTrue);
    });

    test('remainingValidity is positive for active session', () {
      final session = FakeBiometricSession.active(
        validity: const Duration(minutes: 15),
      );
      expect(session.remainingValidity.inSeconds, greaterThan(0));
    });

    test('remainingValidity is zero for expired session', () {
      final session = FakeBiometricSession.expired();
      expect(session.remainingValidity, Duration.zero);
    });

    test('aboutToExpire session has very short remaining validity', () {
      final session = FakeBiometricSession.aboutToExpire();
      expect(session.remainingValidity.inSeconds, lessThanOrEqualTo(1));
      expect(session.isExpired, isFalse);
    });

    test('equality based on sessionId, userId, methodUsed', () {
      final now = DateTime.now();
      final a = BiometricSession(
        sessionId: 'abc',
        userId: 'user1',
        authenticatedAt: now,
        expiresAt: now.add(const Duration(minutes: 15)),
        methodUsed: BiometricAuthMethod.fingerprint,
      );
      final b = BiometricSession(
        sessionId: 'abc',
        userId: 'user1',
        authenticatedAt: now.add(const Duration(seconds: 1)), // different
        expiresAt: now.add(const Duration(minutes: 30)), // different
        methodUsed: BiometricAuthMethod.fingerprint,
      );
      expect(a, equals(b));
    });

    test('inequality when sessionId differs', () {
      final now = DateTime.now();
      final a = BiometricSession(
        sessionId: 'abc',
        userId: 'user1',
        authenticatedAt: now,
        expiresAt: now.add(const Duration(minutes: 15)),
        methodUsed: BiometricAuthMethod.fingerprint,
      );
      final b = BiometricSession(
        sessionId: 'xyz',
        userId: 'user1',
        authenticatedAt: now,
        expiresAt: now.add(const Duration(minutes: 15)),
        methodUsed: BiometricAuthMethod.fingerprint,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('LockoutState', () {
    test('remainingLockout returns null when not locked', () {
      const state = LockoutState(
        isLockedOut: false,
        currentAttemptCount: 0,
        maxAttempts: 3,
      );
      expect(state.remainingLockout, isNull);
    });

    test('remainingLockout returns Duration when locked', () {
      final state = LockoutState(
        isLockedOut: true,
        lockedUntil: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        currentAttemptCount: 3,
        maxAttempts: 3,
      );
      expect(state.remainingLockout, isNotNull);
      expect(state.remainingLockout!.inSeconds, greaterThan(0));
    });

    test('remainingLockout returns zero when lockout expired', () {
      final state = LockoutState(
        isLockedOut: true,
        lockedUntil: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        currentAttemptCount: 3,
        maxAttempts: 3,
      );
      expect(state.remainingLockout, Duration.zero);
    });

    test('remainingAttempts computed correctly', () {
      const state = LockoutState(
        isLockedOut: false,
        currentAttemptCount: 1,
        maxAttempts: 3,
      );
      expect(state.remainingAttempts, 2);
    });

    test('toString provides useful output', () {
      const state = LockoutState(
        isLockedOut: true,
        currentAttemptCount: 3,
        maxAttempts: 3,
      );
      expect(state.toString(), contains('locked: true'));
      expect(state.toString(), contains('3/3'));
    });
  });
}
