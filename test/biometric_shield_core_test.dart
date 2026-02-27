import 'package:biometric_shield/biometric_shield.dart';
import 'package:biometric_shield/biometric_shield_testing.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingFallbackHandler implements FallbackHandler {
  _CountingFallbackHandler();
  int calls = 0;

  @override
  Future<FallbackResult> handleFallback({
    required BiometricFallback type,
    required String reason,
  }) async {
    calls++;
    return FallbackResult.success;
  }
}

class _MutablePolicyProvider implements PolicyProvider {
  _MutablePolicyProvider(this.currentPolicy);

  BiometricPolicy currentPolicy;

  @override
  Future<BiometricPolicy> getPolicy({String? userId}) async => currentPolicy;
}

class _DelayedPolicyProvider implements PolicyProvider {
  _DelayedPolicyProvider(this.delay);

  final Duration delay;

  @override
  Future<BiometricPolicy> getPolicy({String? userId}) async {
    await Future<void>.delayed(delay);
    return const BiometricPolicy();
  }
}

void main() {
  group('BiometricShield core behavior', () {
    late FakeTokenStore store;
    late _CountingFallbackHandler fallbackHandler;
    late BiometricShield shield;

    setUp(() {
      store = FakeTokenStore();
      fallbackHandler = _CountingFallbackHandler();
      shield = BiometricShield(
        config: BiometricConfig(
          tokenStore: store,
          fallbackChain: const [BiometricFallback.customPin],
          fallbackHandler: fallbackHandler,
          persistLockout: true,
        ),
      );
    });

    test('clearSession deletes token when rememberMe is disabled', () async {
      await shield.storeToken('jwt-abc');
      await shield.preferences.setRememberMe(false);

      await shield.clearSession();

      expect(await shield.getToken(), isNull);
      expect(await store.containsKey('_device_default_:token'), isFalse);
    });

    test('treats empty token as tokenExpired on valid session', () async {
      await shield.storeToken('jwt-valid');
      final authResult = await shield.authenticate(reason: 'Unlock');
      expect(authResult, isA<BiometricSuccess>());

      await shield.storeToken('');

      final result = await shield.validateOrAuthenticate(reason: 'Check token');
      expect(result, isA<BiometricTokenExpired>());
    });

    test('policy maxSessionDuration triggers re-authentication', () async {
      final policyProvider = _MutablePolicyProvider(const BiometricPolicy());
      final policyShield = BiometricShield(
        config: BiometricConfig(
          tokenStore: store,
          fallbackChain: const [BiometricFallback.customPin],
          fallbackHandler: fallbackHandler,
          policyProvider: policyProvider,
        ),
      );

      await policyShield.storeToken('jwt-initial');
      final first = await policyShield.authenticate(reason: 'Initial auth');
      expect(first, isA<BiometricSuccess>());
      expect(fallbackHandler.calls, 1);

      policyProvider.currentPolicy = const BiometricPolicy(
        maxSessionDuration: Duration.zero,
      );

      await policyShield.storeToken('jwt-refreshed');
      final second = await policyShield.validateOrAuthenticate(
        reason: 'Revalidate',
      );
      expect(second, isA<BiometricSuccess>());
      expect(fallbackHandler.calls, 2);
    });

    test('timeout returns quickly when policy fetch hangs', () async {
      final timeoutShield = BiometricShield(
        config: BiometricConfig(
          tokenStore: store,
          fallbackChain: const [BiometricFallback.none],
          authenticationTimeout: const Duration(milliseconds: 20),
          policyProvider: _DelayedPolicyProvider(
            const Duration(milliseconds: 200),
          ),
        ),
      );

      final watch = Stopwatch()..start();
      final result = await timeoutShield.authenticate(reason: 'Timeout test');
      watch.stop();

      expect(result, isA<BiometricError>());
      final error = result as BiometricError;
      expect(error.message, 'Authentication timed out');
      expect(watch.elapsedMilliseconds, lessThan(150));
    });
  });
}
