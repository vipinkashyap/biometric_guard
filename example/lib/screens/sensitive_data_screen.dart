import 'package:flutter/material.dart';
import 'package:biometric_shield/biometric_shield_ui.dart';
import '../main.dart';

/// Demonstrates Pattern 2: Sensitive Action Gate (Widget).
///
/// Wraps the actual content inside a [BiometricGate] widget.
/// The gate handles authentication automatically — the child
/// is only shown after successful auth.
class SensitiveDataScreen extends StatelessWidget {
  const SensitiveDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Health Records')),
      body: BiometricGate(
        shield: shield,
        reason: 'Confirm to view health records',
        userId: 'demo-user',
        reauthOnResume: true,

        // Called when auth succeeds — use for analytics side effects.
        onAuthenticated: (result) {
          debugPrint('Health records unlocked: $result');
        },

        // Shown when all auth methods fail.
        fallbackWidget: (result) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Access Denied',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Authentication is required to view health records.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),

        // The actual content — only shown after successful auth.
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildRecordCard(
              context,
              title: 'Annual Physical',
              date: 'Jan 15, 2026',
              doctor: 'Dr. Smith',
              notes: 'All vitals normal. Cholesterol slightly elevated.',
            ),
            _buildRecordCard(
              context,
              title: 'Blood Work',
              date: 'Dec 3, 2025',
              doctor: 'LabCorp',
              notes: 'CBC, CMP, Lipid panel — results within range.',
            ),
            _buildRecordCard(
              context,
              title: 'Dental Checkup',
              date: 'Nov 20, 2025',
              doctor: 'Dr. Johnson',
              notes: 'No cavities. Recommended flossing more often.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordCard(
    BuildContext context, {
    required String title,
    required String date,
    required String doctor,
    required String notes,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  date,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              doctor,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(notes),
          ],
        ),
      ),
    );
  }
}
