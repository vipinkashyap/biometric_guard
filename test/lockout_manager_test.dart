import 'package:flutter_test/flutter_test.dart';
import 'package:biometric_shield/biometric_shield.dart';
import 'package:biometric_shield/biometric_shield_testing.dart';
import 'package:biometric_shield/src/session/lockout_manager.dart';

void main() {
  late FakeTokenStore store;
  late LockoutManager lockoutManager;

  setUp(() {
    store = FakeTokenStore();
    lockoutManager = LockoutManager(
      config: BiometricTestConfig.create(maxAttempts: 3),
      store: store,
    );
  });

  tearDown(() {
    lockoutManager.dispose();
  });

  group('LockoutManager', () {
    group('recordFailure', () {
      test('increments attempt count', () async {
        final state = await lockoutManager.recordFailure(userId: 'user-1');
        expect(state.currentAttemptCount, 1);
        expect(state.isLockedOut, isFalse);
      });

      test('locks out after max attempts', () async {
        await lockoutManager.recordFailure(userId: 'user-1');
        await lockoutManager.recordFailure(userId: 'user-1');
        final state = await lockoutManager.recordFailure(userId: 'user-1');

        expect(state.currentAttemptCount, 3);
        expect(state.isLockedOut, isTrue);
        expect(state.lockedUntil, isNotNull);
      });

      test('lockout state includes correct maxAttempts', () async {
        final state = await lockoutManager.recordFailure(userId: 'user-1');
        expect(state.maxAttempts, 3);
        expect(state.remainingAttempts, 2);
      });

      test('stays locked when already locked out', () async {
        await lockoutManager.recordFailure(userId: 'user-1');
        await lockoutManager.recordFailure(userId: 'user-1');
        await lockoutManager.recordFailure(userId: 'user-1');

        // Additional failure while locked
        final state = await lockoutManager.recordFailure(userId: 'user-1');
        expect(state.isLockedOut, isTrue);
        expect(state.currentAttemptCount, 3);
      });

      test('failures are isolated by userId', () async {
        await lockoutManager.recordFailure(userId: 'user-1');
        await lockoutManager.recordFailure(userId: 'user-1');

        final state1 =
            await lockoutManager.getLockoutState(userId: 'user-1');
        final state2 =
            await lockoutManager.getLockoutState(userId: 'user-2');

        expect(state1.currentAttemptCount, 2);
        expect(state2.currentAttemptCount, 0);
      });
    });

    group('getLockoutState', () {
      test('returns clean state initially', () async {
        final state = await lockoutManager.getLockoutState(userId: 'user-1');
        expect(state.isLockedOut, isFalse);
        expect(state.currentAttemptCount, 0);
        expect(state.maxAttempts, 3);
      });

      test('reflects recorded failures', () async {
        await lockoutManager.recordFailure(userId: 'user-1');
        await lockoutManager.recordFailure(userId: 'user-1');

        final state = await lockoutManager.getLockoutState(userId: 'user-1');
        expect(state.currentAttemptCount, 2);
        expect(state.isLockedOut, isFalse);
      });
    });

    group('resetLockout', () {
      test('clears lockout state', () async {
        await lockoutManager.recordFailure(userId: 'user-1');
        await lockoutManager.recordFailure(userId: 'user-1');
        await lockoutManager.recordFailure(userId: 'user-1');

        await lockoutManager.resetLockout(userId: 'user-1');

        final state = await lockoutManager.getLockoutState(userId: 'user-1');
        expect(state.isLockedOut, isFalse);
        expect(state.currentAttemptCount, 0);
      });

      test('reset one user does not affect another', () async {
        await lockoutManager.recordFailure(userId: 'user-1');
        await lockoutManager.recordFailure(userId: 'user-1');
        await lockoutManager.recordFailure(userId: 'user-2');

        await lockoutManager.resetLockout(userId: 'user-1');

        final state1 =
            await lockoutManager.getLockoutState(userId: 'user-1');
        final state2 =
            await lockoutManager.getLockoutState(userId: 'user-2');

        expect(state1.currentAttemptCount, 0);
        expect(state2.currentAttemptCount, 1);
      });
    });

    group('onSuccess', () {
      test('resets attempt counter', () async {
        await lockoutManager.recordFailure(userId: 'user-1');
        await lockoutManager.recordFailure(userId: 'user-1');

        await lockoutManager.onSuccess(userId: 'user-1');

        final state = await lockoutManager.getLockoutState(userId: 'user-1');
        expect(state.currentAttemptCount, 0);
        expect(state.isLockedOut, isFalse);
      });
    });

    group('custom maxAttempts', () {
      test('locks out at custom threshold', () async {
        final customManager = LockoutManager(
          config: BiometricTestConfig.create(maxAttempts: 1),
          store: store,
        );

        final state = await customManager.recordFailure(userId: 'user-1');
        expect(state.isLockedOut, isTrue);
        customManager.dispose();
      });

      test('5 attempts before lockout', () async {
        final customManager = LockoutManager(
          config: BiometricTestConfig.create(maxAttempts: 5),
          store: store,
        );

        for (var i = 0; i < 4; i++) {
          final state = await customManager.recordFailure(userId: 'user-1');
          expect(state.isLockedOut, isFalse);
        }

        final state = await customManager.recordFailure(userId: 'user-1');
        expect(state.isLockedOut, isTrue);
        expect(state.currentAttemptCount, 5);
        customManager.dispose();
      });
    });

    group('event emission', () {
      test('emits lockoutStarted when locked', () async {
        final events = <BiometricEvent>[];
        final config = BiometricConfig(
          maxAttempts: 2,
          tokenStore: store,
          persistLockout: false,
          onEvent: events.add,
        );
        final mgr = LockoutManager(config: config, store: store);

        await mgr.recordFailure(userId: 'user-1');
        await mgr.recordFailure(userId: 'user-1');

        expect(
          events.any((e) => e.type == BiometricEventType.lockoutStarted),
          isTrue,
        );
        mgr.dispose();
      });

      test('emits lockoutReset on manual reset', () async {
        final events = <BiometricEvent>[];
        final config = BiometricConfig(
          tokenStore: store,
          persistLockout: false,
          onEvent: events.add,
        );
        final mgr = LockoutManager(config: config, store: store);

        await mgr.resetLockout(userId: 'user-1');

        expect(
          events.any((e) => e.type == BiometricEventType.lockoutReset),
          isTrue,
        );
        mgr.dispose();
      });
    });
  });
}
