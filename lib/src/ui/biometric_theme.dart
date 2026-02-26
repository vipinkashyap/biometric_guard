import 'package:flutter/widgets.dart';

/// Visual customization model for all SDK-owned UI surfaces.
///
/// Pass this via [BiometricConfig.theme] to brand the biometric
/// prompt, lockout screen, and fallback bottom sheet.
class BiometricTheme {
  /// Primary accent color used for buttons and interactive elements.
  final Color? primaryColor;

  /// Background color for SDK-owned surfaces.
  final Color? backgroundColor;

  /// Color used for error states and warning text.
  final Color? errorColor;

  /// Text style for titles (e.g. "Verify your identity").
  final TextStyle? titleStyle;

  /// Text style for subtitles and descriptions.
  final TextStyle? subtitleStyle;

  /// Text style for button labels.
  final TextStyle? buttonStyle;

  /// Border radius for the bottom sheet.
  final BorderRadius? sheetBorderRadius;

  /// Custom icon to replace the default fingerprint/face icon.
  final Widget? biometricIcon;

  /// Custom icon shown on the lockout screen.
  final Widget? lockoutIcon;

  /// Maximum height of the bottom sheet as a fraction of screen height
  /// (e.g. 0.4 for 40%).
  final double? sheetMaxHeight;

  const BiometricTheme({
    this.primaryColor,
    this.backgroundColor,
    this.errorColor,
    this.titleStyle,
    this.subtitleStyle,
    this.buttonStyle,
    this.sheetBorderRadius,
    this.biometricIcon,
    this.lockoutIcon,
    this.sheetMaxHeight,
  });
}
