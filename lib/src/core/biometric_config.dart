import '../analytics/biometric_event.dart';
import '../fallback/fallback_type.dart';
import '../fallback/fallback_handler.dart';
import '../storage/token_store_interface.dart';
import 'token_lifecycle.dart';
import 'policy_provider.dart';

/// Configuration object for the BiometricShield SDK.
///
/// Pure Dart configuration without Flutter or UI dependencies.
/// Pass this to [BiometricShield()] constructor. Every field is optional —
/// the SDK works with zero configuration using sensible defaults.
///
/// ## Integration points:
///
/// - [tokenLifecycle] — Backend-agnostic token refresh (Firebase, REST, Supabase, etc.)
/// - [policyProvider] — Server-driven policy enforcement (admin overrides, compliance)
/// - [fallbackHandler] — Custom fallback UI (PIN, password, custom flows)
/// - [tokenStore] — Custom secure storage backend
/// - [onEvent] — Analytics/audit event stream
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
    this.tokenLifecycle,
    this.policyProvider,
    this.onEvent,
    this.defaultUserId,
    this.authenticationTimeout = const Duration(seconds: 60),
    this.verbose = false,
  }) : assert(maxAttempts > 0, 'maxAttempts must be > 0'),
       assert(
         fallbackHandler != null ||
             !fallbackChain.any((f) =>
                 f == BiometricFallback.customPin ||
                 f == BiometricFallback.customPassword),
         'fallbackHandler must be provided when fallbackChain '
         'contains customPin or customPassword',
       );

  /// Validate this config at runtime. Call this from BiometricShield
  /// constructor to catch misconfiguration even in release builds.
  void validate() {
    if (maxAttempts <= 0) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be > 0');
    }
    if (fallbackHandler == null &&
        fallbackChain.any((f) =>
            f == BiometricFallback.customPin ||
            f == BiometricFallback.customPassword)) {
      throw ArgumentError(
        'fallbackHandler must be provided when fallbackChain '
        'contains customPin or customPassword',
      );
    }
  }

  // --- Session ---

  /// How long a successful auth remains valid before re-auth is required.
  /// Default: 15 minutes. Set to [Duration.zero] to require auth every time.
  /// May be overridden by [PolicyProvider.getPolicy] at runtime.
  final Duration sessionDuration;

  /// If true, session timer resets on any app interaction.
  /// If false, session expires based on wall clock from last auth.
  /// Default: true
  final bool sessionResetsOnActivity;

  // --- Lockout ---

  /// Max failed biometric attempts before lockout triggers.
  /// Default: 3. May be tightened by server policy.
  final int maxAttempts;

  /// How long the lockout lasts after [maxAttempts] is exceeded.
  /// Default: 5 minutes. May be extended by server policy.
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

  // --- Token Lifecycle (Backend Integration) ---

  /// Backend-agnostic token lifecycle handler.
  ///
  /// When configured, the SDK will:
  /// 1. Validate stored tokens after biometric auth succeeds
  /// 2. Auto-refresh expired tokens using [TokenLifecycle.refresh]
  /// 3. Emit [BiometricResult.reauthenticationRequired] if refresh fails
  ///
  /// Without this, the SDK simply returns whatever is in storage,
  /// and the caller handles expiry themselves.
  ///
  /// See [TokenLifecycle] for Firebase, REST API, and Supabase examples.
  final TokenLifecycle? tokenLifecycle;

  // --- Server Policy ---

  /// Server-driven policy enforcement.
  ///
  /// When configured, the SDK calls [PolicyProvider.getPolicy] before each
  /// authentication and merges the server policy with local config.
  /// Server policy can enforce stricter session durations, lockout rules,
  /// or disable biometric entirely.
  ///
  /// See [PolicyProvider] for implementation examples.
  final PolicyProvider? policyProvider;

  // --- Analytics ---

  /// Receives all audit events emitted by the SDK.
  /// Plug directly into your existing analytics or logging service.
  final void Function(BiometricEvent event)? onEvent;

  // --- Multi-user ---

  /// Default userId for storage namespacing.
  /// Can be overridden per-call on [BiometricShield.authenticate].
  /// If null, uses a device-scoped default (single user scenario).
  final String? defaultUserId;

  // --- Timeout ---

  /// Maximum time to wait for the entire authentication flow to complete.
  /// Includes platform prompt, fallback chain, and token lifecycle.
  /// Default: 60 seconds. If exceeded, returns [BiometricResult.error].
  final Duration authenticationTimeout;

  // --- Debug ---

  /// If true, the SDK prints debug information to the console.
  /// Useful for integrators debugging authentication flows.
  /// Default: false. Never enable in production.
  final bool verbose;
}
