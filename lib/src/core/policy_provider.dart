/// Interface for server-driven policy enforcement.
///
/// Implement this to let a backend control biometric requirements
/// at runtime. The SDK calls [getPolicy] before each authentication
/// and merges the server policy with local configuration.
///
/// This enables scenarios like:
/// - Admin forces all users to use biometric after a breach
/// - Compliance requires re-auth every 5 minutes for certain roles
/// - Specific users are exempted from biometric (accessibility)
/// - Different security tiers for different user roles
/// - Kill-switch to disable biometric globally during maintenance
///
/// ## Usage:
///
/// ```dart
/// class AppPolicyProvider implements PolicyProvider {
///   final ApiClient api;
///   AppPolicyProvider(this.api);
///
///   BiometricPolicy? _cachedPolicy;
///   DateTime? _cachedAt;
///
///   @override
///   Future<BiometricPolicy> getPolicy({String? userId}) async {
///     // Cache policy for 5 minutes to avoid hitting the server on every auth
///     if (_cachedPolicy != null &&
///         _cachedAt != null &&
///         DateTime.now().difference(_cachedAt!) < const Duration(minutes: 5)) {
///       return _cachedPolicy!;
///     }
///
///     try {
///       final response = await api.get('/auth/biometric-policy',
///         headers: {'X-User-Id': userId ?? ''},
///       );
///       _cachedPolicy = BiometricPolicy(
///         requireBiometric: response['require_biometric'] as bool?,
///         maxSessionDuration: response['max_session_minutes'] != null
///             ? Duration(minutes: response['max_session_minutes'] as int)
///             : null,
///         maxAttempts: response['max_attempts'] as int?,
///         lockoutDuration: response['lockout_minutes'] != null
///             ? Duration(minutes: response['lockout_minutes'] as int)
///             : null,
///         forceReauthOnResume: response['force_reauth_resume'] as bool?,
///         disabled: response['biometric_disabled'] as bool?,
///         disabledReason: response['disabled_reason'] as String?,
///       );
///       _cachedAt = DateTime.now();
///       return _cachedPolicy!;
///     } catch (_) {
///       // Network failure — use default permissive policy
///       return const BiometricPolicy();
///     }
///   }
/// }
/// ```
abstract class PolicyProvider {
  /// Fetch the current biometric policy for a user.
  ///
  /// Called before each authentication attempt. Implementations should
  /// cache aggressively to avoid blocking the auth flow with network calls.
  ///
  /// If the network call fails, return [BiometricPolicy()] (all nulls)
  /// to fall back to local configuration. Never throw — the SDK will
  /// treat exceptions as "use local config".
  Future<BiometricPolicy> getPolicy({String? userId});
}

/// Server-driven policy overrides.
///
/// Every field is nullable — null means "use local configuration".
/// Non-null values override the corresponding [BiometricConfig] setting.
///
/// The SDK applies the **most restrictive** merge:
/// - For durations: uses the shorter of local vs server
/// - For attempt limits: uses the lower of local vs server
/// - For booleans: if the server says "required", it overrides local opt-out
class BiometricPolicy {
  const BiometricPolicy({
    this.requireBiometric,
    this.maxSessionDuration,
    this.maxAttempts,
    this.lockoutDuration,
    this.forceReauthOnResume,
    this.disabled,
    this.disabledReason,
  });

  /// If true, the user MUST authenticate with biometric.
  /// Overrides the user's preference to disable biometric.
  /// Useful after a security incident or for compliance.
  final bool? requireBiometric;

  /// Maximum session duration allowed by the server.
  /// If shorter than [BiometricConfig.sessionDuration], this wins.
  /// Useful for enforcing shorter sessions for high-risk roles.
  final Duration? maxSessionDuration;

  /// Server-enforced maximum failed attempts before lockout.
  /// If lower than [BiometricConfig.maxAttempts], this wins.
  final int? maxAttempts;

  /// Server-enforced lockout duration.
  /// If longer than [BiometricConfig.lockoutDuration], this wins
  /// (more restrictive = longer lockout).
  final Duration? lockoutDuration;

  /// If true, forces re-authentication on every app resume.
  /// Overrides the user's preference.
  final bool? forceReauthOnResume;

  /// If true, biometric authentication is completely disabled.
  /// The SDK will return [BiometricResult.unavailable] immediately.
  /// Useful as a kill-switch during maintenance or if a vulnerability is found.
  final bool? disabled;

  /// Human-readable reason why biometric is disabled.
  /// Shown to the user when [disabled] is true.
  final String? disabledReason;
}
