import 'package:flutter_test/flutter_test.dart';
import 'package:biometric_shield/biometric_shield.dart';
import 'package:biometric_shield/biometric_shield_testing.dart';

void main() {
  group('BiometricShieldMock', () {
    test('returns configured authenticate result', () async {
      final mock = BiometricShieldMock(
        authenticateResult: FakeBiometricResult.success(token: 'test-jwt'),
      );

      final result = await mock.authenticate(reason: 'Test');
      expect(result, isA<BiometricSuccess>());

      final success = result as BiometricSuccess;
      expect(success.token, 'test-jwt');
    });

    test('tracks authenticate calls', () async {
      final mock = BiometricShieldMock();

      await mock.authenticate(reason: 'First call', userId: 'user-1');
      await mock.authenticate(
        reason: 'Second call',
        userId: 'user-2',
        requireFresh: true,
      );

      expect(mock.authenticateCalls, hasLength(2));
      expect(mock.authenticateCalls[0].reason, 'First call');
      expect(mock.authenticateCalls[0].userId, 'user-1');
      expect(mock.authenticateCalls[0].requireFresh, isFalse);
      expect(mock.authenticateCalls[1].reason, 'Second call');
      expect(mock.authenticateCalls[1].userId, 'user-2');
      expect(mock.authenticateCalls[1].requireFresh, isTrue);
    });

    test('tracks stored tokens', () async {
      final mock = BiometricShieldMock();

      await mock.storeToken('token-1');
      await mock.storeToken('token-2');

      expect(mock.storedTokens, ['token-1', 'token-2']);
    });

    test('returns configured token', () async {
      final mock = BiometricShieldMock(tokenResult: 'stored-jwt');

      final token = await mock.getToken();
      expect(token, 'stored-jwt');
    });

    test('returns configured session validity', () async {
      final mock = BiometricShieldMock(hasValidSessionResult: true);

      final isValid = await mock.hasValidSession();
      expect(isValid, isTrue);
    });

    test('returns configured capability', () async {
      final mock = BiometricShieldMock(
        capabilityResult: const BiometricCapability(
          isEnrolled: false,
          hasStrongBiometric: false,
          biometricLabel: 'None',
        ),
      );

      final capability = await mock.getCapability();
      expect(capability.isEnrolled, isFalse);
      expect(capability.biometricLabel, 'None');
    });

    test('returns configured lockout state', () async {
      final mock = BiometricShieldMock(
        lockoutStateResult: const LockoutState(
          isLockedOut: true,
          currentAttemptCount: 3,
          maxAttempts: 3,
        ),
      );

      final lockout = await mock.getLockoutState();
      expect(lockout.isLockedOut, isTrue);
      expect(lockout.remainingAttempts, 0);
    });

    test('sessionStream emits configured session', () async {
      final session = FakeBiometricSession.active();
      final mock = BiometricShieldMock(sessionStreamResult: session);

      final emissions = await mock.sessionStream().take(1).toList();
      expect(emissions, hasLength(1));
      expect(emissions.first, session);
    });

    test('tracks onActivity calls', () {
      final mock = BiometricShieldMock();

      mock.onActivity(userId: 'user-1');
      mock.onActivity();
      mock.onActivity(userId: 'user-2');

      expect(mock.onActivityCalls, ['user-1', null, 'user-2']);
    });

    test('tracks disposeUser calls', () async {
      final mock = BiometricShieldMock();

      await mock.disposeUser(userId: 'user-1');
      await mock.disposeUser(userId: 'user-2');

      expect(mock.disposedUsers, ['user-1', 'user-2']);
    });

    test('resetCalls clears all tracking', () async {
      final mock = BiometricShieldMock();

      await mock.authenticate(reason: 'test');
      await mock.storeToken('token');
      mock.onActivity(userId: 'user');
      await mock.disposeUser(userId: 'user');

      expect(mock.authenticateCalls, isNotEmpty);
      expect(mock.storedTokens, isNotEmpty);
      expect(mock.onActivityCalls, isNotEmpty);
      expect(mock.disposedUsers, isNotEmpty);

      mock.resetCalls();

      expect(mock.authenticateCalls, isEmpty);
      expect(mock.storedTokens, isEmpty);
      expect(mock.onActivityCalls, isEmpty);
      expect(mock.disposedUsers, isEmpty);
    });

    test('implements BiometricShieldInterface', () {
      final mock = BiometricShieldMock();
      expect(mock, isA<BiometricShieldInterface>());
    });

    test('validateOrAuthenticate delegates to authenticate', () async {
      final mock = BiometricShieldMock(
        authenticateResult: FakeBiometricResult.sessionValid(),
      );

      final result = await mock.validateOrAuthenticate(
        reason: 'Verify',
        userId: 'user-1',
      );

      expect(result, isA<BiometricSessionValid>());
      expect(mock.authenticateCalls, hasLength(1));
      expect(mock.authenticateCalls.first.reason, 'Verify');
    });
  });

  group('FakeBiometricResult', () {
    test('success creates BiometricSuccess with defaults', () {
      final result = FakeBiometricResult.success();
      expect(result, isA<BiometricSuccess>());
      final success = result as BiometricSuccess;
      expect(success.token, 'fake-token');
      expect(success.session.isExpired, isFalse);
    });

    test('lockedOut creates future lockout', () {
      final result = FakeBiometricResult.lockedOut();
      expect(result, isA<BiometricLockedOut>());
      final locked = result as BiometricLockedOut;
      expect(locked.lockedUntil.isAfter(DateTime.now()), isTrue);
    });

    test('error creates BiometricError', () {
      final result = FakeBiometricResult.error(message: 'oops');
      expect(result, isA<BiometricError>());
      final error = result as BiometricError;
      expect(error.message, 'oops');
    });
  });

  group('FakeTokenStore', () {
    late FakeTokenStore store;

    setUp(() {
      store = FakeTokenStore();
    });

    test('store and retrieve', () async {
      await store.store('key1', 'value1');
      final value = await store.retrieve('key1');
      expect(value, 'value1');
    });

    test('retrieve returns null for missing key', () async {
      final value = await store.retrieve('nonexistent');
      expect(value, isNull);
    });

    test('delete removes key', () async {
      await store.store('key1', 'value1');
      await store.delete('key1');
      final value = await store.retrieve('key1');
      expect(value, isNull);
    });

    test('deleteAll clears everything', () async {
      await store.store('key1', 'value1');
      await store.store('key2', 'value2');
      await store.deleteAll();
      expect(await store.retrieve('key1'), isNull);
      expect(await store.retrieve('key2'), isNull);
    });

    test('containsKey works', () async {
      await store.store('key1', 'value1');
      expect(await store.containsKey('key1'), isTrue);
      expect(await store.containsKey('key2'), isFalse);
    });

    test('data getter returns unmodifiable copy', () async {
      await store.store('key1', 'value1');
      final data = store.data;
      expect(data['key1'], 'value1');
      expect(() => data['key2'] = 'value2', throwsUnsupportedError);
    });

    test('reset clears all data', () async {
      await store.store('key1', 'value1');
      store.reset();
      expect(await store.retrieve('key1'), isNull);
    });
  });

  group('BiometricTestConfig', () {
    test('creates config with no persistence', () {
      final config = BiometricTestConfig.create();
      expect(config.persistLockout, isFalse);
      expect(config.sessionResetsOnActivity, isFalse);
      expect(config.tokenStore, isA<FakeTokenStore>());
    });

    test('allows custom session duration', () {
      final config = BiometricTestConfig.create(
        sessionDuration: const Duration(minutes: 1),
      );
      expect(config.sessionDuration, const Duration(minutes: 1));
    });

    test('allows custom max attempts', () {
      final config = BiometricTestConfig.create(maxAttempts: 5);
      expect(config.maxAttempts, 5);
    });
  });
}
