import '../storage/token_store_interface.dart';
import '../storage/biometric_token_store.dart';

/// User-facing biometric preferences that can be changed at runtime.
///
/// Separates *user preferences* (can change from settings screen) from
/// *SDK configuration* (set once at construction). This enables:
///
/// - "Remember Me" checkbox on login screen
/// - Settings screen toggle to enable/disable biometric
/// - In-app session timeout slider
/// - Per-user opt-in/opt-out of biometric authentication
///
/// Preferences are persisted to secure storage and survive app restarts.
/// They are namespaced by userId for multi-user support.
///
/// ## Usage:
///
/// ```dart
/// // Login screen — "Remember Me" checkbox
/// final prefs = shield.preferences;
/// await prefs.setRememberMe(true, userId: 'user-123');
///
/// // Settings screen — toggle biometric on/off
/// await prefs.setBiometricEnabled(false, userId: 'user-123');
///
/// // Check before showing biometric prompt
/// if (await prefs.isBiometricEnabled(userId: 'user-123')) {
///   final result = await shield.authenticate(reason: '...');
/// }
/// ```
class BiometricPreferences {
  BiometricPreferences({
    TokenStoreInterface? store,
    String? defaultUserId,
  })  : _store = store ?? BiometricTokenStore(),
        _defaultUserId = defaultUserId;

  static const _keyPrefix = 'prefs';
  static const _defaultUser = '_device_default_';

  final TokenStoreInterface _store;
  final String? _defaultUserId;

  // ──────────────────────────────────────────────────────────
  // Biometric Enabled (master switch)
  // ──────────────────────────────────────────────────────────

  /// Whether biometric authentication is enabled for this user.
  ///
  /// When false, [BiometricShield.authenticate] will skip biometric
  /// and go straight to fallback chain. Default: true.
  Future<bool> isBiometricEnabled({String? userId}) async {
    final raw = await _store.retrieve(_key('biometric_enabled', userId));
    return raw != 'false'; // default true
  }

  /// Enable or disable biometric authentication.
  ///
  /// Use from a settings screen toggle. When disabled, the SDK
  /// still functions but skips the biometric prompt, going straight
  /// to fallbacks.
  Future<void> setBiometricEnabled(bool enabled, {String? userId}) async {
    await _store.store(_key('biometric_enabled', userId), enabled.toString());
  }

  // ──────────────────────────────────────────────────────────
  // Remember Me (session persistence)
  // ──────────────────────────────────────────────────────────

  /// Whether "Remember Me" is enabled for this user.
  ///
  /// When true:
  /// - Session and token are persisted to secure storage
  /// - Next app launch uses biometric to unlock stored session
  /// - User stays "logged in" across app restarts
  ///
  /// When false:
  /// - Session lives in memory only
  /// - Token is NOT persisted to secure storage
  /// - Next app launch requires full re-authentication
  /// - Equivalent to "session cookie" behavior
  ///
  /// Default: true
  Future<bool> isRememberMeEnabled({String? userId}) async {
    final raw = await _store.retrieve(_key('remember_me', userId));
    return raw != 'false'; // default true
  }

  /// Set the "Remember Me" preference.
  ///
  /// Typically bound to a checkbox on the login screen.
  /// Changing this at runtime affects the *next* authentication —
  /// it does not retroactively clear an existing persisted session.
  Future<void> setRememberMe(bool enabled, {String? userId}) async {
    await _store.store(_key('remember_me', userId), enabled.toString());
  }

  // ──────────────────────────────────────────────────────────
  // Custom Session Duration Override
  // ──────────────────────────────────────────────────────────

  /// Get the user's custom session duration override, if any.
  ///
  /// Returns null if the user hasn't set a custom duration,
  /// in which case [BiometricConfig.sessionDuration] is used.
  Future<Duration?> getSessionDurationOverride({String? userId}) async {
    final raw = await _store.retrieve(_key('session_duration', userId));
    if (raw == null) return null;
    final seconds = int.tryParse(raw);
    if (seconds == null) return null;
    return Duration(seconds: seconds);
  }

  /// Set a custom session duration override from a settings screen.
  ///
  /// Pass null to reset to the SDK default ([BiometricConfig.sessionDuration]).
  Future<void> setSessionDurationOverride(
    Duration? duration, {
    String? userId,
  }) async {
    if (duration == null) {
      await _store.delete(_key('session_duration', userId));
    } else {
      await _store.store(
        _key('session_duration', userId),
        duration.inSeconds.toString(),
      );
    }
  }

  // ──────────────────────────────────────────────────────────
  // Reauth on Resume
  // ──────────────────────────────────────────────────────────

  /// Whether to require re-authentication when the app resumes
  /// from background, even if the session hasn't expired.
  ///
  /// Useful for high-security scenarios (banking apps).
  /// Default: false (uses session expiry instead).
  Future<bool> isReauthOnResumeEnabled({String? userId}) async {
    final raw = await _store.retrieve(_key('reauth_on_resume', userId));
    return raw == 'true'; // default false
  }

  /// Set whether to require re-auth on resume.
  Future<void> setReauthOnResume(bool enabled, {String? userId}) async {
    await _store.store(_key('reauth_on_resume', userId), enabled.toString());
  }

  // ──────────────────────────────────────────────────────────
  // Clear all preferences
  // ──────────────────────────────────────────────────────────

  /// Clear all stored preferences for a user.
  ///
  /// Call this on account deletion or full logout.
  Future<void> clearAll({String? userId}) async {
    final keys = [
      'biometric_enabled',
      'remember_me',
      'session_duration',
      'reauth_on_resume',
    ];
    for (final key in keys) {
      await _store.delete(_key(key, userId));
    }
  }

  // ──────────────────────────────────────────────────────────
  // Private
  // ──────────────────────────────────────────────────────────

  String _key(String field, String? userId) {
    final resolvedUser = userId ?? _defaultUserId ?? _defaultUser;
    return '$_keyPrefix:$resolvedUser:$field';
  }
}
