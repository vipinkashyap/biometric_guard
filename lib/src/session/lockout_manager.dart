import 'dart:convert';

import '../core/biometric_config.dart';
import '../analytics/biometric_event.dart';
import '../analytics/event_type.dart';
import '../storage/token_store_interface.dart';
import '../storage/biometric_token_store.dart';
import 'lockout_state.dart';

/// Tracks failed authentication attempts and manages lockout state.
///
/// Lockout data is optionally persisted across app restarts
/// (controlled by [BiometricConfig.persistLockout]).
class LockoutManager {

  LockoutManager({
    required BiometricConfig config,
    TokenStoreInterface? store,
  })  : _config = config,
        _store = store ?? config.tokenStore ?? BiometricTokenStore();
  static const _lockoutKeyPrefix = 'lockout';
  static const _defaultUserId = '_device_default_';

  final BiometricConfig _config;
  final TokenStoreInterface _store;

  /// In-memory lockout state keyed by userId.
  final Map<String, _LockoutData> _lockoutData = {};

  /// Record a failed authentication attempt.
  ///
  /// Returns the updated [LockoutState]. If [maxAttempts] is exceeded,
  /// lockout begins and the [onLockoutStart] callback is invoked.
  Future<LockoutState> recordFailure({String? userId}) async {
    final resolvedUserId = userId ?? _config.defaultUserId ?? _defaultUserId;
    final data = await _getOrLoadData(resolvedUserId);

    // If currently locked out and lockout has expired, reset first
    if (data.isLockedOut && data.lockedUntil != null) {
      if (DateTime.now().isAfter(data.lockedUntil!)) {
        await _resetData(resolvedUserId);
        return _recordNewFailure(resolvedUserId);
      }
    }

    // If already locked out and lockout hasn't expired
    if (data.isLockedOut) {
      return _toState(data);
    }

    return _recordNewFailure(resolvedUserId);
  }

  /// Get the current lockout state for a user.
  Future<LockoutState> getLockoutState({String? userId}) async {
    final resolvedUserId = userId ?? _config.defaultUserId ?? _defaultUserId;
    final data = await _getOrLoadData(resolvedUserId);

    // Check if lockout has expired
    if (data.isLockedOut && data.lockedUntil != null) {
      if (DateTime.now().isAfter(data.lockedUntil!)) {
        await _resetData(resolvedUserId);
        _emitEvent(BiometricEventType.lockoutEnded, resolvedUserId);
        return LockoutState(
          isLockedOut: false,
          currentAttemptCount: 0,
          maxAttempts: _config.maxAttempts,
        );
      }
    }

    return _toState(data);
  }

  /// Manually reset the lockout (e.g. after admin override).
  Future<void> resetLockout({String? userId}) async {
    final resolvedUserId = userId ?? _config.defaultUserId ?? _defaultUserId;
    await _resetData(resolvedUserId);
    _emitEvent(BiometricEventType.lockoutReset, resolvedUserId);
  }

  /// Reset attempt counter on successful authentication.
  Future<void> onSuccess({String? userId}) async {
    final resolvedUserId = userId ?? _config.defaultUserId ?? _defaultUserId;
    await _resetData(resolvedUserId);
  }

  /// Clean up resources. Currently a no-op but available for future use.
  void dispose() {
    // No resources to clean up currently, but keeping for API consistency
  }

  // --- Private helpers ---

  Future<LockoutState> _recordNewFailure(String resolvedUserId) async {
    var data = await _getOrLoadData(resolvedUserId);
    final newCount = data.attemptCount + 1;

    if (newCount >= _config.maxAttempts) {
      // Trigger lockout
      final lockedUntil = DateTime.now().add(_config.lockoutDuration);
      data = _LockoutData(
        attemptCount: newCount,
        isLockedOut: true,
        lockedUntil: lockedUntil,
      );

      _emitEvent(BiometricEventType.lockoutStarted, resolvedUserId);
    } else {
      data = _LockoutData(
        attemptCount: newCount,
        isLockedOut: false,
      );
    }

    _lockoutData[resolvedUserId] = data;
    if (_config.persistLockout) {
      await _persistData(resolvedUserId, data);
    }

    return _toState(data);
  }

  Future<_LockoutData> _getOrLoadData(String userId) async {
    final cached = _lockoutData[userId];
    if (cached != null) return cached;

    if (_config.persistLockout) {
      final loaded = await _loadData(userId);
      if (loaded != null) {
        _lockoutData[userId] = loaded;
        return loaded;
      }
    }

    final empty = _LockoutData(attemptCount: 0, isLockedOut: false);
    _lockoutData[userId] = empty;
    return empty;
  }

  Future<void> _resetData(String userId) async {
    _lockoutData[userId] =
        _LockoutData(attemptCount: 0, isLockedOut: false);
    if (_config.persistLockout) {
      await _store.delete('$_lockoutKeyPrefix:$userId');
    }
  }

  Future<void> _persistData(String userId, _LockoutData data) async {
    await _store.store(
      '$_lockoutKeyPrefix:$userId',
      jsonEncode({
        'attemptCount': data.attemptCount,
        'isLockedOut': data.isLockedOut,
        'lockedUntil': data.lockedUntil?.toIso8601String(),
      }),
    );
  }

  Future<_LockoutData?> _loadData(String userId) async {
    final raw = await _store.retrieve('$_lockoutKeyPrefix:$userId');
    if (raw == null) return null;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return _LockoutData(
        attemptCount: map['attemptCount'] as int,
        isLockedOut: map['isLockedOut'] as bool,
        lockedUntil: map['lockedUntil'] != null
            ? DateTime.parse(map['lockedUntil'] as String)
            : null,
      );
    } catch (_) {
      await _store.delete('$_lockoutKeyPrefix:$userId');
      return null;
    }
  }

  LockoutState _toState(_LockoutData data) => LockoutState(
        isLockedOut: data.isLockedOut,
        lockedUntil: data.lockedUntil,
        currentAttemptCount: data.attemptCount,
        maxAttempts: _config.maxAttempts,
      );

  void _emitEvent(BiometricEventType type, String userId) {
    _config.onEvent?.call(BiometricEvent(
      type: type,
      userId: userId,
      timestamp: DateTime.now(),
    ));
  }
}

/// Internal lockout data representation.
class _LockoutData {

  _LockoutData({
    required this.attemptCount,
    required this.isLockedOut,
    this.lockedUntil,
  });
  final int attemptCount;
  final bool isLockedOut;
  final DateTime? lockedUntil;
}
