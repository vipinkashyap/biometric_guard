
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:biometric_shield/biometric_shield.dart';
import 'package:biometric_shield/biometric_shield_ui.dart';
import 'package:biometric_shield/biometric_shield_testing.dart';

void main() {
  group('BiometricBuilder', () {
    testWidgets('shows authenticating state initially when autoAuthenticate is true',
        (tester) async {
      final mock = BiometricShieldMock(
        authenticateResult: FakeBiometricResult.success(token: 'test-jwt'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BiometricBuilder(
            shield: mock,
            reason: 'Test auth',
            autoAuthenticate: true,
            builder: (context, state) => switch (state) {
              AuthIdle() => const Text('idle'),
              AuthAuthenticating() => const Text('authenticating'),
              AuthAuthenticated() => const Text('authenticated'),
              AuthFailed() => const Text('failed'),
            },
          ),
        ),
      );

      // Initially should show authenticating (auto-auth fires in initState)
      expect(find.text('authenticating'), findsOneWidget);
    });

    testWidgets('shows authenticated state after successful auth',
        (tester) async {
      final session = FakeBiometricSession.active();
      final mock = BiometricShieldMock(
        authenticateResult: BiometricResult.success(
          session: session,
          token: 'test-jwt',
        ),
        // Also set tokenResult so the sessionStream listener and
        // authenticate() agree on the token value, avoiding a race
        // where the stream listener calls getToken() and gets null.
        tokenResult: 'test-jwt',
        sessionStreamResult: session,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BiometricBuilder(
            shield: mock,
            reason: 'Test auth',
            autoAuthenticate: true,
            builder: (context, state) => switch (state) {
              AuthIdle() => const Text('idle'),
              AuthAuthenticating() => const Text('authenticating'),
              AuthAuthenticated(:final token) =>
                Text('authenticated:${token ?? "null"}'),
              AuthFailed() => const Text('failed'),
            },
          ),
        ),
      );

      // Let the async authenticate() call complete
      await tester.pumpAndSettle();

      expect(find.text('authenticated:test-jwt'), findsOneWidget);
      expect(mock.authenticateCalls, hasLength(1));
      expect(mock.authenticateCalls.first.reason, 'Test auth');
    });

    testWidgets('shows failed state when auth is cancelled', (tester) async {
      final mock = BiometricShieldMock(
        authenticateResult: const BiometricResult.cancelled(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BiometricBuilder(
            shield: mock,
            reason: 'Test auth',
            autoAuthenticate: true,
            builder: (context, state) => switch (state) {
              AuthIdle() => const Text('idle'),
              AuthAuthenticating() => const Text('authenticating'),
              AuthAuthenticated() => const Text('authenticated'),
              AuthFailed(:final result) =>
                Text('failed:${result is BiometricCancelled ? "cancelled" : "other"}'),
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('failed:cancelled'), findsOneWidget);
    });

    testWidgets('shows failed state when locked out', (tester) async {
      final lockedUntil = DateTime.now().add(const Duration(minutes: 5));
      final mock = BiometricShieldMock(
        authenticateResult: BiometricResult.lockedOut(
          lockedUntil: lockedUntil,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BiometricBuilder(
            shield: mock,
            reason: 'Test auth',
            autoAuthenticate: true,
            builder: (context, state) => switch (state) {
              AuthIdle() => const Text('idle'),
              AuthAuthenticating() => const Text('authenticating'),
              AuthAuthenticated() => const Text('authenticated'),
              AuthFailed(:final result) =>
                Text('failed:${result is BiometricLockedOut ? "lockedOut" : "other"}'),
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('failed:lockedOut'), findsOneWidget);
    });

    testWidgets('shows idle when autoAuthenticate is false', (tester) async {
      final mock = BiometricShieldMock(
        authenticateResult: FakeBiometricResult.success(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BiometricBuilder(
            shield: mock,
            reason: 'Test auth',
            autoAuthenticate: false,
            builder: (context, state) => switch (state) {
              AuthIdle() => const Text('idle'),
              AuthAuthenticating() => const Text('authenticating'),
              AuthAuthenticated() => const Text('authenticated'),
              AuthFailed() => const Text('failed'),
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should stay idle — no auto-auth
      expect(find.text('idle'), findsOneWidget);
      expect(mock.authenticateCalls, isEmpty);
    });

    testWidgets('passes userId to authenticate', (tester) async {
      final session = FakeBiometricSession.active(userId: 'user-42');
      final mock = BiometricShieldMock(
        authenticateResult: BiometricResult.success(
          session: session,
          token: 'jwt-42',
        ),
        tokenResult: 'jwt-42',
        sessionStreamResult: session,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BiometricBuilder(
            shield: mock,
            reason: 'Confirm identity',
            userId: 'user-42',
            autoAuthenticate: true,
            builder: (context, state) => switch (state) {
              AuthIdle() => const Text('idle'),
              AuthAuthenticating() => const Text('authenticating'),
              AuthAuthenticated() => const Text('authenticated'),
              AuthFailed() => const Text('failed'),
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(mock.authenticateCalls.first.userId, 'user-42');
    });

    testWidgets('handles fallbackSuccess as authenticated', (tester) async {
      final session = FakeBiometricSession.deviceCredential();
      final mock = BiometricShieldMock(
        authenticateResult: BiometricResult.fallbackSuccess(
          methodUsed: BiometricFallback.deviceCredential,
          session: session,
          token: 'fallback-jwt',
        ),
        tokenResult: 'fallback-jwt',
        sessionStreamResult: session,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BiometricBuilder(
            shield: mock,
            reason: 'Test fallback',
            autoAuthenticate: true,
            builder: (context, state) => switch (state) {
              AuthIdle() => const Text('idle'),
              AuthAuthenticating() => const Text('authenticating'),
              AuthAuthenticated(:final token) =>
                Text('authenticated:${token ?? "null"}'),
              AuthFailed() => const Text('failed'),
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('authenticated:fallback-jwt'), findsOneWidget);
    });

    testWidgets('handles error result as failed', (tester) async {
      final mock = BiometricShieldMock(
        authenticateResult: const BiometricResult.error(
          message: 'Platform error',
          cause: null,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BiometricBuilder(
            shield: mock,
            reason: 'Test error',
            autoAuthenticate: true,
            builder: (context, state) => switch (state) {
              AuthIdle() => const Text('idle'),
              AuthAuthenticating() => const Text('authenticating'),
              AuthAuthenticated() => const Text('authenticated'),
              AuthFailed(:final result) =>
                Text('failed:${result is BiometricError ? (result).message : "other"}'),
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('failed:Platform error'), findsOneWidget);
    });
  });

  group('BiometricGate', () {
    testWidgets('shows loading initially then child after success',
        (tester) async {
      final session = FakeBiometricSession.active();
      final mock = BiometricShieldMock(
        authenticateResult: BiometricResult.success(
          session: session,
          token: 'gate-jwt',
        ),
        tokenResult: 'gate-jwt',
        sessionStreamResult: session,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BiometricGate(
            shield: mock,
            reason: 'Confirm access',
            child: const Text('Secret Content'),
          ),
        ),
      );

      // Initially shows loading (CircularProgressIndicator is default)
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Secret Content'), findsNothing);

      // After auth completes
      await tester.pumpAndSettle();

      expect(find.text('Secret Content'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows custom loading widget when provided', (tester) async {
      final mock = BiometricShieldMock(
        authenticateResult: FakeBiometricResult.success(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BiometricGate(
            shield: mock,
            reason: 'Test loading',
            loadingWidget: const Text('Custom Loading...'),
            child: const Text('Content'),
          ),
        ),
      );

      expect(find.text('Custom Loading...'), findsOneWidget);
    });

    testWidgets('shows fallback widget when auth fails', (tester) async {
      final mock = BiometricShieldMock(
        authenticateResult: const BiometricResult.cancelled(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BiometricGate(
            shield: mock,
            reason: 'Test fallback',
            child: const Text('Secret Content'),
            fallbackWidget: (result) => const Text('Access Denied'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsOneWidget);
      expect(find.text('Secret Content'), findsNothing);
    });

    testWidgets('shows default fallback text when no fallbackWidget provided',
        (tester) async {
      final mock = BiometricShieldMock(
        authenticateResult: const BiometricResult.cancelled(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BiometricGate(
            shield: mock,
            reason: 'Test default fallback',
            child: const Text('Secret Content'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Authentication required'), findsOneWidget);
    });

    testWidgets('calls onAuthenticated callback on success', (tester) async {
      BiometricResult? callbackResult;
      final session = FakeBiometricSession.active();
      final mock = BiometricShieldMock(
        authenticateResult: BiometricResult.success(
          session: session,
          token: 'callback-jwt',
        ),
        tokenResult: 'callback-jwt',
        sessionStreamResult: session,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BiometricGate(
            shield: mock,
            reason: 'Test callback',
            onAuthenticated: (result) => callbackResult = result,
            child: const Text('Content'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(callbackResult, isNotNull);
      expect(callbackResult, isA<BiometricSuccess>());
    });

    testWidgets('passes userId through to shield', (tester) async {
      final session = FakeBiometricSession.active(userId: 'gate-user');
      final mock = BiometricShieldMock(
        authenticateResult: BiometricResult.success(
          session: session,
          token: 'jwt',
        ),
        tokenResult: 'jwt',
        sessionStreamResult: session,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BiometricGate(
            shield: mock,
            reason: 'Test userId',
            userId: 'gate-user',
            child: const Text('Content'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(mock.authenticateCalls.first.userId, 'gate-user');
    });

    testWidgets('shows child after fallback success', (tester) async {
      final session = FakeBiometricSession.deviceCredential();
      final mock = BiometricShieldMock(
        authenticateResult: BiometricResult.fallbackSuccess(
          methodUsed: BiometricFallback.deviceCredential,
          session: session,
          token: 'fallback-jwt',
        ),
        tokenResult: 'fallback-jwt',
        sessionStreamResult: session,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BiometricGate(
            shield: mock,
            reason: 'Test fallback success',
            child: const Text('Protected Content'),
            fallbackWidget: (result) => const Text('Denied'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Protected Content'), findsOneWidget);
      expect(find.text('Denied'), findsNothing);
    });

    testWidgets('shows fallback for unavailable biometric', (tester) async {
      final mock = BiometricShieldMock(
        authenticateResult: const BiometricResult.unavailable(
          reason: BiometricUnavailableReason.notEnrolled,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BiometricGate(
            shield: mock,
            reason: 'Test unavailable',
            child: const Text('Content'),
            fallbackWidget: (result) {
              final unavailable = result as BiometricUnavailable;
              return Text('Unavailable: ${unavailable.reason.name}');
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Unavailable: notEnrolled'), findsOneWidget);
    });

    testWidgets('shows fallback for lockout with details', (tester) async {
      final lockedUntil = DateTime.now().add(const Duration(minutes: 5));
      final mock = BiometricShieldMock(
        authenticateResult: BiometricResult.lockedOut(
          lockedUntil: lockedUntil,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BiometricGate(
            shield: mock,
            reason: 'Test lockout',
            child: const Text('Content'),
            fallbackWidget: (result) {
              return const Text('Locked Out');
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Locked Out'), findsOneWidget);
      expect(find.text('Content'), findsNothing);
    });
  });

  group('AuthState', () {
    test('AuthIdle is correct type', () {
      const state = AuthIdle();
      expect(state, isA<AuthState>());
    });

    test('AuthAuthenticating is correct type', () {
      const state = AuthAuthenticating();
      expect(state, isA<AuthState>());
    });

    test('AuthAuthenticated exposes session and token', () {
      final session = FakeBiometricSession.active();
      final state = AuthAuthenticated(session: session, token: 'jwt-123');
      expect(state.session, session);
      expect(state.token, 'jwt-123');
    });

    test('AuthFailed exposes result', () {
      const result = BiometricResult.cancelled();
      const state = AuthFailed(result: result);
      expect(state.result, isA<BiometricCancelled>());
    });
  });
}
