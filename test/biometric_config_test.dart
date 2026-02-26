import 'package:flutter_test/flutter_test.dart';
import 'package:biometric_shield/biometric_shield.dart';

void main() {
  group('BiometricConfig', () {
    test('default config has sensible values', () {
      const config = BiometricConfig();
      expect(config.sessionDuration, const Duration(minutes: 15));
      expect(config.sessionResetsOnActivity, isTrue);
      expect(config.maxAttempts, 3);
      expect(config.lockoutDuration, const Duration(minutes: 5));
      expect(config.persistLockout, isTrue);
      expect(config.fallbackChain, [BiometricFallback.deviceCredential]);
      expect(config.fallbackHandler, isNull);
      expect(config.tokenStore, isNull);
      expect(config.tokenLifecycle, isNull);
      expect(config.policyProvider, isNull);
      expect(config.onEvent, isNull);
      expect(config.defaultUserId, isNull);
      expect(config.authenticationTimeout, const Duration(seconds: 60));
      expect(config.verbose, isFalse);
    });

    test('maxAttempts assert rejects zero', () {
      expect(
        () => BiometricConfig(maxAttempts: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('maxAttempts assert rejects negative', () {
      expect(
        () => BiometricConfig(maxAttempts: -1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('validate() throws when customPin without handler', () {
      const config = BiometricConfig(
        fallbackChain: [BiometricFallback.customPin],
      );
      expect(
        () => config.validate(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validate() throws when customPassword without handler', () {
      const config = BiometricConfig(
        fallbackChain: [BiometricFallback.customPassword],
      );
      expect(
        () => config.validate(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validate() passes when deviceCredential without handler', () {
      const config = BiometricConfig(
        fallbackChain: [BiometricFallback.deviceCredential],
      );
      // Should not throw
      config.validate();
    });

    test('validate() passes with empty fallback chain', () {
      const config = BiometricConfig(fallbackChain: []);
      config.validate();
    });

    test('custom session duration is preserved', () {
      const config = BiometricConfig(
        sessionDuration: Duration(minutes: 30),
      );
      expect(config.sessionDuration, const Duration(minutes: 30));
    });

    test('zero session duration means auth every time', () {
      const config = BiometricConfig(sessionDuration: Duration.zero);
      expect(config.sessionDuration, Duration.zero);
    });
  });
}
