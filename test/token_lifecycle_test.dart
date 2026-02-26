import 'package:flutter_test/flutter_test.dart';
import 'package:biometric_shield/biometric_shield.dart';

/// A test implementation of TokenLifecycle that returns configurable results.
class TestTokenLifecycle implements TokenLifecycle {

  TestTokenLifecycle({
    this.validateResult = TokenStatus.valid,
    this.refreshResult = const TokenRefreshResult.success(newToken: 'new-token'),
  });
  TokenStatus validateResult;
  TokenRefreshResult refreshResult;
  int validateCallCount = 0;
  int refreshCallCount = 0;

  @override
  Future<TokenStatus> validate(String token) async {
    validateCallCount++;
    return validateResult;
  }

  @override
  Future<TokenRefreshResult> refresh(String expiredToken) async {
    refreshCallCount++;
    return refreshResult;
  }
}

void main() {
  group('TokenLifecycle interface', () {
    test('validate returns configured status', () async {
      final lifecycle = TestTokenLifecycle(
        validateResult: TokenStatus.expired,
      );

      final status = await lifecycle.validate('test-token');
      expect(status, TokenStatus.expired);
      expect(lifecycle.validateCallCount, 1);
    });

    test('refresh returns success with new token', () async {
      final lifecycle = TestTokenLifecycle(
        refreshResult: const TokenRefreshResult.success(
          newToken: 'refreshed-jwt',
          metadata: {'refresh_token': 'new-refresh'},
        ),
      );

      final result = await lifecycle.refresh('old-token');
      expect(result, isA<TokenRefreshSuccess>());

      final success = result as TokenRefreshSuccess;
      expect(success.newToken, 'refreshed-jwt');
      expect(success.metadata['refresh_token'], 'new-refresh');
    });

    test('refresh returns reauthRequired', () async {
      final lifecycle = TestTokenLifecycle(
        refreshResult: const TokenRefreshResult.reauthRequired(),
      );

      final result = await lifecycle.refresh('old-token');
      expect(result, isA<TokenRefreshReauthRequired>());
    });

    test('refresh returns failed with reason', () async {
      final lifecycle = TestTokenLifecycle(
        refreshResult: const TokenRefreshResult.failed(reason: 'Network error'),
      );

      final result = await lifecycle.refresh('old-token');
      expect(result, isA<TokenRefreshFailed>());

      final failed = result as TokenRefreshFailed;
      expect(failed.reason, 'Network error');
    });
  });

  group('TokenStatus', () {
    test('has all expected values', () {
      expect(TokenStatus.values, hasLength(4));
      expect(TokenStatus.values, contains(TokenStatus.valid));
      expect(TokenStatus.values, contains(TokenStatus.expired));
      expect(TokenStatus.values, contains(TokenStatus.invalid));
      expect(TokenStatus.values, contains(TokenStatus.missing));
    });
  });

  group('TokenRefreshResult', () {
    test('success holds newToken and metadata', () {
      const result = TokenRefreshResult.success(
        newToken: 'jwt',
        metadata: {'key': 'val'},
      );
      expect(result, isA<TokenRefreshSuccess>());
      const success = result as TokenRefreshSuccess;
      expect(success.newToken, 'jwt');
      expect(success.metadata, {'key': 'val'});
    });

    test('success defaults to empty metadata', () {
      const result = TokenRefreshResult.success(newToken: 'jwt');
      const success = result as TokenRefreshSuccess;
      expect(success.metadata, isEmpty);
    });

    test('failed holds optional reason', () {
      const result = TokenRefreshResult.failed(reason: 'timeout');
      const failed = result as TokenRefreshFailed;
      expect(failed.reason, 'timeout');
    });

    test('failed reason defaults to null', () {
      const result = TokenRefreshResult.failed();
      const failed = result as TokenRefreshFailed;
      expect(failed.reason, isNull);
    });
  });

  group('PolicyProvider / BiometricPolicy', () {
    test('default policy has all nulls', () {
      const policy = BiometricPolicy();
      expect(policy.requireBiometric, isNull);
      expect(policy.maxSessionDuration, isNull);
      expect(policy.maxAttempts, isNull);
      expect(policy.lockoutDuration, isNull);
      expect(policy.forceReauthOnResume, isNull);
      expect(policy.disabled, isNull);
      expect(policy.disabledReason, isNull);
    });

    test('policy fields are set correctly', () {
      const policy = BiometricPolicy(
        requireBiometric: true,
        maxSessionDuration: Duration(minutes: 5),
        maxAttempts: 1,
        lockoutDuration: Duration(minutes: 30),
        forceReauthOnResume: true,
        disabled: false,
        disabledReason: 'Active',
      );

      expect(policy.requireBiometric, isTrue);
      expect(policy.maxSessionDuration, const Duration(minutes: 5));
      expect(policy.maxAttempts, 1);
      expect(policy.lockoutDuration, const Duration(minutes: 30));
      expect(policy.forceReauthOnResume, isTrue);
      expect(policy.disabled, isFalse);
      expect(policy.disabledReason, 'Active');
    });
  });

  group('BiometricEvent', () {
    test('properties are immutable', () {
      final event = BiometricEvent(
        type: BiometricEventType.authSucceeded,
        userId: 'user-1',
        timestamp: DateTime.now().toUtc(),
        properties: {'key': 'value'},
      );

      expect(
        () => event.properties['new_key'] = 'new_value',
        throwsUnsupportedError,
      );
    });

    test('stores all fields', () {
      final now = DateTime.now().toUtc();
      final event = BiometricEvent(
        type: BiometricEventType.authSucceeded,
        userId: 'user-1',
        timestamp: now,
        method: BiometricAuthMethod.faceID,
        properties: {'source': 'test'},
      );

      expect(event.type, BiometricEventType.authSucceeded);
      expect(event.userId, 'user-1');
      expect(event.timestamp, now);
      expect(event.method, BiometricAuthMethod.faceID);
      expect(event.properties['source'], 'test');
    });
  });
}
