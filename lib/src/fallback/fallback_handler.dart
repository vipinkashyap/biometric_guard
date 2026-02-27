import 'fallback_type.dart';

/// Result of a fallback attempt.
enum FallbackResult {
  /// Fallback authentication succeeded.
  success,

  /// Fallback authentication failed (wrong PIN, wrong password, etc).
  failed,

  /// User cancelled the fallback prompt.
  cancelled,
}

/// Interface for handling fallback authentication UI.
///
/// Implementers (e.g., MaterialFallbackHandler in the UI layer)
/// handle custom PIN/password UI for fallback authentication.
abstract class FallbackHandler {
  /// Attempt a fallback authentication.
  ///
  /// [type] — the fallback type (customPin, customPassword, etc.)
  /// [reason] — user-facing reason shown in the prompt
  ///
  /// Returns the result of the fallback attempt.
  Future<FallbackResult> handleFallback({
    required BiometricFallback type,
    required String reason,
  });
}
