import 'package:flutter/material.dart';

import '../session/lockout_state.dart';
import 'biometric_theme.dart';
import 'biometric_strings.dart';

/// Internal bottom sheet shown during lockout or when biometric
/// is unavailable.
class BiometricBottomSheet {
  /// Show the lockout state bottom sheet.
  static Future<void> showLockout({
    required BuildContext context,
    required LockoutState lockoutState,
    BiometricTheme? theme,
    BiometricStrings? strings,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: true,
      shape: RoundedRectangleBorder(
        borderRadius: theme?.sheetBorderRadius ??
            const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      backgroundColor: theme?.backgroundColor,
      builder: (sheetContext) => _LockoutSheet(
        lockoutState: lockoutState,
        theme: theme,
        strings: strings,
      ),
    );
  }

  /// Show the "biometric unavailable" bottom sheet.
  static Future<void> showUnavailable({
    required BuildContext context,
    required String reason,
    BiometricTheme? theme,
    BiometricStrings? strings,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: true,
      shape: RoundedRectangleBorder(
        borderRadius: theme?.sheetBorderRadius ??
            const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      backgroundColor: theme?.backgroundColor,
      builder: (sheetContext) => _UnavailableSheet(
        reason: reason,
        theme: theme,
        strings: strings,
      ),
    );
  }
}

class _LockoutSheet extends StatelessWidget {
  final LockoutState lockoutState;
  final BiometricTheme? theme;
  final BiometricStrings? strings;

  const _LockoutSheet({
    required this.lockoutState,
    this.theme,
    this.strings,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = lockoutState.remainingLockout ?? Duration.zero;
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Lockout icon
          theme?.lockoutIcon ??
              Icon(
                Icons.lock_outline,
                size: 64,
                color: theme?.errorColor ?? Colors.red,
              ),

          const SizedBox(height: 16),

          Text(
            strings?.lockoutTitle ?? 'Too Many Attempts',
            style: theme?.titleStyle ??
                const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
          ),

          const SizedBox(height: 8),

          Text(
            strings?.lockoutMessage?.call(remaining) ??
                'Please try again in ${minutes}m ${seconds}s',
            style: theme?.subtitleStyle ??
                TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 24),

          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _UnavailableSheet extends StatelessWidget {
  final String reason;
  final BiometricTheme? theme;
  final BiometricStrings? strings;

  const _UnavailableSheet({
    required this.reason,
    this.theme,
    this.strings,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Icon(
            Icons.warning_amber_rounded,
            size: 64,
            color: theme?.errorColor ?? Colors.orange,
          ),

          const SizedBox(height: 16),

          Text(
            strings?.biometricUnavailableTitle ?? 'Biometric Unavailable',
            style: theme?.titleStyle ??
                const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
          ),

          const SizedBox(height: 8),

          Text(
            strings?.biometricUnavailableMessage ?? reason,
            style: theme?.subtitleStyle ??
                TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 24),

          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
