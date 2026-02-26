import 'dart:async';

import 'package:flutter/material.dart';
import 'package:biometric_shield/biometric_shield.dart';
import '../main.dart';
import 'sensitive_data_screen.dart';

/// Home screen shown after successful authentication.
///
/// Demonstrates:
/// - Checking session validity via stream
/// - Programmatic re-authentication for sensitive actions
/// - Logout (session clearing)
/// - Navigating to a BiometricGate-protected screen (Pattern 2)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _sessionInfo;
  String? _token;

  @override
  void initState() {
    super.initState();
    _loadSessionInfo();
  }

  Future<void> _loadSessionInfo() async {
    final hasSession = await shield.hasValidSession(userId: 'demo-user');
    final token = await shield.getToken(userId: 'demo-user');

    setState(() {
      _sessionInfo = hasSession ? 'Active session' : 'No active session';
      _token = token != null
          ? '${token.substring(0, 20)}...'
          : 'No token stored';
    });
  }

  /// Programmatic re-auth for a one-off sensitive action.
  Future<void> _performSensitiveAction() async {
    final result = await shield.authenticate(
      reason: 'Confirm to transfer funds',
      userId: 'demo-user',
      requireFresh: true, // Force re-auth even if session is valid
    );

    final message = result.when(
      success: (_, __) => 'Transfer authorized!',
      fallbackSuccess: (_, __, ___) => 'Transfer authorized via fallback',
      sessionValid: (_, __) => 'Session valid — transfer authorized',
      tokenExpired: () => 'Token expired — cannot authorize',
      cancelled: () => 'Transfer cancelled by user',
      lockedOut: (until) => 'Locked out — try later',
      unavailable: (reason, message) => message ?? 'Biometric unavailable: ${reason.name}',
      invalidated: () => 'Biometric invalidated',
      reauthenticationRequired: (reason) => reason ?? 'Please sign in again',
      error: (msg, _) => 'Error: $msg',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  /// Navigate to a screen protected by BiometricGate widget.
  void _openSensitiveData() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SensitiveDataScreen()),
    );
  }

  /// Clear session and navigate back to login.
  Future<void> _logout() async {
    await shield.clearSession(userId: 'demo-user');
    if (mounted) {
      unawaited(Navigator.of(context).pushReplacementNamed('/login'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Security Settings',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Session info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session Status',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('Status: ${_sessionInfo ?? "Loading..."}'),
                    Text('Token: ${_token ?? "Loading..."}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Pattern 3: Programmatic auth for sensitive action
            FilledButton.icon(
              onPressed: _performSensitiveAction,
              icon: const Icon(Icons.send),
              label: const Text('Transfer Funds (requireFresh)'),
            ),
            const SizedBox(height: 12),

            // Pattern 2: Navigate to BiometricGate-wrapped screen
            OutlinedButton.icon(
              onPressed: _openSensitiveData,
              icon: const Icon(Icons.lock),
              label: const Text('View Health Records (BiometricGate)'),
            ),
            const SizedBox(height: 12),

            // Validate or re-auth (silent)
            TextButton.icon(
              onPressed: () async {
                final result = await shield.validateOrAuthenticate(
                  reason: 'Verify session',
                  userId: 'demo-user',
                );
                final status = result.when(
                  success: (_, __) => 'Fresh auth succeeded',
                  fallbackSuccess: (_, __, ___) => 'Fallback auth succeeded',
                  sessionValid: (_, __) => 'Session still valid — no prompt shown',
                  tokenExpired: () => 'Token expired',
                  cancelled: () => 'Cancelled',
                  lockedOut: (_) => 'Locked out',
                  unavailable: (r, msg) => msg ?? 'Unavailable: ${r.name}',
                  invalidated: () => 'Invalidated',
                  reauthenticationRequired: (r) => r ?? 'Re-auth required',
                  error: (m, _) => 'Error: $m',
                );
                // ignore: use_build_context_synchronously
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(status)),
                  );
                }
                unawaited(_loadSessionInfo());
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Validate or Re-authenticate'),
            ),
          ],
        ),
      ),
    );
  }
}
