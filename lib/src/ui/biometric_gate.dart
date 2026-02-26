import 'package:flutter/material.dart';
import '../core/biometric_shield.dart';
import '../core/biometric_result.dart';
import 'biometric_builder.dart';

/// A convenience widget that gates access to its child behind biometric auth.
///
/// Wraps [BiometricBuilder] to provide a simpler API for the common pattern
/// of "show loading -> show child after auth -> show fallback if auth fails".
///
/// For more control over auth states, use [BiometricBuilder] directly.
///
/// Example:
/// ```dart
/// BiometricGate(
///   shield: shield,
///   reason: 'Confirm to view health records',
///   userId: currentUser.id,
///   child: HealthRecordsScreen(),
///   fallbackWidget: (result) => AccessDeniedScreen(result: result),
/// )
/// ```
class BiometricGate extends StatelessWidget {
  const BiometricGate({
    super.key,
    required this.shield,
    required this.child,
    required this.reason,
    this.loadingWidget,
    this.fallbackWidget,
    this.onAuthenticated,
    this.reauthOnResume = false,
    this.userId,
  });

  /// The BiometricShield instance to use.
  final BiometricShield shield;

  /// The content to show after successful authentication.
  final Widget child;

  /// Reason shown in the biometric prompt.
  final String reason;

  /// Widget to show while authentication is in progress.
  /// Default: centered [CircularProgressIndicator]
  final Widget? loadingWidget;

  /// Widget to show if auth fails.
  /// Receives the final [BiometricResult] for context.
  final Widget Function(BiometricResult result)? fallbackWidget;

  /// Called when auth succeeds. Use for side effects (analytics, etc).
  final void Function(BiometricResult result)? onAuthenticated;

  /// If true, re-authenticates when app resumes from background
  /// and the session has expired.
  final bool reauthOnResume;

  /// Override userId for this gate instance.
  final String? userId;

  @override
  Widget build(BuildContext context) {
    return BiometricBuilder(
      shield: shield,
      reason: reason,
      userId: userId,
      reauthOnResume: reauthOnResume,
      autoAuthenticate: true,
      builder: (context, state) {
        return switch (state) {
          AuthIdle() || AuthAuthenticating() =>
            loadingWidget ?? const Center(child: CircularProgressIndicator()),
          AuthAuthenticated(:final session, :final token) => () {
            _invokeCallback(
              BiometricResult.success(session: session, token: token),
            );
            return child;
          }(),
          AuthFailed(:final result) =>
            fallbackWidget?.call(result) ??
                const Center(child: Text('Authentication required')),
        };
      },
    );
  }

  /// Helper to invoke the onAuthenticated callback and return a dummy bool.
  bool _invokeCallback(BiometricResult result) {
    onAuthenticated?.call(result);
    return true;
  }
}
