/// BiometricShield — A composable Flutter SDK for biometric authentication.
///
/// Core package for biometric authentication. Pure Dart business logic
/// without Flutter widget dependencies.
///
/// For Flutter UI widgets, import [biometric_shield_ui] separately.
library biometric_shield;

// Core
export 'src/core/biometric_config.dart';
export 'src/core/biometric_preferences.dart';
export 'src/core/biometric_result.dart';
export 'src/core/biometric_session.dart';
export 'src/core/biometric_shield.dart';
export 'src/core/policy_provider.dart';
export 'src/core/token_lifecycle.dart';

// Platform
export 'src/platform/biometric_capability.dart';

// Fallback
export 'src/fallback/fallback_type.dart';
export 'src/fallback/fallback_handler.dart';

// Storage
export 'src/storage/token_store_interface.dart';

// Session
export 'src/session/lockout_state.dart';

// Analytics
export 'src/analytics/biometric_event.dart';
export 'src/analytics/event_type.dart';
