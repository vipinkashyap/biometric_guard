import 'dart:async';

import 'package:local_auth/local_auth.dart';

import '../core/biometric_config.dart';
import '../core/biometric_session.dart';
import '../analytics/biometric_event.dart';
import '../analytics/event_type.dart';
import 'fallback_type.dart';
import 'fallback_handler.dart';

/// Orchestrates the fallback chain when biometric auth fails or is unavailable.
///
/// Pure Dart orchestrator (no Flutter imports). Walks through
/// [BiometricConfig.fallbackChain] in order, attempting each fallback
/// until one succeeds, all fail, or the user cancels.
class FallbackChainExecutor {

  FallbackChainExecutor({
    required BiometricConfig config,
    LocalAuthentication? localAuth,
  })  : _config = config,
        _localAuth = localAuth ?? LocalAuthentication();

  final BiometricConfig _config;
  final LocalAuthentication _localAuth;

  /// Execute the fallback chain.
  ///
  /// Returns a [FallbackOutcome] indicating which fallback succeeded,
  /// or that all fallbacks were exhausted / user cancelled.
  ///
  /// Note: No BuildContext parameter — custom fallbacks are handled
  /// by the configured [FallbackHandler] in the UI layer.
  Future<FallbackOutcome> execute({
    required String reason,
    String? userId,
  }) async {
    for (final fallback in _config.fallbackChain) {
      _emitEvent(BiometricEventType.fallbackTriggered, userId, fallback);

      switch (fallback) {
        case BiometricFallback.deviceCredential:
          final result = await _tryDeviceCredential(reason);
          if (result == _FallbackResult.success) {
            _emitEvent(
                BiometricEventType.fallbackSucceeded, userId, fallback);
            return FallbackSuccessOutcome(
              method: BiometricFallback.deviceCredential,
              authMethod: BiometricAuthMethod.deviceCredential,
            );
          }
          if (result == _FallbackResult.cancelled) {
            return const FallbackCancelledOutcome();
          }
          _emitEvent(BiometricEventType.fallbackFailed, userId, fallback);
          continue;

        case BiometricFallback.customPin:
        case BiometricFallback.customPassword:
          if (_config.fallbackHandler == null) {
            _emitEvent(BiometricEventType.fallbackFailed, userId, fallback);
            continue;
          }
          final result = await _tryCustomFallback(
            fallback,
            reason,
          );
          if (result == _FallbackResult.success) {
            _emitEvent(
                BiometricEventType.fallbackSucceeded, userId, fallback);
            return FallbackSuccessOutcome(
              method: fallback,
              authMethod: fallback == BiometricFallback.customPin
                  ? BiometricAuthMethod.customPin
                  : BiometricAuthMethod.customPassword,
            );
          }
          if (result == _FallbackResult.cancelled) {
            return const FallbackCancelledOutcome();
          }
          _emitEvent(BiometricEventType.fallbackFailed, userId, fallback);
          continue;

        case BiometricFallback.none:
          return const FallbackExhaustedOutcome();
      }
    }

    return const FallbackExhaustedOutcome();
  }

  Future<_FallbackResult> _tryDeviceCredential(String reason) async {
    try {
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      return didAuthenticate
          ? _FallbackResult.success
          : _FallbackResult.failed;
    } catch (_) {
      return _FallbackResult.failed;
    }
  }

  Future<_FallbackResult> _tryCustomFallback(
    BiometricFallback fallback,
    String reason,
  ) async {
    try {
      final result = await _config.fallbackHandler!.handleFallback(
        type: fallback,
        reason: reason,
      );
      return switch (result) {
        FallbackResult.success => _FallbackResult.success,
        FallbackResult.cancelled => _FallbackResult.cancelled,
        FallbackResult.failed => _FallbackResult.failed,
      };
    } catch (_) {
      return _FallbackResult.failed;
    }
  }

  void _emitEvent(
    BiometricEventType type,
    String? userId,
    BiometricFallback fallback,
  ) {
    _config.onEvent?.call(BiometricEvent(
      type: type,
      userId: userId ?? _config.defaultUserId ?? '_device_default_',
      timestamp: DateTime.now(),
      properties: {'fallbackMethod': fallback.name},
    ));
  }
}

/// Outcome of the fallback chain execution.
sealed class FallbackOutcome {
  const FallbackOutcome();

  /// A fallback succeeded.
  const factory FallbackOutcome.success({
    required BiometricFallback method,
    required BiometricAuthMethod authMethod,
  }) = FallbackSuccessOutcome;

  /// User cancelled during fallback.
  const factory FallbackOutcome.cancelled() = FallbackCancelledOutcome;

  /// All fallbacks were exhausted without success.
  const factory FallbackOutcome.exhausted() = FallbackExhaustedOutcome;
}

/// A fallback succeeded.
class FallbackSuccessOutcome extends FallbackOutcome {
  const FallbackSuccessOutcome({required this.method, required this.authMethod});
  final BiometricFallback method;
  final BiometricAuthMethod authMethod;
}

/// User cancelled during fallback.
class FallbackCancelledOutcome extends FallbackOutcome {
  const FallbackCancelledOutcome();
}

/// All fallbacks were exhausted without success.
class FallbackExhaustedOutcome extends FallbackOutcome {
  const FallbackExhaustedOutcome();
}

enum _FallbackResult { success, failed, cancelled }
