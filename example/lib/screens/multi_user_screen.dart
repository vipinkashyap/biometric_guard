import 'dart:async';

import 'package:flutter/material.dart';
import 'package:biometric_shield/biometric_shield.dart';
import '../main.dart';

/// Demonstrates multi-user support.
///
/// BiometricShield namespaces all data by userId. Multiple users on
/// the same device never share sessions, tokens, or lockout state.
///
/// This is common in:
/// - Shared family tablets (kids, parents have separate accounts)
/// - Enterprise apps where multiple employees share a kiosk device
/// - Healthcare apps where a nurse logs in on a shared ward tablet
class MultiUserScreen extends StatefulWidget {
  const MultiUserScreen({super.key});

  @override
  State<MultiUserScreen> createState() => _MultiUserScreenState();
}

class _MultiUserScreenState extends State<MultiUserScreen> {
  static const _users = ['alice@example.com', 'bob@example.com'];
  final Map<String, _UserState> _states = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    for (final user in _users) {
      _states[user] = _UserState();
    }
    _loadAllStates();
  }

  Future<void> _loadAllStates() async {
    for (final user in _users) {
      final hasSession = await shield.hasValidSession(userId: user);
      final token = await shield.getToken(userId: user);
      final lockout = await shield.getLockoutState(userId: user);

      if (mounted) {
        setState(() {
          _states[user] = _UserState(
            hasSession: hasSession,
            token: token,
            lockout: lockout,
          );
        });
      }
    }
  }

  Future<void> _storeTokenForUser(String userId) async {
    setState(() => _isLoading = true);
    await shield.storeToken(
      'jwt-for-$userId-${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
    );
    await _loadAllStates();
    setState(() => _isLoading = false);
  }

  Future<void> _authenticateUser(String userId) async {
    setState(() => _isLoading = true);

    try {
      final result = await shield.authenticate(
        reason: 'Unlock account for $userId',
        userId: userId,
      );

      if (!mounted) return;

      final message = result.when(
        success: (_, _) => '$userId: Auth success',
        fallbackSuccess: (m, _, _) => '$userId: Fallback success (${m.name})',
        sessionValid: (_, _) => '$userId: Session valid',
        tokenExpired: () => '$userId: Token expired',
        cancelled: () => '$userId: Cancelled',
        lockedOut: (until) => '$userId: Locked out',
        unavailable: (r, msg) => '$userId: Unavailable (${r.name})',
        invalidated: () => '$userId: Invalidated',
        reauthenticationRequired: (r) => '$userId: Re-auth required',
        error: (msg, _) => '$userId: Error: $msg',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }

    await _loadAllStates();
    setState(() => _isLoading = false);
  }

  Future<void> _clearUser(String userId) async {
    await shield.clearAll(userId: userId);
    await _loadAllStates();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cleared all data for $userId')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Multi-User Demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How it works',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'All storage is namespaced by userId. Alice\'s token, '
                    'session, lockout state, and preferences are completely '
                    'isolated from Bob\'s — even on the same device.\n\n'
                    'Store a token for each user, then authenticate them '
                    'independently.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ..._users.map((user) => _buildUserCard(user)),
        ],
      ),
    );
  }

  Widget _buildUserCard(String userId) {
    final state = _states[userId] ?? _UserState();
    final shortName = userId.split('@').first;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(shortName[0].toUpperCase()),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shortName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        userId,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _statusRow('Session', state.hasSession ? 'Active' : 'None'),
            _statusRow('Token', state.token != null ? 'Stored' : 'Empty'),
            _statusRow(
              'Lockout',
              state.lockout?.isLockedOut == true
                  ? 'LOCKED (${state.lockout!.remainingLockout?.inSeconds}s)'
                  : 'OK (${state.lockout?.currentAttemptCount ?? 0}/${state.lockout?.maxAttempts ?? 3} attempts)',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => _storeTokenForUser(userId),
                    child: const Text('Store Token'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _isLoading ? null : () => _authenticateUser(userId),
                    child: const Text('Authenticate'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isLoading ? null : () => _clearUser(userId),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Clear all data',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value),
        ],
      ),
    );
  }
}

class _UserState {
  final bool hasSession;
  final String? token;
  final LockoutState? lockout;

  _UserState({
    this.hasSession = false,
    this.token,
    this.lockout,
  });
}
