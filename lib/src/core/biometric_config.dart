import '../analytics/biometric_event.dart';
import '../fallback/fallback_type.dart';
import '../fallback/custom_fallback.dart';
import '../storage/token_store_interface.dart';
import '../ui/biometric_theme.dart';
import '../ui/biometric_strings.dart';

/// Configuration object for the BiometricShield SDK.
///
/// Pass this to [BiometricShield.configure] at app startup. Every field
/// is optional — the SDK works with zero configuration using sensible defaults.
class BiometricConfig {
  const BiometricConfig({
    this.sessionDuration = const Duration(minutes: 15),
    this.sessionResetsOnActivity = true,
    this.maxAttempts = 3,
    this.lockoutDuration = const Duration(minutes: 5),
    this.persistLockout = true,
    this.fallbackChain = const [BiometricFallback.deviceCredential],
    this.customPinBuilder,
    this.tokenStore,
    this.theme,
    this.strings,
    this.useCustomPromptUI = true,
    this.onTokenExpired,
    this.onLockoutStart,
    this.onLockoutEnd,
    this.onUserCancelled,
    this.onBiometricInvalidated,
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

  /// If [fallbackChain] includes [BiometricFallback.customPin] or
  /// [BiometricFallback.customPassword], this widget builder is called
  /// to show the custom authentication UI.
  /// Receives [CustomFallbackCallbacks] with onSuccess, onCancel, onFailure.
  final CustomFallbackBuilder? customPinBuilder;

  // --- Storage ---

  /// Custom token store implementation.
  /// If null, uses the default [flutter_secure_storage] implementation.
  final TokenStoreInterface? tokenStore;

  // --- UI ---

  /// Visual theme for all SDK-owned UI surfaces.
  final BiometricTheme? theme;

  /// Custom string overrides for all user-facing text.
  final BiometricStrings? strings;

  /// If true, SDK shows its own prompt UI (bottom sheet / overlay).
  /// If false, relies entirely on platform biometric UI.
  /// Default: true for fallback flows, false for biometric itself
  final bool useCustomPromptUI;

  // --- Lifecycle Callbacks ---

  /// Called when biometric succeeds but the stored token has expired.
  /// Use this to redirect to full login or trigger a token refresh.
  /// If null, SDK surfaces a [BiometricResult.tokenExpired] to the caller.
  final Future<void> Function()? onTokenExpired;

  /// Called when the user exceeds [maxAttempts] and lockout begins.
  /// Receives the [DateTime] when lockout will end.
  final void Function(DateTime lockedUntil)? onLockoutStart;

  /// Called when lockout period ends and auth is available again.
  final void Function()? onLockoutEnd;

  /// Called when the user explicitly cancels authentication.
  final void Function()? onUserCancelled;

  /// Called when biometric keys are invalidated (e.g. new fingerprint
  /// added on Android). Use this to prompt user to re-enroll biometric.
  final void Function()? onBiometricInvalidated;

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
