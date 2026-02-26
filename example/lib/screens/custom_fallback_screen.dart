import 'dart:async';

import 'package:flutter/material.dart';
import 'package:biometric_shield/biometric_shield.dart';
import '../main.dart';

/// Demonstrates a custom FallbackHandler implementation.
///
/// Instead of using the SDK's MaterialFallbackHandler, this example
/// shows how to build your own fallback UI — a full-screen PIN entry.
///
/// This is useful when:
/// - Your app has a custom design system
/// - You need specialized fallback flows (OTP, security questions, etc.)
/// - You want full control over the fallback UX
class CustomFallbackScreen extends StatefulWidget {
  const CustomFallbackScreen({super.key});

  @override
  State<CustomFallbackScreen> createState() => _CustomFallbackScreenState();
}

class _CustomFallbackScreenState extends State<CustomFallbackScreen> {
  String? _statusMessage;
  bool _isLoading = false;

  /// Authenticate using a shield with a custom fallback handler.
  Future<void> _authenticateWithCustomFallback() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Authenticating...';
    });

    // Create a temporary shield with a custom fallback handler.
    // In a real app, you'd configure this once at app startup.
    final customShield = BiometricShield(
      config: BiometricConfig(
        sessionDuration: const Duration(minutes: 15),
        fallbackChain: const [
          BiometricFallback.deviceCredential,
          BiometricFallback.customPin,
        ],
        fallbackHandler: _AppPinFallbackHandler(context),
        onEvent: (event) {
          debugPrint('[CustomFallback] ${event.type.name}: ${event.properties}');
        },
      ),
    );

    try {
      final result = await customShield.authenticate(
        reason: 'Confirm identity with custom PIN',
        userId: 'demo-user',
      );

      if (!mounted) return;

      result.when(
        success: (session, token) {
          setState(() {
            _statusMessage = 'Authenticated via ${session.methodUsed.name}';
            _isLoading = false;
          });
        },
        fallbackSuccess: (method, session, token) {
          setState(() {
            _statusMessage =
                'Authenticated via custom fallback: ${method.name}';
            _isLoading = false;
          });
        },
        sessionValid: (session, token) {
          setState(() {
            _statusMessage = 'Session still valid';
            _isLoading = false;
          });
        },
        tokenExpired: () {
          setState(() {
            _statusMessage = 'Token expired';
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
          setState(() {
            _statusMessage = 'Locked out until $until';
            _isLoading = false;
          });
        },
        unavailable: (reason, message) {
          setState(() {
            _statusMessage = message ?? 'Unavailable: ${reason.name}';
            _isLoading = false;
          });
        },
        invalidated: () {
          setState(() {
            _statusMessage = 'Biometric invalidated';
            _isLoading = false;
          });
        },
        reauthenticationRequired: (reason) {
          setState(() {
            _statusMessage = reason ?? 'Re-auth required';
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
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Custom Fallback Handler')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How it works',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This demo creates a BiometricShield with a custom '
                      'FallbackHandler. When biometric auth fails, instead '
                      'of using the SDK\'s Material bottom sheet, it navigates '
                      'to a full-screen PIN entry page.\n\n'
                      'The FallbackHandler interface is simple: implement '
                      'handleFallback() and return success, failed, or cancelled.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_statusMessage != null) ...[
              Text(
                _statusMessage!,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed: _isLoading ? null : _authenticateWithCustomFallback,
              icon: const Icon(Icons.pin),
              label: const Text('Authenticate (Custom PIN Fallback)'),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// Custom FallbackHandler — navigates to a full-screen PIN page
// ────────────────────────────────────────────────────────────────

/// A custom [FallbackHandler] that shows a full-screen PIN entry.
///
/// In a real app, this could be a 6-digit PIN, a password field,
/// a security question screen, or an OTP entry — whatever your
/// app's design requires. The SDK doesn't care what you show;
/// it just needs a [FallbackResult] back.
class _AppPinFallbackHandler extends FallbackHandler {
  final BuildContext context;

  _AppPinFallbackHandler(this.context);

  @override
  Future<FallbackResult> handleFallback({
    required BiometricFallback type,
    required String reason,
  }) async {
    // Navigate to a full-screen PIN entry page.
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _PinEntryPage(reason: reason, fallbackType: type),
      ),
    );

    // null means the user pressed back (cancelled)
    if (result == null) return FallbackResult.cancelled;
    return result ? FallbackResult.success : FallbackResult.failed;
  }
}

// ────────────────────────────────────────────────────────────────
// Full-screen PIN entry page
// ────────────────────────────────────────────────────────────────

class _PinEntryPage extends StatefulWidget {
  final String reason;
  final BiometricFallback fallbackType;

  const _PinEntryPage({
    required this.reason,
    required this.fallbackType,
  });

  @override
  State<_PinEntryPage> createState() => _PinEntryPageState();
}

class _PinEntryPageState extends State<_PinEntryPage> {
  final _pinController = TextEditingController();
  String? _error;

  // In a real app, this would validate against a stored hash.
  static const _correctPin = '1234';

  void _submit() {
    if (_pinController.text == _correctPin) {
      Navigator.of(context).pop(true); // success
    } else {
      setState(() => _error = 'Incorrect PIN. Try again.');
      _pinController.clear();
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Enter ${widget.fallbackType.name}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null), // cancelled
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: Colors.blue),
            const SizedBox(height: 24),
            Text(
              widget.reason,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Biometric authentication was not available.\n'
              'Enter your PIN to continue.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: InputDecoration(
                hintText: '• • • •',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            const Text(
              'Hint: PIN is 1234',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: const Text('Verify PIN'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
