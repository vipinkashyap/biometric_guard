import 'package:flutter/material.dart';
import 'package:biometric_shield/biometric_shield.dart';
import '../main.dart';

/// Demonstrates runtime user preferences via [BiometricPreferences].
///
/// Shows how to build a settings screen that controls:
/// - Biometric enable/disable toggle
/// - "Remember Me" toggle (session persistence)
/// - Session timeout duration
/// - Reauth on resume toggle
///
/// All preferences are persisted per-user and take effect on the
/// next authentication attempt — no SDK restart needed.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricEnabled = true;
  bool _rememberMe = true;
  bool _reauthOnResume = false;
  Duration? _sessionDuration;
  bool _isLoading = true;

  static const _userId = 'demo-user';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = shield.preferences;
    final biometricEnabled = await prefs.isBiometricEnabled(userId: _userId);
    final rememberMe = await prefs.isRememberMeEnabled(userId: _userId);
    final reauthOnResume = await prefs.isReauthOnResumeEnabled(userId: _userId);
    final sessionDuration = await prefs.getSessionDurationOverride(
      userId: _userId,
    );

    setState(() {
      _biometricEnabled = biometricEnabled;
      _rememberMe = rememberMe;
      _reauthOnResume = reauthOnResume;
      _sessionDuration = sessionDuration;
      _isLoading = false;
    });
  }

  Future<void> _setBiometricEnabled(bool value) async {
    await shield.preferences.setBiometricEnabled(value, userId: _userId);
    setState(() => _biometricEnabled = value);
  }

  Future<void> _setRememberMe(bool value) async {
    await shield.preferences.setRememberMe(value, userId: _userId);
    setState(() => _rememberMe = value);
  }

  Future<void> _setReauthOnResume(bool value) async {
    await shield.preferences.setReauthOnResume(value, userId: _userId);
    setState(() => _reauthOnResume = value);
  }

  Future<void> _setSessionDuration(Duration? duration) async {
    await shield.preferences.setSessionDurationOverride(
      duration,
      userId: _userId,
    );
    setState(() => _sessionDuration = duration);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Security Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Security Settings')),
      body: ListView(
        children: [
          // ─── Biometric Toggle ───
          SwitchListTile(
            title: const Text('Biometric Authentication'),
            subtitle: const Text(
              'Use fingerprint or face to unlock the app',
            ),
            value: _biometricEnabled,
            onChanged: _setBiometricEnabled,
            secondary: const Icon(Icons.fingerprint),
          ),
          const Divider(),

          // ─── Remember Me ───
          SwitchListTile(
            title: const Text('Remember Me'),
            subtitle: Text(
              _rememberMe
                  ? 'Session persists across app restarts'
                  : 'You\'ll need to sign in each time',
            ),
            value: _rememberMe,
            onChanged: _setRememberMe,
            secondary: const Icon(Icons.bookmark),
          ),
          const Divider(),

          // ─── Reauth on Resume ───
          SwitchListTile(
            title: const Text('Lock on Background'),
            subtitle: const Text(
              'Require authentication when returning to the app',
            ),
            value: _reauthOnResume,
            onChanged: _setReauthOnResume,
            secondary: const Icon(Icons.lock_clock),
          ),
          const Divider(),

          // ─── Session Timeout ───
          ListTile(
            leading: const Icon(Icons.timer),
            title: const Text('Session Timeout'),
            subtitle: Text(
              _sessionDuration != null
                  ? '${_sessionDuration!.inMinutes} minutes'
                  : 'Default (${shield.config.sessionDuration.inMinutes} min)',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showTimeoutPicker(context),
          ),
          const Divider(),

          // ─── Clear All Data ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              onPressed: () async {
                await shield.clearAll(userId: _userId);
                await shield.preferences.clearAll(userId: _userId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All biometric data cleared')),
                  );
                  await _loadPreferences();
                }
              },
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text(
                'Clear All Biometric Data',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ),

          // ─── Info Card ───
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How it works',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'These settings are stored securely on-device and '
                      'scoped to your account. Changes take effect on the '
                      'next authentication attempt — no app restart needed.\n\n'
                      'If your organization enforces a security policy, '
                      'some settings may be overridden by your admin.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTimeoutPicker(BuildContext context) {
    final options = <Duration?>[
      null, // default
      const Duration(minutes: 1),
      const Duration(minutes: 5),
      const Duration(minutes: 15),
      const Duration(minutes: 30),
      const Duration(hours: 1),
    ];

    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Session Timeout',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...options.map((duration) {
                final label = duration == null
                    ? 'Default (${shield.config.sessionDuration.inMinutes} min)'
                    : '${duration.inMinutes} minutes';
                final isSelected = _sessionDuration == duration;

                return ListTile(
                  title: Text(label),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: Colors.blue)
                      : null,
                  onTap: () {
                    _setSessionDuration(duration);
                    Navigator.pop(context);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
