import '../analytics/biometric_event.dart';
import '../fallback/fallback_type.dart';
import '../fallback/fallback_handler.dart';
import '../storage/token_store_interface.dart';

/// Configuration object for the BiometricShield SDK.
///
/// Pure Dart configuration without Flutter or UI dependencies.
/// Pass this to [BiometricShield()] constructor. Every field is optional —
/// the SDK works with zero configuration using sensible defaults.
class BiometricConfig {
  const BiometricConfig({
    this.sessionDuration = const Duration(minutes: 15),
    this.sessionResetsOnActivity = true,
    this.maxAttempts = 3,
    this.lockoutDuration = const Duration(minutes: 5),
    this.persistLockout = true,
    this.fallbackChain = const [BiometricFallback.deviceCredential],
    this.fallbackHandler,
    this.tokenStore,
    this.onEvent,
    this.defaultUserId,
  });

  // --- Session ---

  /// How long a successful auth remains valid before re-auth is required.
  /// Default: 15 minutes. Set to [Duration.zero] to require auth every time.
  final Duration sessionDuration;

  /// If true, session timer resets on any app interaction.
  /// If false, session expires based on wall clock from last auth.
  /// Default: true
  final bool sessionResetsOnActivity;

  // --- Lockout ---

  /// Max failed biometric attempts before lockout triggers.
  /// Default: 3
  final int maxAttempts;

  /// How long the lockout lasts after [maxAttempts] is exceeded.
  /// Default: 5 minutes
  final Duration lockoutDuration;

  /// If true, lockout state persists across app restarts.
  /// Default: true
  final bool persistLockout;

  // --- Fallback Chain ---

  /// Ordered list of fallbacks to attempt if biometric fails or is unavailable.
  /// Evaluated in order. Default: [BiometricFallback.deviceCredential]
  final List<BiometricFallback> fallbackChain;

  /// Handler for custom fallback UI (PIN/password).
  /// If [fallbackChain] includes [BiometricFallback.customPin] or
  /// [BiometricFallback.customPassword], this handler must be provided.
  /// Typically implemented by the UI layer (e.g., MaterialFallbackHandler).
  final FallbackHandler? fallbackHandler;

  // --- Storage ---

  /// Custom token store implementation.
  /// If null, uses the default [BiometricTokenStore] implementation.
  final TokenStoreInterface? tokenStore;

  // --- Analytics ---

  /// Receives all audit events emitted by the SDK.
  /// Plug directly into your existing analytics or logging service.
  final void Function(BiometricEvent event)? onEvent;

  // --- Multi-user ---

  /// Default userId for storage namespacing.
  /// Can be overridden per-call on [BiometricShield.authenticate].
  /// If null, uses a device-scoped default (single user scenario).
  final String? defaultUserId;
}
