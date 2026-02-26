import 'package:flutter/widgets.dart';

/// Callbacks provided to a custom fallback UI widget.
///
/// The SDK passes these to [CustomFallbackBuilder] so the custom UI
/// can communicate auth outcomes back to the SDK.
class CustomFallbackCallbacks {

  const CustomFallbackCallbacks({
    required this.onSuccess,
    required this.onCancel,
    required this.onFailure,
  });
  /// Call this when the user successfully completes your custom auth.
  final void Function() onSuccess;

  /// Call this if the user cancels your custom auth flow.
  final void Function() onCancel;

  /// Call this if the user fails your custom auth (increments attempt counter).
  final void Function() onFailure;
}

/// Builder function for custom fallback authentication UI.
///
/// Receives the [BuildContext] and [CustomFallbackCallbacks] to communicate
/// auth outcomes back to the SDK.
typedef CustomFallbackBuilder = Widget Function(
  BuildContext context,
  CustomFallbackCallbacks callbacks,
);
