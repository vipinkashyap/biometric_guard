import 'package:flutter_test/flutter_test.dart';
import 'package:biometric_shield/biometric_shield.dart';
import 'package:biometric_shield/biometric_shield_testing.dart';
import 'package:biometric_shield/src/session/session_manager.dart';

void main() {
  late FakeTokenStore store;
  late SessionManager sessionManager;

  setUp(() {
    store = FakeTokenStore();
    sessionManager = SessionManager(
      config: BiometricTestConfig.create(),
      store: store,
    );
  });

  tearDown(() {
    sessionManager.dispose();
  });

  group('SessionManager', () {
    group('createSession', () {
      test('creates an active session with correct method', () async {
        final session = await sessionManager.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-1',
        );

        expect(session.userId, 'user-1');
        expect(session.methodUsed, BiometricAuthMethod.fingerprint);
        expect(session.isActive, isTrue);
        expect(session.isExpired, isFalse);
        expect(session.sessionId, isNotEmpty);
      });

      test('session expires after configured duration', () async {
        final shortConfig = BiometricTestConfig.create(
          sessionDuration: Duration.zero,
        );
        final mgr = SessionManager(config: shortConfig, store: store);

        final session = await mgr.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-1',
        );

        // With Duration.zero, session should be expired immediately
        expect(session.isExpired, isTrue);
        mgr.dispose();
      });

      test('persists session to store', () async {
        await sessionManager.createSession(
          method: BiometricAuthMethod.faceID,
          userId: 'user-1',
        );

        expect(await store.containsKey('session:user-1'), isTrue);
      });

      test('generates unique session IDs', () async {
        final s1 = await sessionManager.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-1',
        );
        final s2 = await sessionManager.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-1',
        );

        expect(s1.sessionId, isNot(equals(s2.sessionId)));
      });
    });

    group('hasValidSession', () {
      test('returns false when no session exists', () async {
        final isValid = await sessionManager.hasValidSession(userId: 'user-1');
        expect(isValid, isFalse);
      });

      test('returns true for active session', () async {
        await sessionManager.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-1',
        );

        final isValid = await sessionManager.hasValidSession(userId: 'user-1');
        expect(isValid, isTrue);
      });

      test('sessions are isolated by userId', () async {
        await sessionManager.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-1',
        );

        expect(
          await sessionManager.hasValidSession(userId: 'user-1'),
          isTrue,
        );
        expect(
          await sessionManager.hasValidSession(userId: 'user-2'),
          isFalse,
        );
      });
    });

    group('getActiveSession', () {
      test('returns null when no session exists', () async {
        final session =
            await sessionManager.getActiveSession(userId: 'user-1');
        expect(session, isNull);
      });

      test('returns session when active', () async {
        await sessionManager.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-1',
        );

        final session =
            await sessionManager.getActiveSession(userId: 'user-1');
        expect(session, isNotNull);
        expect(session!.userId, 'user-1');
      });
    });

    group('clearSession', () {
      test('removes active session', () async {
        await sessionManager.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-1',
        );

        await sessionManager.clearSession(userId: 'user-1');

        final isValid = await sessionManager.hasValidSession(userId: 'user-1');
        expect(isValid, isFalse);
      });

      test('clear one user does not affect another', () async {
        await sessionManager.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-1',
        );
        await sessionManager.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-2',
        );

        await sessionManager.clearSession(userId: 'user-1');

        expect(
          await sessionManager.hasValidSession(userId: 'user-1'),
          isFalse,
        );
        expect(
          await sessionManager.hasValidSession(userId: 'user-2'),
          isTrue,
        );
      });
    });

    group('token management', () {
      test('store and retrieve token', () async {
        await sessionManager.storeToken('jwt-abc', userId: 'user-1');
        final token = await sessionManager.getToken(userId: 'user-1');
        expect(token, 'jwt-abc');
      });

      test('tokens are namespaced by userId', () async {
        await sessionManager.storeToken('token-1', userId: 'user-1');
        await sessionManager.storeToken('token-2', userId: 'user-2');

        expect(await sessionManager.getToken(userId: 'user-1'), 'token-1');
        expect(await sessionManager.getToken(userId: 'user-2'), 'token-2');
      });

      test('getToken returns null when no token stored', () async {
        final token = await sessionManager.getToken(userId: 'user-1');
        expect(token, isNull);
      });
    });

    group('clearAll', () {
      test('clears session and token', () async {
        await sessionManager.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-1',
        );
        await sessionManager.storeToken('jwt-abc', userId: 'user-1');

        await sessionManager.clearAll(userId: 'user-1');

        expect(
          await sessionManager.hasValidSession(userId: 'user-1'),
          isFalse,
        );
        expect(await sessionManager.getToken(userId: 'user-1'), isNull);
      });
    });

    group('sessionStream', () {
      test('emits current session immediately', () async {
        await sessionManager.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-1',
        );

        final stream = sessionManager.sessionStream(userId: 'user-1');
        final first = await stream.first;

        expect(first, isNotNull);
        expect(first!.userId, 'user-1');
      });

      test('emits null when no session', () async {
        final stream = sessionManager.sessionStream(userId: 'user-1');
        final first = await stream.first;

        expect(first, isNull);
      });

      test('emits null after clearSession', () async {
        await sessionManager.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-1',
        );

        final emissions = <BiometricSession?>[];
        sessionManager.sessionStream(userId: 'user-1').listen(emissions.add);

        // Wait a tick for the initial emission
        await Future<void>.delayed(Duration.zero);

        await sessionManager.clearSession(userId: 'user-1');

        await Future<void>.delayed(Duration.zero);

        // Should have initial session + null after clear
        expect(emissions.length, greaterThanOrEqualTo(2));
        expect(emissions.last, isNull);
      });
    });

    group('event emission', () {
      test('emits sessionStarted on create', () async {
        final events = <BiometricEvent>[];
        final config = BiometricConfig(
          tokenStore: store,
          persistLockout: false,
          sessionResetsOnActivity: false,
          onEvent: events.add,
        );
        final mgr = SessionManager(config: config, store: store);

        await mgr.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-1',
        );

        expect(events, hasLength(1));
        expect(events.first.type, BiometricEventType.sessionStarted);
        expect(events.first.userId, 'user-1');
        expect(events.first.method, BiometricAuthMethod.fingerprint);
        mgr.dispose();
      });

      test('emits sessionCleared on clear', () async {
        final events = <BiometricEvent>[];
        final config = BiometricConfig(
          tokenStore: store,
          persistLockout: false,
          sessionResetsOnActivity: false,
          onEvent: events.add,
        );
        final mgr = SessionManager(config: config, store: store);

        await mgr.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-1',
        );
        events.clear();

        await mgr.clearSession(userId: 'user-1');

        expect(events, hasLength(1));
        expect(events.first.type, BiometricEventType.sessionCleared);
        mgr.dispose();
      });
    });
  });
}
