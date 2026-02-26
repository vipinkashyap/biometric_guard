import 'dart:async';

import 'package:flutter/material.dart';

import '../core/biometric_result.dart';

/// A widget wrapper that requires biometric authentication before
/// showing its child content.
///
/// Drop this around any widget or route to gate access behind
/// biometric auth.
///
/// ```dart
/// BiometricGate(
///   reason: 'Confirm to view health records',
///   userId: currentUser.id,
///   child: HealthRecordsScreen(),
///   fallbackWidget: (result) => AccessDeniedScreen(result: result),
/// )
/// ```
class BiometricGate extends StatefulWidget {

  const BiometricGate({
    super.key,
    required this.child,
    required this.reason,
    this.loadingWidget,
    this.fallbackWidget,
    this.onAuthenticated,
    this.onAuthFailed,
    this.reauthOnResume,
    this.userId,
  });
  /// The content to show after successful authentication.
  final Widget child;

  /// Reason shown in the biometric prompt.
  final String reason;

  /// Widget to show while authentication is in progress.
  /// Default: centered [CircularProgressIndicator]
  final Widget? loadingWidget;

  /// Widget to show if auth fails permanently (all fallbacks exhausted).
  /// Receives the final [BiometricResult] for context.
  final Widget Function(BiometricResult result)? fallbackWidget;

  /// Called when auth succeeds. Use for side effects (analytics etc).
  final void Function(BiometricResult result)? onAuthenticated;

  /// Called when auth fails. Return true to retry, false to show fallbackWidget.
  final Future<bool> Function(BiometricResult result)? onAuthFailed;

  /// If true, re-authenticates when app resumes from background.
  /// Default: uses config.sessionDuration to decide
  final bool? reauthOnResume;

  /// Override userId for this gate instance.
  final String? userId;

  @override
  State<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<BiometricGate>
    with WidgetsBindingObserver {
  _GateStatus _status = _GateStatus.loading;
  BiometricResult? _lastResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authenticate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (widget.reauthOnResume ?? false)) {
      _authenticate();
    }
  }

  Future<void> _authenticate() async {
    if (!mounted) return;
    setState(() => _status = _GateStatus.loading);

    try {
      // Import dynamically to avoid circular dependency
      // The actual authentication is delegated to BiometricShield
      final result = await _performAuth();

      if (!mounted) return;

      result.when(
        success: (_, __) => _onSuccess(result),
        fallbackSuccess: (_, __, ___) => _onSuccess(result),
        sessionValid: (_, __) => _onSuccess(result),
        tokenExpired: () => unawaited(_onFailure(result)),
        cancelled: () => unawaited(_onFailure(result)),
        lockedOut: (_) => unawaited(_onFailure(result)),
        unavailable: (_) => unawaited(_onFailure(result)),
        invalidated: () => unawaited(_onFailure(result)),
        error: (_, __) => unawaited(_onFailure(result)),
      );
    } catch (e) {
      if (mounted) {
        unawaited(_onFailure(BiometricResult.error(
          message: 'Authentication error: $e',
          cause: e,
        )));
      }
    }
  }

  void _onSuccess(BiometricResult result) {
    setState(() {
      _status = _GateStatus.authenticated;
      _lastResult = result;
    });
    widget.onAuthenticated?.call(result);
  }

  Future<void> _onFailure(BiometricResult result) async {
    _lastResult = result;

    if (widget.onAuthFailed != null) {
      final shouldRetry = await widget.onAuthFailed!(result);
      if (shouldRetry && mounted) {
        _authenticate();
        return;
      }
    }

    if (mounted) {
      setState(() => _status = _GateStatus.failed);
    }
  }

  /// Performs authentication via the BiometricShield singleton.
  ///
  /// This uses a late import pattern to avoid circular dependencies.
  /// The BiometricShield class must be configured before using BiometricGate.
  Future<BiometricResult> _performAuth() async {
    // We use a dynamic import here to break the circular dependency
    // between BiometricGate and BiometricShield.
    // In the actual implementation, this calls BiometricShield.authenticate()
    // or BiometricShield.validateOrAuthenticate().
    //
    // For now, the gate delegates to a static callback that BiometricShield
    // sets up during configure().
    if (_authenticateCallback == null) {
      return const BiometricResult.error(
        message: 'BiometricShield not configured. '
            'Call BiometricShield.configure() before using BiometricGate.',
        cause: null,
      );
    }
    return _authenticateCallback!(
      reason: widget.reason,
      userId: widget.userId,
      context: context,
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (_status) {
      _GateStatus.loading => widget.loadingWidget ??
          const Center(child: CircularProgressIndicator()),
      _GateStatus.authenticated => widget.child,
      _GateStatus.failed => widget.fallbackWidget?.call(_lastResult!) ??
          const Center(
            child: Text('Authentication required'),
          ),
    };
  }
}

enum _GateStatus { loading, authenticated, failed }

/// Static callback set by BiometricShield.configure() to enable
/// BiometricGate to trigger authentication without a circular import.
typedef GateAuthenticateCallback = Future<BiometricResult> Function({
  required String reason,
  String? userId,
  BuildContext? context,
});

GateAuthenticateCallback? _authenticateCallback;

/// Called by BiometricShield.configure() to wire up the gate.
/// @internal
void setGateAuthenticateCallback(GateAuthenticateCallback callback) {
  _authenticateCallback = callback;
}
