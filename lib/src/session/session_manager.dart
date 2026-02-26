import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/biometric_config.dart';
import '../core/biometric_session.dart';
import '../analytics/biometric_event.dart';
import '../analytics/event_type.dart';
import '../storage/token_store_interface.dart';
import '../storage/biometric_token_store.dart';

/// Manages biometric session lifecycle.
///
/// Handles session creation, validation, expiry, and activity-based
/// extension. All session data is namespace-scoped by userId.
class SessionManager {
  static const _sessionKeyPrefix = 'session';
  static const _defaultUserId = '_device_default_';

  final BiometricConfig _config;
  final TokenStoreInterface _store;

  /// In-memory cache of active sessions keyed by userId.
  final Map<String, BiometricSession> _activeSessions = {};

  SessionManager({
    required BiometricConfig config,
    TokenStoreInterface? store,
  })  : _config = config,
        _store = store ?? config.tokenStore ?? BiometricTokenStore();

  /// Create a new session after successful authentication.
  Future<BiometricSession> createSession({
    required BiometricAuthMethod method,
    String? userId,
  }) async {
    final resolvedUserId = userId ?? _config.defaultUserId ?? _defaultUserId;
    final now = DateTime.now();
    final session = BiometricSession(
      sessionId: _generateSessionId(),
      userId: resolvedUserId,
      authenticatedAt: now,
      expiresAt: now.add(_config.sessionDuration),
      methodUsed: method,
      isActive: true,
    );

    // Cache in memory
    _activeSessions[resolvedUserId] = session;

    // Persist session metadata
    await _store.store(
      _sessionKey(resolvedUserId),
      _encodeSession(session),
    );

    // Emit event
    _emitEvent(BiometricEventType.sessionStarted, resolvedUserId, method);

    return session;
  }

  /// Check if a valid (non-expired) session exists for the user.
  Future<bool> hasValidSession({String? userId}) async {
    final resolvedUserId = userId ?? _config.defaultUserId ?? _defaultUserId;

    // Check in-memory cache first
    final cached = _activeSessions[resolvedUserId];
    if (cached != null && !cached.isExpired && cached.isActive) {
      return true;
    }

    // Fall back to persisted session
    final session = await _loadSession(resolvedUserId);
    if (session != null && !session.isExpired) {
      _activeSessions[resolvedUserId] = session;
      return true;
    }

    return false;
  }

  /// Get the current active session, if any.
  Future<BiometricSession?> getActiveSession({String? userId}) async {
    final resolvedUserId = userId ?? _config.defaultUserId ?? _defaultUserId;

    // Check cache
    final cached = _activeSessions[resolvedUserId];
    if (cached != null && !cached.isExpired && cached.isActive) {
      return cached;
    }

    // Fall back to persisted
    final session = await _loadSession(resolvedUserId);
    if (session != null && !session.isExpired) {
      _activeSessions[resolvedUserId] = session;
      return session;
    }

    return null;
  }

  /// Extend the session if activity-based reset is enabled.
  Future<void> onActivity({String? userId}) async {
    if (!_config.sessionResetsOnActivity) return;

    final resolvedUserId = userId ?? _config.defaultUserId ?? _defaultUserId;
    final session = _activeSessions[resolvedUserId];
    if (session == null || session.isExpired) return;

    final extended = BiometricSession(
      sessionId: session.sessionId,
      userId: session.userId,
      authenticatedAt: session.authenticatedAt,
      expiresAt: DateTime.now().add(_config.sessionDuration),
      methodUsed: session.methodUsed,
      isActive: true,
    );

    _activeSessions[resolvedUserId] = extended;
    await _store.store(
      _sessionKey(resolvedUserId),
      _encodeSession(extended),
    );
  }

  /// Clear the session for a user (e.g. on logout).
  Future<void> clearSession({String? userId}) async {
    final resolvedUserId = userId ?? _config.defaultUserId ?? _defaultUserId;
    _activeSessions.remove(resolvedUserId);
    await _store.delete(_sessionKey(resolvedUserId));
    _emitEvent(BiometricEventType.sessionCleared, resolvedUserId, null);
  }

  /// Clear all sessions and stored data.
  Future<void> clearAll({String? userId}) async {
    final resolvedUserId = userId ?? _config.defaultUserId ?? _defaultUserId;
    _activeSessions.remove(resolvedUserId);

    // Clear session, token, and lockout data
    await _store.delete(_sessionKey(resolvedUserId));
    await _store.delete('$resolvedUserId:token');
    await _store.delete('$resolvedUserId:lockout');
  }

  // --- Token management ---

  /// Store a token namespaced to the user.
  Future<void> storeToken(String token, {String? userId}) async {
    final resolvedUserId = userId ?? _config.defaultUserId ?? _defaultUserId;
    await _store.store('$resolvedUserId:token', token);
    _emitEvent(BiometricEventType.tokenStored, resolvedUserId, null);
  }

  /// Retrieve the stored token for a user.
  Future<String?> getToken({String? userId}) async {
    final resolvedUserId = userId ?? _config.defaultUserId ?? _defaultUserId;
    final token = await _store.retrieve('$resolvedUserId:token');
    if (token != null) {
      _emitEvent(BiometricEventType.tokenRetrieved, resolvedUserId, null);
    }
    return token;
  }

  // --- Private helpers ---

  String _sessionKey(String userId) => '$_sessionKeyPrefix:$userId';

  String _generateSessionId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toString();
    final hash = sha256.convert(utf8.encode(timestamp)).toString();
    return hash.substring(0, 16);
  }

  String _encodeSession(BiometricSession session) {
    return jsonEncode({
      'sessionId': session.sessionId,
      'userId': session.userId,
      'authenticatedAt': session.authenticatedAt.toIso8601String(),
      'expiresAt': session.expiresAt.toIso8601String(),
      'methodUsed': session.methodUsed.index,
      'isActive': session.isActive,
    });
  }

  Future<BiometricSession?> _loadSession(String userId) async {
    final raw = await _store.retrieve(_sessionKey(userId));
    if (raw == null) return null;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return BiometricSession(
        sessionId: map['sessionId'] as String,
        userId: map['userId'] as String,
        authenticatedAt: DateTime.parse(map['authenticatedAt'] as String),
        expiresAt: DateTime.parse(map['expiresAt'] as String),
        methodUsed: BiometricAuthMethod.values[map['methodUsed'] as int],
        isActive: map['isActive'] as bool? ?? true,
      );
    } catch (_) {
      // Corrupted session data — clear it
      await _store.delete(_sessionKey(userId));
      return null;
    }
  }

  void _emitEvent(
    BiometricEventType type,
    String userId,
    BiometricAuthMethod? method,
  ) {
    _config.onEvent?.call(BiometricEvent(
      type: type,
      userId: userId,
      timestamp: DateTime.now(),
      method: method,
    ));
  }
}
