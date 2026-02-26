import 'dart:async';
import 'dart:collection';
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

  SessionManager({
    required BiometricConfig config,
    TokenStoreInterface? store,
  })  : _config = config,
        _store = store ?? config.tokenStore ?? BiometricTokenStore();
  static const _sessionKeyPrefix = 'session';
  static const _defaultUserId = '_device_default_';
  static const _maxStreamControllers = 50;

  final BiometricConfig _config;
  final TokenStoreInterface _store;

  /// In-memory cache of active sessions keyed by userId.
  final Map<String, BiometricSession> _activeSessions = {};

  /// Stream controllers for session state changes, keyed by userId.
  /// LinkedHashMap preserves insertion order for deterministic LRU eviction.
  final LinkedHashMap<String, StreamController<BiometricSession?>> _sessionStreamControllers = LinkedHashMap();

  /// Create a new session after successful authentication.
  Future<BiometricSession> createSession({
    required BiometricAuthMethod method,
    String? userId,
  }) async {
    final resolvedUserId = userId ?? _config.defaultUserId ?? _defaultUserId;
    final now = DateTime.now().toUtc();
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

    // Emit stream event
    _emitSessionStreamEvent(resolvedUserId, session);

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
  /// Also emits a stream event so listeners know the session was refreshed.
  Future<void> onActivity({String? userId}) async {
    if (!_config.sessionResetsOnActivity) return;

    final resolvedUserId = userId ?? _config.defaultUserId ?? _defaultUserId;
    final session = _activeSessions[resolvedUserId];
    if (session == null || session.isExpired) return;

    final extended = BiometricSession(
      sessionId: session.sessionId,
      userId: session.userId,
      authenticatedAt: session.authenticatedAt,
      expiresAt: DateTime.now().toUtc().add(_config.sessionDuration),
      methodUsed: session.methodUsed,
      isActive: true,
    );

    _activeSessions[resolvedUserId] = extended;
    await _store.store(
      _sessionKey(resolvedUserId),
      _encodeSession(extended),
    );

    // Notify stream listeners of the extended session
    _emitSessionStreamEvent(resolvedUserId, extended);
  }

  /// Clear the session for a user (e.g. on logout).
  Future<void> clearSession({String? userId}) async {
    final resolvedUserId = userId ?? _config.defaultUserId ?? _defaultUserId;
    _activeSessions.remove(resolvedUserId);
    await _store.delete(_sessionKey(resolvedUserId));
    _emitSessionStreamEvent(resolvedUserId, null);
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
    _emitSessionStreamEvent(resolvedUserId, null);
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

  /// Get a stream of session state changes for a user.
  ///
  /// Emits the current session (or null if none) immediately, then emits
  /// updates whenever the session changes (created, cleared, or expired).
  Stream<BiometricSession?> sessionStream({String? userId}) {
    final resolvedUserId = userId ?? _config.defaultUserId ?? _defaultUserId;

    // Create controller if it doesn't exist
    if (!_sessionStreamControllers.containsKey(resolvedUserId)) {
      // Evict oldest controllers (LRU) to prevent unbounded memory growth.
      // LinkedHashMap preserves insertion order so .keys.first is oldest.
      while (_sessionStreamControllers.length >= _maxStreamControllers) {
        final oldestKey = _sessionStreamControllers.keys.first;
        final oldController = _sessionStreamControllers.remove(oldestKey);
        if (oldController != null && !oldController.isClosed) {
          // Emit null so subscribers get a clean "session ended" event
          // before the stream closes, rather than an abrupt error.
          oldController.add(null);
          oldController.close();
        }
      }

      final controller = StreamController<BiometricSession?>.broadcast();
      _sessionStreamControllers[resolvedUserId] = controller;

      // Emit current session immediately
      final currentSession = _activeSessions[resolvedUserId];
      if (!controller.isClosed) {
        controller.add(currentSession);
      }
    }

    return _sessionStreamControllers[resolvedUserId]!.stream;
  }

  /// Clean up resources (close stream controllers).
  void dispose() {
    for (final controller in _sessionStreamControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _sessionStreamControllers.clear();
  }

  // --- Private helpers ---

  String _sessionKey(String userId) => '$_sessionKeyPrefix:$userId';

  void _emitSessionStreamEvent(String userId, BiometricSession? session) {
    final controller = _sessionStreamControllers[userId];
    if (controller != null && !controller.isClosed) {
      controller.add(session);
    }
  }

  /// Generate a unique session ID using timestamp + counter for uniqueness.
  static int _sessionCounter = 0;
  String _generateSessionId() {
    _sessionCounter++;
    final input = '${DateTime.now().toUtc().microsecondsSinceEpoch}:$_sessionCounter';
    final hash = sha256.convert(utf8.encode(input)).toString();
    return hash.substring(0, 16);
  }

  String _encodeSession(BiometricSession session) {
    return jsonEncode({
      'sessionId': session.sessionId,
      'userId': session.userId,
      'authenticatedAt': session.authenticatedAt.toIso8601String(),
      'expiresAt': session.expiresAt.toIso8601String(),
      'methodUsed': session.methodUsed.name,
      'isActive': session.isActive,
    });
  }

  Future<BiometricSession?> _loadSession(String userId) async {
    final raw = await _store.retrieve(_sessionKey(userId));
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Session data is not a JSON object');
      }
      final map = decoded;
      final sessionId = map['sessionId'];
      final sessionUserId = map['userId'];
      final authAt = map['authenticatedAt'];
      final expAt = map['expiresAt'];
      if (sessionId is! String || sessionUserId is! String ||
          authAt is! String || expAt is! String) {
        throw const FormatException('Session data has missing or invalid fields');
      }
      return BiometricSession(
        sessionId: sessionId,
        userId: sessionUserId,
        authenticatedAt: DateTime.parse(authAt),
        expiresAt: DateTime.parse(expAt),
        methodUsed: _parseAuthMethod(map['methodUsed']),
        isActive: map['isActive'] as bool? ?? true,
      );
    } on Exception catch (e) {
      // Corrupted session data — emit event with details and clear it.
      _config.onEvent?.call(BiometricEvent(
        type: BiometricEventType.sessionCleared,
        userId: userId,
        timestamp: DateTime.now().toUtc(),
        properties: {'reason': 'corrupted_data', 'error': e.toString()},
      ));
      await _store.delete(_sessionKey(userId));
      return null;
    }
  }

  /// Parse auth method from stored value.
  /// Supports both `.name` (new) and `.index` (legacy) formats.
  BiometricAuthMethod _parseAuthMethod(dynamic value) {
    if (value is String) {
      // Graceful lookup — return default on unrecognized name
      // instead of throwing ArgumentError from byName().
      for (final method in BiometricAuthMethod.values) {
        if (method.name == value) return method;
      }
      return BiometricAuthMethod.fingerprint;
    }
    if (value is int && value >= 0 && value < BiometricAuthMethod.values.length) {
      // Legacy format — index-based with bounds check.
      return BiometricAuthMethod.values[value];
    }
    return BiometricAuthMethod.fingerprint;
  }

  /// Dispose resources for a single user (clear sessions, close streams).
  void disposeUser(String userId) {
    _activeSessions.remove(userId);
    final controller = _sessionStreamControllers.remove(userId);
    if (controller != null && !controller.isClosed) {
      controller.close();
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
      timestamp: DateTime.now().toUtc(),
      method: method,
    ));
  }
}
