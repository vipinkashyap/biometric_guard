import '../core/biometric_config.dart';
import '../fallback/fallback_type.dart';
import 'fake_token_store.dart';

/// A config preset that disables all persistence for testing.
///
/// Uses an in-memory [FakeTokenStore] and disables lockout persistence
/// so tests run without touching any platform storage.
class BiometricTestConfig {
  BiometricTestConfig._();

  /// Create a test-friendly config with no persistence.
  static BiometricConfig create({
    Duration sessionDuration = const Duration(minutes: 15),
    int maxAttempts = 3,
    Duration lockoutDuration = const Duration(minutes: 5),
    List<BiometricFallback> fallbackChain = const [],
  }) {
    return BiometricConfig(
      sessionDuration: sessionDuration,
      sessionResetsOnActivity: false,
      maxAttempts: maxAttempts,
      lockoutDuration: lockoutDuration,
      persistLockout: false,
      fallbackChain: fallbackChain,
      tokenStore: FakeTokenStore(),
      useCustomPromptUI: false,
    );
  }
}
