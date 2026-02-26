import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../fallback/fallback_handler.dart';
import '../fallback/fallback_type.dart';
import 'biometric_theme.dart';
import 'biometric_strings.dart';

/// Callback signature for custom PIN/password builder.
///
/// The builder receives the current context and a set of callbacks
/// to communicate success, cancellation, or failure.
typedef CustomFallbackBuilder = Widget Function(
  BuildContext context,
  CustomFallbackCallbacks callbacks,
);

/// Callbacks passed to the custom fallback builder.
///
/// The builder calls one of these to signal the result of fallback auth.
class CustomFallbackCallbacks {
  const CustomFallbackCallbacks({
    required this.onSuccess,
    required this.onCancel,
    required this.onFailure,
  });

  /// Called when the user successfully completes fallback authentication.
  final void Function() onSuccess;

  /// Called when the user cancels fallback authentication.
  final void Function() onCancel;

  /// Called when fallback authentication fails (e.g., wrong PIN).
  final void Function() onFailure;
}

/// Default Material fallback UI handler for BiometricShield.
///
/// Handles fallback authentication flows by presenting Material UI:
/// - For [BiometricFallback.deviceCredential], uses [local_auth]
/// - For [BiometricFallback.customPin] or [customPassword], shows
///   the custom builder in a bottom sheet or dialog
///
/// Inject this into [BiometricConfig.fallbackHandler] to customize
/// fallback presentation.
///
/// Example:
/// ```dart
/// final shield = BiometricShield(BiometricConfig(
///   fallbackHandler: MaterialFallbackHandler(
///     context: context,
///     customBuilder: (ctx, callbacks) => MyPinSheet(
///       onSuccess: callbacks.onSuccess,
///       onCancel: callbacks.onCancel,
///     ),
///     theme: BiometricTheme(primaryColor: Colors.blue),
///     strings: BiometricStrings(
///       cancelButton: 'Cancel',
///     ),
///   ),
/// ));
/// ```
class MaterialFallbackHandler extends FallbackHandler {
  /// The BuildContext for showing bottom sheets and overlays.
  final BuildContext context;

  /// Optional builder for custom PIN/password UI.
  /// If null, custom fallbacks cannot be handled.
  final CustomFallbackBuilder? customBuilder;

  /// Visual customization (colors, text styles, icons, etc).
  final BiometricTheme? theme;

  /// String customization (copy, localization, etc).
  final BiometricStrings? strings;

  MaterialFallbackHandler({
    required this.context,
    this.customBuilder,
    this.theme,
    this.strings,
  });

  @override
  Future<FallbackResult> handleFallback({
    required BiometricFallback type,
    required String reason,
  }) async {
    return switch (type) {
      BiometricFallback.deviceCredential => _handleDeviceCredential(reason),
      BiometricFallback.customPin ||
      BiometricFallback.customPassword =>
        _handleCustomFallback(type, reason),
      BiometricFallback.none => Future.value(FallbackResult.cancelled),
    };
  }

  /// Handle device credential fallback using local_auth.
  Future<FallbackResult> _handleDeviceCredential(String reason) async {
    try {
      final localAuth = LocalAuthentication();
      final authenticated = await localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      return authenticated ? FallbackResult.success : FallbackResult.cancelled;
    } catch (e) {
      // Platform error or user cancelled
      return FallbackResult.cancelled;
    }
  }

  /// Handle custom PIN or password fallback using the provided builder.
  Future<FallbackResult> _handleCustomFallback(
    BiometricFallback type,
    String reason,
  ) async {
    if (customBuilder == null) {
      // No custom builder provided — cannot handle this fallback
      return FallbackResult.failed;
    }

    // Track the result from the custom builder
    var result = FallbackResult.cancelled;

    if (!context.mounted) {
      return FallbackResult.failed;
    }

    // Show custom fallback UI in a bottom sheet
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: theme?.sheetBorderRadius ?? BorderRadius.zero,
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          maxChildSize: theme?.sheetMaxHeight ?? 0.75,
          builder: (scrollContext, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: customBuilder!(
                  scrollContext,
                  CustomFallbackCallbacks(
                    onSuccess: () {
                      result = FallbackResult.success;
                      Navigator.pop(sheetContext);
                    },
                    onCancel: () {
                      result = FallbackResult.cancelled;
                      Navigator.pop(sheetContext);
                    },
                    onFailure: () {
                      result = FallbackResult.failed;
                      Navigator.pop(sheetContext);
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    return result;
  }
}
