import 'package:flutter/material.dart';

import '../core/biometric_result.dart';
import 'biometric_theme.dart';
import 'biometric_strings.dart';

/// Programmatic trigger for the biometric prompt bottom sheet.
///
/// Use this when you want to show the SDK's prompt UI
/// independently of [BiometricGate].
class BiometricPrompt {
  /// Show the biometric prompt bottom sheet.
  ///
  /// Returns the [BiometricResult] after the user completes or
  /// cancels the authentication flow.
  static Future<void> show({
    required BuildContext context,
    required String reason,
    required Future<BiometricResult> Function() onAuthenticate,
    required void Function(BiometricResult result) onResult,
    BiometricTheme? theme,
    BiometricStrings? strings,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: true,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: theme?.sheetBorderRadius ??
            const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      backgroundColor: theme?.backgroundColor,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height *
            (theme?.sheetMaxHeight ?? 0.4),
      ),
      builder: (sheetContext) => _BiometricPromptSheet(
        reason: reason,
        onAuthenticate: onAuthenticate,
        onResult: onResult,
        theme: theme,
        strings: strings,
      ),
    );
  }
}

class _BiometricPromptSheet extends StatefulWidget {

  const _BiometricPromptSheet({
    required this.reason,
    required this.onAuthenticate,
    required this.onResult,
    this.theme,
    this.strings,
  });
  final String reason;
  final Future<BiometricResult> Function() onAuthenticate;
  final void Function(BiometricResult result) onResult;
  final BiometricTheme? theme;
  final BiometricStrings? strings;

  @override
  State<_BiometricPromptSheet> createState() => _BiometricPromptSheetState();
}

class _BiometricPromptSheetState extends State<_BiometricPromptSheet> {
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    _startAuth();
  }

  Future<void> _startAuth() async {
    setState(() => _isAuthenticating = true);

    final result = await widget.onAuthenticate();

    if (mounted) {
      setState(() => _isAuthenticating = false);
      widget.onResult(result);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final strings = widget.strings;

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

          // Icon
          theme?.biometricIcon ??
              Icon(
                Icons.fingerprint,
                size: 64,
                color: theme?.primaryColor ?? Colors.blue,
              ),

          const SizedBox(height: 16),

          // Title
          Text(
            widget.reason,
            style: theme?.titleStyle ??
                const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 24),

          if (_isAuthenticating)
            CircularProgressIndicator(
              color: theme?.primaryColor,
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    strings?.cancelButton ?? 'Cancel',
                    style: theme?.buttonStyle,
                  ),
                ),
                ElevatedButton(
                  onPressed: _startAuth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme?.primaryColor,
                  ),
                  child: Text(
                    'Try Again',
                    style: theme?.buttonStyle,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
