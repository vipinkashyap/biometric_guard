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

        expect(await sessionManager.hasValidSession(userId: 'user-1'), isTrue);
        expect(await sessionManager.hasValidSession(userId: 'user-2'), isFalse);
      });
    });

    group('getActiveSession', () {
      test('returns null when no session exists', () async {
        final session = await sessionManager.getActiveSession(userId: 'user-1');
        expect(session, isNull);
      });

      test('returns session when active', () async {
        await sessionManager.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-1',
        );

        final session = await sessionManager.getActiveSession(userId: 'user-1');
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

        expect(await sessionManager.hasValidSession(userId: 'user-1'), isFalse);
        expect(await sessionManager.hasValidSession(userId: 'user-2'), isTrue);
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

        expect(await sessionManager.hasValidSession(userId: 'user-1'), isFalse);
        expect(await sessionManager.getToken(userId: 'user-1'), isNull);
      });

      test(
        'clears persisted lockout data with lockout:userId key format',
        () async {
          await store.store('lockout:user-1', '{"attemptCount":2}');

          await sessionManager.clearAll(userId: 'user-1');

          expect(await store.containsKey('lockout:user-1'), isFalse);
        },
      );
    });

    group('sessionStream', () {
      test('emits session on create after subscribing', () async {
        // Subscribe FIRST, then create session — broadcast streams
        // drop events when no listeners are attached.
        final emissions = <BiometricSession?>[];
        sessionManager.sessionStream(userId: 'user-1').listen(emissions.add);

        // The initial emission (null, no session yet) fires synchronously
        // inside sessionStream(), but broadcast streams only deliver to
        // listeners already attached. Since .listen() returns after the
        // synchronous add(), we may or may not catch it. So create a
        // session which will reliably emit to our listener.
        await sessionManager.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-1',
        );

        await Future<void>.delayed(Duration.zero);

        // Should have at least the session from createSession
        expect(emissions.any((s) => s != null && s.userId == 'user-1'), isTrue);
      });

      test('emits null after clearSession', () async {
        // Subscribe first
        final emissions = <BiometricSession?>[];
        sessionManager.sessionStream(userId: 'user-1').listen(emissions.add);

        // Create and then clear
        await sessionManager.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-1',
        );
        await Future<void>.delayed(Duration.zero);

        await sessionManager.clearSession(userId: 'user-1');
        await Future<void>.delayed(Duration.zero);

        // The last emission should be null (session cleared)
        expect(emissions, isNotEmpty);
        expect(emissions.last, isNull);
      });

      test('different users get independent streams', () async {
        final emissions1 = <BiometricSession?>[];
        final emissions2 = <BiometricSession?>[];
        sessionManager.sessionStream(userId: 'user-1').listen(emissions1.add);
        sessionManager.sessionStream(userId: 'user-2').listen(emissions2.add);

        await sessionManager.createSession(
          method: BiometricAuthMethod.fingerprint,
          userId: 'user-1',
        );
        await Future<void>.delayed(Duration.zero);

        // user-1 stream got the session, user-2 did not
        expect(emissions1.any((s) => s != null), isTrue);
        expect(emissions2.every((s) => s == null), isTrue);
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
