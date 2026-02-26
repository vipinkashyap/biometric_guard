import 'dart:async';

import 'package:flutter/material.dart';
import 'package:biometric_shield/biometric_shield.dart';
import '../main.dart';

/// Demonstrates Pattern 1: Gate on App Launch.
///
/// After initial server login, store a token via BiometricShield.
/// On subsequent launches, authenticate with biometrics to unlock.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  BiometricCapability? _capability;
  bool _isLoading = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _checkCapability();
  }

  Future<void> _checkCapability() async {
    final capability = await shield.getCapability();
    setState(() => _capability = capability);
  }

  /// Simulate initial server login, then store token for biometric unlock.
  Future<void> _simulateServerLogin() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Signing in...';
    });

    // Simulate a server auth call (Amplify, Firebase, custom JWT, etc.)
    await Future.delayed(const Duration(seconds: 1));
    const fakeServerToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.example';

    // Store the token for future biometric-gated access.
    // This is the key integration point — after your server auth
    // succeeds, hand the token to BiometricShield.
    await shield.storeToken(
      fakeServerToken,
      userId: 'demo-user',
    );

    setState(() => _statusMessage = 'Token stored. You can now use biometrics.');

    // Navigate to home
    if (mounted) {
      unawaited(Navigator.of(context).pushReplacementNamed('/home'));
    }
  }

  /// Attempt biometric unlock (for returning users who already
  /// have a stored token).
  Future<void> _biometricUnlock() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Authenticating...';
    });

    final result = await shield.authenticate(
      reason: 'Unlock your account',
      userId: 'demo-user',
    );

    result.when(
      success: (session, token) {
        setState(() => _statusMessage = 'Authenticated via ${session.methodUsed.name}');
        unawaited(Navigator.of(context).pushReplacementNamed('/home'));
      },
      fallbackSuccess: (method, session, token) {
        setState(() => _statusMessage = 'Authenticated via fallback: ${method.name}');
        unawaited(Navigator.of(context).pushReplacementNamed('/home'));
      },
      sessionValid: (session, token) {
        setState(() => _statusMessage = 'Session still valid');
        unawaited(Navigator.of(context).pushReplacementNamed('/home'));
      },
      tokenExpired: () {
        setState(() {
          _statusMessage = 'Token expired — please sign in again';
          _isLoading = false;
        });
      },
      cancelled: () {
        setState(() {
          _statusMessage = 'Authentication cancelled';
          _isLoading = false;
        });
      },
      lockedOut: (until) {
        final remaining = until.difference(DateTime.now());
        setState(() {
          _statusMessage = 'Locked out for ${remaining.inMinutes}m ${remaining.inSeconds % 60}s';
          _isLoading = false;
        });
      },
      unavailable: (reason, message) {
        setState(() {
          _statusMessage = message ?? 'Biometric unavailable: ${reason.name}';
          _isLoading = false;
        });
      },
      invalidated: () {
        setState(() {
          _statusMessage = 'Biometric invalidated — please re-enroll';
          _isLoading = false;
        });
      },
      reauthenticationRequired: (reason) {
        setState(() {
          _statusMessage = reason ?? 'Session expired — please sign in again';
          _isLoading = false;
        });
      },
      error: (message, cause) {
        setState(() {
          _statusMessage = 'Error: $message';
          _isLoading = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BiometricShield Demo')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Device capability info
            if (_capability != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Device Capabilities',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('Biometric: ${_capability!.biometricLabel}'),
                      Text('Enrolled: ${_capability!.isEnrolled}'),
                      Text('Can authenticate: ${_capability!.canAuthenticate}'),
                      Text('Device credential: ${_capability!.supportsDeviceCredential}'),
                      if (_capability!.hasFaceID) const Text('Face ID: available'),
                      if (_capability!.hasTouchID) const Text('Touch ID: available'),
                      if (_capability!.hasStrongBiometric)
                        const Text('Strong biometric: available'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Status message
            if (_statusMessage != null) ...[
              Text(
                _statusMessage!,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],

            // Actions
            FilledButton.icon(
              onPressed: _isLoading ? null : _simulateServerLogin,
              icon: const Icon(Icons.login),
              label: const Text('Simulate Server Login'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _biometricUnlock,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Biometric Unlock (Returning User)'),
            ),
          ],
        ),
      ),
    );
  }
}
