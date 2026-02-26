import 'event_type.dart';
import '../core/biometric_session.dart';

/// An audit event emitted by the BiometricShield SDK.
///
/// Every meaningful SDK action produces a [BiometricEvent] that is
/// delivered to [BiometricConfig.onEvent]. Log these to your analytics
/// or HIPAA audit store.
class BiometricEvent {
  /// The type of event that occurred.
  final BiometricEventType type;

  /// The userId this event pertains to.
  final String userId;

  /// When this event occurred.
  final DateTime timestamp;

  /// The biometric method involved, if applicable.
  final BiometricAuthMethod? method;

  /// Arbitrary key-value properties for additional context.
  final Map<String, dynamic> properties;

  const BiometricEvent({
    required this.type,
    required this.userId,
    required this.timestamp,
    this.method,
    this.properties = const {},
  });

  @override
  String toString() =>
      'BiometricEvent(type: $type, userId: $userId, timestamp: $timestamp)';
}
