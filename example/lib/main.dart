import 'package:flutter/material.dart';
import 'package:biometric_shield/biometric_shield.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/biometric_builder_screen.dart';
import 'screens/custom_fallback_screen.dart';
import 'screens/multi_user_screen.dart';

// Create a single BiometricShield instance for the app.
// In a real app, this would be provided via a DI framework (Provider, Riverpod, GetIt).
//
// Integration points:
// - tokenLifecycle: Plug in your backend (Firebase, REST JWT, Supabase, Amplify)
// - policyProvider: Let your server enforce biometric rules
// - fallbackHandler: Custom PIN/password UI
// - tokenStore: Custom secure storage
// - onEvent: Analytics / HIPAA audit trail
//
// All are optional — the SDK works with zero config.
final shield = BiometricShield(
  config: BiometricConfig(
    sessionDuration: const Duration(minutes: 15),
    sessionResetsOnActivity: true,
    maxAttempts: 3,
    lockoutDuration: const Duration(minutes: 5),
    fallbackChain: const [BiometricFallback.deviceCredential],
    // tokenLifecycle: MyFirebaseTokenLifecycle(),   // <-- your backend adapter
    // policyProvider: MyApiPolicyProvider(apiClient), // <-- server policy
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
        '/settings': (context) => const SettingsScreen(),
        '/builder-demo': (context) => const BiometricBuilderScreen(),
        '/custom-fallback': (context) => const CustomFallbackScreen(),
        '/multi-user': (context) => const MultiUserScreen(),
      },
    );
  }
}
