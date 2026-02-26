import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';

import '../core/biometric_config.dart';
import '../core/biometric_session.dart';
import '../analytics/biometric_event.dart';
import '../analytics/event_type.dart';
import 'fallback_type.dart';
import 'custom_fallback.dart';

/// Orchestrates the fallback chain when biometric auth fails
/// or is unavailable.
///
/// Walks through [BiometricConfig.fallbackChain] in order, attempting
/// each fallback until one succeeds, all fail, or the user cancels.
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
  Future<FallbackOutcome> execute({
    required String reason,
    BuildContext? context,
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
            return const FallbackOutcome.success(
              method: BiometricFallback.deviceCredential,
              authMethod: BiometricAuthMethod.deviceCredential,
            );
          }
          if (result == _FallbackResult.cancelled) {
            return const FallbackOutcome.cancelled();
          }
          _emitEvent(BiometricEventType.fallbackFailed, userId, fallback);
          continue;

        case BiometricFallback.customPin:
        case BiometricFallback.customPassword:
          if (_config.customPinBuilder == null || context == null) {
            _emitEvent(BiometricEventType.fallbackFailed, userId, fallback);
            continue;
          }
          final result =
              await _tryCustomFallback(context, _config.customPinBuilder!);
          if (result == _FallbackResult.success) {
            _emitEvent(
                BiometricEventType.fallbackSucceeded, userId, fallback);
            return FallbackOutcome.success(
              method: fallback,
              authMethod: fallback == BiometricFallback.customPin
                  ? BiometricAuthMethod.customPin
                  : BiometricAuthMethod.customPassword,
            );
          }
          if (result == _FallbackResult.cancelled) {
            return const FallbackOutcome.cancelled();
          }
          _emitEvent(BiometricEventType.fallbackFailed, userId, fallback);
          continue;

        case BiometricFallback.none:
          return const FallbackOutcome.exhausted();
      }
    }

    return const FallbackOutcome.exhausted();
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
    BuildContext context,
    CustomFallbackBuilder builder,
  ) async {
    final completer = Completer<_FallbackResult>();

    final callbacks = CustomFallbackCallbacks(
      onSuccess: () {
        if (!completer.isCompleted) completer.complete(_FallbackResult.success);
      },
      onCancel: () {
        if (!completer.isCompleted) {
          completer.complete(_FallbackResult.cancelled);
        }
      },
      onFailure: () {
        if (!completer.isCompleted) completer.complete(_FallbackResult.failed);
      },
    );

    // Show the custom fallback widget as an overlay
    final overlay = OverlayEntry(
      builder: (_) => builder(context, callbacks),
    );

    Overlay.of(context).insert(overlay);

    try {
      final result = await completer.future;
      overlay.remove();
      return result;
    } catch (_) {
      overlay.remove();
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

class FallbackSuccessOutcome extends FallbackOutcome {
  const FallbackSuccessOutcome({required this.method, required this.authMethod});
  final BiometricFallback method;
  final BiometricAuthMethod authMethod;
}

class FallbackCancelledOutcome extends FallbackOutcome {
  const FallbackCancelledOutcome();
}

class FallbackExhaustedOutcome extends FallbackOutcome {
  const FallbackExhaustedOutcome();
}

enum _FallbackResult { success, failed, cancelled }
