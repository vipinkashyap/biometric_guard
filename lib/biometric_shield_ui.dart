/// BiometricShield Flutter UI layer.
///
/// Provides reactive widgets and Material UI handlers for biometric auth.
/// Import this to access:
/// - [BiometricBuilder] — reactive widget for auth state
/// - [BiometricGate] — convenience wrapper for "gate access" pattern
/// - [MaterialFallbackHandler] — Material UI for fallbacks
/// - [BiometricTheme] and [BiometricStrings] — customization
///
/// ```dart
/// import 'package:biometric_shield/biometric_shield_ui.dart';
/// ```
library;

export 'src/ui/biometric_builder.dart';
export 'src/ui/biometric_gate.dart';
export 'src/ui/material_fallback_handler.dart';
export 'src/ui/biometric_theme.dart';
export 'src/ui/biometric_strings.dart';
