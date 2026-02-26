import 'package:flutter/material.dart';
import 'package:biometric_shield/biometric_shield.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

// Create a single BiometricShield instance for the app.
// In a real app, this would be provided via a DI framework (Provider, Riverpod, GetIt).
final shield = BiometricShield(
  BiometricConfig(
    sessionDuration: const Duration(minutes: 15),
    sessionResetsOnActivity: true,
    maxAttempts: 3,
    lockoutDuration: const Duration(minutes: 5),
    fallbackChain: const [BiometricFallback.deviceCredential],
    onEvent: (event) {
      // Pipe all audit events to your analytics service.
      debugPrint('[BiometricShield] Event: ${event.type.name} '
          'user=${event.userId} ${event.properties}');
    },
  ),
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
