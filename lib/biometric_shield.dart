/// BiometricShield — A composable Flutter SDK for biometric authentication.
///
/// Wraps all biometric authentication concerns into an injectable,
/// namespace-aware layer with typed results, fallback chains,
/// and audit event emission.
library biometric_shield;

// Core
export 'src/core/biometric_config.dart';
export 'src/core/biometric_result.dart';
export 'src/core/biometric_session.dart';
export 'src/core/biometric_shield.dart';

// Platform
export 'src/platform/biometric_capability.dart';

// Fallback
export 'src/fallback/fallback_type.dart';
export 'src/fallback/fallback_handler.dart';

// Storage
export 'src/storage/token_store_interface.dart';

// Session
export 'src/session/lockout_state.dart';

// UI
export 'src/ui/biometric_gate.dart';
export 'src/ui/biometric_theme.dart';
export 'src/ui/biometric_strings.dart';

// Analytics
export 'src/analytics/biometric_event.dart';
export 'src/analytics/event_type.dart';
