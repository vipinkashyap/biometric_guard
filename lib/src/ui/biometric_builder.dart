import 'dart:async';
import 'package:flutter/material.dart';
import '../core/biometric_shield.dart';
import '../core/biometric_result.dart';
import '../core/biometric_session.dart';

/// Auth state sealed class for BiometricBuilder.
///
/// Represents all possible authentication states that can be passed
/// to the builder function.
sealed class AuthState {
  const AuthState();

  /// Idle state — no authentication in progress.
  const factory AuthState.idle() = AuthIdle;

  /// Authentication is currently in progress.
  const factory AuthState.authenticating() = AuthAuthenticating;

  /// Authentication succeeded and session is active.
  const factory AuthState.authenticated({
    required BiometricSession session,
    required String? token,
  }) = AuthAuthenticated;

  /// Authentication failed.
  const factory AuthState.failed({required BiometricResult result}) = AuthFailed;
}

/// Idle state — no authentication in progress.
class AuthIdle extends AuthState {
  const AuthIdle();
}

/// Authentication is currently in progress.
class AuthAuthenticating extends AuthState {
  const AuthAuthenticating();
}

/// Authentication succeeded and session is active.
class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({
    required this.session,
    required this.token,
  });

  final BiometricSession session;
  final String? token;
}

/// Authentication failed.
class AuthFailed extends AuthState {
  const AuthFailed({required this.result});

  final BiometricResult result;
}

/// Reactive widget that rebuilds when biometric auth state changes.
///
/// Like FutureBuilder but for biometric authentication. Handles lifecycle
/// events (app resume), session stream subscription, and state management.
///
/// Example:
/// ```dart
/// BiometricBuilder(
///   shield: shield,
///   reason: 'Confirm to view health records',
///   userId: user.id,
///   reauthOnResume: true,
///   builder: (context, state) => switch (state) {
///     AuthIdle() => MyIdleScreen(),
///     AuthAuthenticating() => MyLoadingScreen(),
///     AuthAuthenticated(:final session, :final token) => HealthRecordsScreen(),
///     AuthFailed(:final result) => MyErrorScreen(result: result),
///   },
/// )
/// ```
class BiometricBuilder extends StatefulWidget {
  const BiometricBuilder({
    super.key,
    required this.shield,
    required this.reason,
    this.userId,
    this.reauthOnResume = false,
    this.autoAuthenticate = true,
    required this.builder,
  });

  /// The BiometricShield instance to use for authentication.
  /// Accepts the interface for DI/testing.
  final BiometricShieldInterface shield;

  /// Reason shown in the biometric prompt.
  final String reason;

  /// Override userId for this builder instance.
  /// Defaults to [BiometricConfig.defaultUserId].
  final String? userId;

  /// If true, re-triggers authentication when app resumes from background
  /// and the session has expired.
  final bool reauthOnResume;

  /// If true, automatically triggers authentication on widget mount.
  /// If false, waits for the caller to explicitly trigger auth via
  /// [_BiometricBuilderState.authenticate].
  final bool autoAuthenticate;

  /// Builder function that receives the current auth state.
  ///
  /// Called whenever the auth state changes. The caller controls all UI.
  final Widget Function(BuildContext context, AuthState state) builder;

  @override
  State<BiometricBuilder> createState() => _BiometricBuilderState();
}

class _BiometricBuilderState extends State<BiometricBuilder>
    with WidgetsBindingObserver {
  late AuthState _authState;
  late StreamSubscription<BiometricSession?> _sessionSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authState = const AuthIdle();

    // Subscribe to session stream to react to session changes.
    _sessionSubscription =
        widget.shield.sessionStream(userId: widget.userId).listen((session) async {
      if (!mounted) return;

      if (session != null && !session.isExpired) {
        // Session is active — fetch token and switch to authenticated state.
        if (_authState is! AuthAuthenticated) {
          final token = await widget.shield.getToken(userId: widget.userId);
          if (!mounted) return;
          setState(() {
            _authState = AuthAuthenticated(session: session, token: token);
          });
        }
      } else {
        // Session expired or cleared — reset to idle.
        if (_authState is AuthAuthenticated) {
          setState(() => _authState = const AuthIdle());
        }
      }
    });

    // Trigger auto-authentication if configured.
    if (widget.autoAuthenticate) {
      _triggerAuthentication();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionSubscription.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.reauthOnResume) {
      // Check if session has expired and re-auth if needed.
      _validateOrReauth();
    }
  }

  /// Trigger authentication programmatically.
  ///
  /// Can be called by parent widgets via [ScaffoldState.of] or similar.
  Future<void> _triggerAuthentication() async {
    if (!mounted) return;

    setState(() => _authState = const AuthAuthenticating());

    final result = await widget.shield.authenticate(
      reason: widget.reason,
      userId: widget.userId,
    );

    if (!mounted) return;

    result.when(
      success: (session, token) {
        setState(() => _authState = AuthAuthenticated(session: session, token: token));
      },
      fallbackSuccess: (_, session, token) {
        setState(() => _authState = AuthAuthenticated(session: session, token: token));
      },
      sessionValid: (session, token) {
        setState(() => _authState = AuthAuthenticated(session: session, token: token));
      },
      tokenExpired: () {
        setState(() => _authState = AuthFailed(result: result));
      },
      cancelled: () {
        setState(() => _authState = AuthFailed(result: result));
      },
      lockedOut: (_) {
        setState(() => _authState = AuthFailed(result: result));
      },
      unavailable: (_, _) {
        setState(() => _authState = AuthFailed(result: result));
      },
      invalidated: () {
        setState(() => _authState = AuthFailed(result: result));
      },
      reauthenticationRequired: (_) {
        setState(() => _authState = AuthFailed(result: result));
      },
      error: (_, _) {
        setState(() => _authState = AuthFailed(result: result));
      },
    );
  }

  /// Validate existing session; re-authenticate if expired.
  Future<void> _validateOrReauth() async {
    if (!mounted) return;

    final result = await widget.shield.validateOrAuthenticate(
      reason: widget.reason,
      userId: widget.userId,
    );

    if (!mounted) return;

    result.when(
      success: (session, token) {
        setState(() => _authState = AuthAuthenticated(session: session, token: token));
      },
      fallbackSuccess: (_, session, token) {
        setState(() => _authState = AuthAuthenticated(session: session, token: token));
      },
      sessionValid: (session, token) {
        // Keep the current state; session is still valid.
      },
      tokenExpired: () {
        setState(() => _authState = AuthFailed(result: result));
      },
      cancelled: () {
        setState(() => _authState = AuthFailed(result: result));
      },
      lockedOut: (_) {
        setState(() => _authState = AuthFailed(result: result));
      },
      unavailable: (_, _) {
        setState(() => _authState = AuthFailed(result: result));
      },
      invalidated: () {
        setState(() => _authState = AuthFailed(result: result));
      },
      reauthenticationRequired: (_) {
        setState(() => _authState = AuthFailed(result: result));
      },
      error: (_, _) {
        setState(() => _authState = AuthFailed(result: result));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _authState);
  }
}
