import 'package:flutter/material.dart';
import 'package:biometric_shield/biometric_shield.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

/// Example app demonstrating BiometricShield SDK integration.
///
/// This app shows three common patterns:
/// 1. Gate on app launch (Pattern 1 from SOUL.md)
/// 2. Sensitive action gate using BiometricGate widget (Pattern 2)
/// 3. Programmatic authentication for one-off actions
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure BiometricShield once at app startup.
  // All fields are optional — sensible defaults are used.
  await BiometricShield.configure(BiometricConfig(
    sessionDuration: const Duration(minutes: 15),
    sessionResetsOnActivity: true,
    maxAttempts: 3,
    lockoutDuration: const Duration(minutes: 5),
    fallbackChain: const [BiometricFallback.deviceCredential],
    onTokenExpired: () async {
      // Redirect to full login when the stored token has expired.
      // In a real app, this would navigate to your login screen
      // or trigger a server token refresh.
      debugPrint('[BiometricShield] Token expired — redirecting to login');
    },
    onLockoutStart: (lockedUntil) {
      debugPrint('[BiometricShield] Locked out until $lockedUntil');
    },
    onLockoutEnd: () {
      debugPrint('[BiometricShield] Lockout ended');
    },
    onUserCancelled: () {
      debugPrint('[BiometricShield] User cancelled authentication');
    },
    onBiometricInvalidated: () {
      debugPrint('[BiometricShield] Biometric invalidated — re-enroll needed');
    },
    onEvent: (event) {
      // Pipe all audit events to your analytics service.
      debugPrint('[BiometricShield] Event: ${event.type.name} '
          'user=${event.userId} ${event.properties}');
    },
  ));

  runApp(const BiometricShieldExampleApp());
}

class BiometricShieldExampleApp extends StatelessWidget {
  const BiometricShieldExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BiometricShield Example',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
      },
    );
  }
}
