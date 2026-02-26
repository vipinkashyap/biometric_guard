import 'package:flutter/material.dart';
import 'package:biometric_shield/biometric_shield.dart';
import 'package:biometric_shield/biometric_shield_ui.dart';
import '../main.dart';

/// Demonstrates BiometricBuilder — the reactive widget pattern.
///
/// Unlike [BiometricGate] (which hides/shows a child), BiometricBuilder
/// gives you full control over every auth state. You decide what to render
/// for idle, authenticating, authenticated, and failed states.
///
/// Use BiometricBuilder when you need:
/// - Custom loading animations
/// - Inline auth status (not a full-screen gate)
/// - Different layouts per auth state
/// - Access to the session/token in your UI
class BiometricBuilderScreen extends StatelessWidget {
  const BiometricBuilderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BiometricBuilder Demo')),
      body: BiometricBuilder(
        shield: shield,
        reason: 'Verify identity to view account details',
        userId: 'demo-user',
        reauthOnResume: true,
        autoAuthenticate: true,
        builder: (context, state) {
          return switch (state) {
            // ─── Idle: waiting for auto-auth to trigger ───
            AuthIdle() => const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fingerprint, size: 80, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('Preparing authentication...'),
                  ],
                ),
              ),

            // ─── Authenticating: prompt is showing ───
            AuthAuthenticating() => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Verifying your identity...',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text('Please use Face ID or your fingerprint'),
                  ],
                ),
              ),

            // ─── Authenticated: show the protected content ───
            AuthAuthenticated(:final session, :final token) => ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Card(
                    color: Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Authenticated',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'via ${session.methodUsed.name}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Session details
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Session Details',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          _infoRow('Session ID', session.sessionId),
                          _infoRow('User', session.userId),
                          _infoRow('Method', session.methodUsed.name),
                          _infoRow(
                            'Expires in',
                            '${session.remainingValidity.inMinutes}m '
                                '${session.remainingValidity.inSeconds % 60}s',
                          ),
                          _infoRow(
                            'Token',
                            token != null
                                ? '${token.length > 20 ? token.substring(0, 20) : token}...'
                                : 'No token',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Simulated account content
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Account Details',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          _infoRow('Name', 'Vipin Kumar'),
                          _infoRow('Email', 'vipin@example.com'),
                          _infoRow('Plan', 'Premium'),
                          _infoRow('Balance', '\$12,450.00'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

            // ─── Failed: show error with retry ───
            AuthFailed(:final result) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        'Authentication Failed',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _describeFailure(result),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Go Back'),
                      ),
                    ],
                  ),
                ),
              ),
          };
        },
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _describeFailure(BiometricResult result) {
    return result.when(
      success: (_, _) => 'Unexpected success in failure state',
      fallbackSuccess: (_, _, _) => 'Unexpected fallback success',
      sessionValid: (_, _) => 'Unexpected session valid',
      tokenExpired: () => 'Your token has expired. Please sign in again.',
      cancelled: () => 'You cancelled the authentication.',
      lockedOut: (until) {
        final remaining = until.difference(DateTime.now().toUtc());
        return 'Too many attempts. Locked for '
            '${remaining.inMinutes}m ${remaining.inSeconds % 60}s.';
      },
      unavailable: (reason, message) =>
          message ?? 'Biometric not available: ${reason.name}',
      invalidated: () =>
          'Your biometric data changed. Please re-enroll.',
      reauthenticationRequired: (reason) =>
          reason ?? 'Your session has expired. Please sign in again.',
      error: (msg, _) => 'Error: $msg',
    );
  }
}
