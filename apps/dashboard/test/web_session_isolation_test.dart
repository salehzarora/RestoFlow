// WEB-AUTH-SESSION-ISOLATION-001 — the Dashboard must not be signed out, or
// silently re-identified, by a POS/KDS tab on the same origin.
//
// THE DEFECT. RestoFlow serves Dashboard, POS and KDS from ONE origin
// (`/`, `/pos/`, `/kds/`). GoTrue opens a BroadcastChannel named
// `sb-<project-ref>-auth-token` in its client constructor, unconditionally on
// web, named from the project URL — no public option renames or disables it. A
// client that RECEIVES on that channel adopts the broadcast session as its own.
// So a POS/KDS anonymous device sign-in became the Dashboard's session,
// `supabase_flutter` persisted it, and after a reload the Dashboard ran as an
// anonymous principal: every tenant RPC 403'd and the operator was stuck on a
// generic error until they cleared site data.
//
// Measured on production before the fix: Dashboard alone left storage empty;
// opening /pos/ wrote an `is_anonymous: true` session into the shared key;
// opening /kds/ then overwrote it with a DIFFERENT anonymous user.
//
// WHAT THESE TESTS PIN. Not token contents — never that. They pin the two
// decisions that make the surfaces coexist: an anonymous principal is never a
// Dashboard identity, and another tab's device event is not a Dashboard event.
// Plus the legacy-key classification, which is what lets an already-poisoned
// browser recover without the operator clearing site data.
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/auth/web_session_isolation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A session shaped like the real thing. `is_anonymous` is the only field under
/// test; the token strings are inert placeholders and are never asserted on.
Session _session({required bool anonymous, String userId = 'user-1'}) {
  return Session(
    accessToken: 'placeholder-access',
    tokenType: 'bearer',
    user: User(
      id: userId,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: DateTime.utc(2026).toIso8601String(),
      isAnonymous: anonymous,
    ),
    refreshToken: 'placeholder-refresh',
  );
}

/// An in-memory [LocalStorage] so the migration is exercised without a browser.
class _MemoryStorage extends LocalStorage {
  _MemoryStorage(this.key, this.backing);

  final String key;
  final Map<String, String> backing;
  int removeCalls = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() async => backing[key];

  @override
  Future<bool> hasAccessToken() async => backing.containsKey(key);

  @override
  Future<void> persistSession(String persistSessionString) async {
    backing[key] = persistSessionString;
  }

  @override
  Future<void> removePersistedSession() async {
    removeCalls++;
    backing.remove(key);
  }
}

String _storedSession({required bool anonymous, String refresh = 'r-1'}) =>
    '{"access_token":"a","refresh_token":"$refresh",'
    '"user":{"id":"u","is_anonymous":$anonymous}}';

void main() {
  group('A. each web app owns a distinct auth namespace', () {
    test('the Dashboard key is not the shared SDK default', () {
      const url = 'https://examplerefonly.supabase.co';
      expect(kDashboardPersistSessionKey, 'restoflow-dashboard-auth');
      expect(
        kDashboardPersistSessionKey,
        isNot(legacySharedSessionKey(url)),
        reason:
            'The Dashboard must not persist into the slot every surface on the '
            'origin shares.',
      );
    });

    test('the legacy key is derived from config, never hardcoded', () {
      expect(
        legacySharedSessionKey('https://abcdefghijkl.supabase.co'),
        'sb-abcdefghijkl-auth-token',
        reason: 'It must match how the SDK derives it, or nothing is cleaned.',
      );
      // A different project yields a different key: no project ref is baked in.
      expect(
        legacySharedSessionKey('https://zzzzzzzzzzzz.supabase.co'),
        'sb-zzzzzzzzzzzz-auth-token',
      );
      expect(legacySharedSessionKey('not a url'), 'sb--auth-token');
    });
  });

  group('B/E/F. a device principal is never a Dashboard identity', () {
    test('an anonymous session is refused', () {
      expect(isUsableDashboardSession(_session(anonymous: true)), isFalse);
    });

    test('a staff session is accepted', () {
      expect(isUsableDashboardSession(_session(anonymous: false)), isTrue);
    });

    test('no session is refused', () {
      expect(isUsableDashboardSession(null), isFalse);
    });

    test('POS and KDS anonymous users are refused alike', () {
      // The two surfaces produce DIFFERENT anonymous users — production showed
      // KDS overwriting POS's. Neither may unlock the Dashboard.
      for (final id in ['pos-anon-user', 'kds-anon-user']) {
        expect(
          isUsableDashboardSession(_session(anonymous: true, userId: id)),
          isFalse,
          reason: '$id must not read as a signed-in Dashboard.',
        );
      }
    });
  });

  group('C/D/L. only the Dashboard\'s own auth events are acted on', () {
    AuthState broadcast(Session? session) =>
        AuthState(AuthChangeEvent.signedIn, session, fromBroadcast: true);
    AuthState own(Session? session) =>
        AuthState(AuthChangeEvent.signedIn, session);

    test('a POS/KDS device sign-in broadcast is ignored', () {
      expect(
        isOwnDashboardAuthEvent(broadcast(_session(anonymous: true))),
        isFalse,
      );
    });

    test('a broadcast SIGNED_OUT carrying no session is ignored', () {
      // Another surface signing out must not sign the Dashboard out.
      expect(
        isOwnDashboardAuthEvent(
          AuthState(AuthChangeEvent.signedOut, null, fromBroadcast: true),
        ),
        isFalse,
      );
    });

    test('another DASHBOARD tab\'s staff event is still honoured', () {
      // Dashboard-to-Dashboard tab sync must survive the fix.
      expect(
        isOwnDashboardAuthEvent(broadcast(_session(anonymous: false))),
        isTrue,
      );
    });

    test('this tab\'s own events always pass, signed in or out', () {
      expect(isOwnDashboardAuthEvent(own(_session(anonymous: false))), isTrue);
      expect(isOwnDashboardAuthEvent(own(null)), isTrue);
    });
  });

  group('J. legacy shared-key classification', () {
    test('an anonymous legacy session is discarded, never migrated', () {
      expect(
        classifyLegacySession({
          'refresh_token': 'r',
          'user': {'is_anonymous': true},
        }),
        LegacySessionAction.discard,
      );
    });

    test('a staff legacy session migrates', () {
      expect(
        classifyLegacySession({
          'refresh_token': 'r',
          'user': {'is_anonymous': false},
        }),
        LegacySessionAction.migrate,
      );
    });

    test('ambiguous or unreadable legacy state fails safe', () {
      // Missing flag, missing user, missing refresh token, empty, null: all
      // resolve to the sign-in screen rather than a half-authorised shell.
      expect(classifyLegacySession(null), LegacySessionAction.none);
      expect(classifyLegacySession({}), LegacySessionAction.none);
      expect(
        classifyLegacySession({'refresh_token': 'r', 'user': {}}),
        LegacySessionAction.discard,
      );
      expect(
        classifyLegacySession({'user': 'nonsense'}),
        LegacySessionAction.discard,
      );
      expect(
        classifyLegacySession({
          'user': {'is_anonymous': false},
        }),
        LegacySessionAction.discard,
      );
    });
  });

  group('J/M. migration recovers a poisoned browser without clearing data', () {
    const url = 'https://examplerefonly.supabase.co';
    final legacyKey = legacySharedSessionKey(url);

    Future<Map<String, String>> run(Map<String, String> initial) async {
      final backing = Map<String, String>.from(initial);
      await migrateLegacySharedSession(
        supabaseUrl: url,
        storageFactory: (key) => _MemoryStorage(key, backing),
      );
      return backing;
    }

    test('a poisoned anonymous session is dropped, not adopted', () async {
      final after = await run({legacyKey: _storedSession(anonymous: true)});
      expect(
        after.containsKey(kDashboardPersistSessionKey),
        isFalse,
        reason: 'A device session must never become the Dashboard session.',
      );
      expect(
        after.containsKey(legacyKey),
        isFalse,
        reason:
            'The poisoned slot must be cleared, or the browser re-poisons '
            'itself on the next load and the operator is stuck again.',
      );
    });

    test(
      'a real staff session is carried over so the operator stays in',
      () async {
        final stored = _storedSession(anonymous: false);
        final after = await run({legacyKey: stored});
        expect(after[kDashboardPersistSessionKey], stored);
        expect(after.containsKey(legacyKey), isFalse);
      },
    );

    test('an existing namespaced session is never clobbered', () async {
      final after = await run({
        legacyKey: _storedSession(anonymous: false, refresh: 'legacy'),
        kDashboardPersistSessionKey: _storedSession(
          anonymous: false,
          refresh: 'current',
        ),
      });
      expect(
        after[kDashboardPersistSessionKey],
        contains('current'),
        reason: 'The namespaced slot is the fresher truth.',
      );
    });

    test('an empty browser is left untouched', () async {
      final after = await run({});
      expect(after, isEmpty);
    });

    test('unparseable legacy JSON is dropped without throwing', () async {
      final after = await run({legacyKey: 'not json at all'});
      expect(after.containsKey(kDashboardPersistSessionKey), isFalse);
      expect(after.containsKey(legacyKey), isFalse);
    });
  });

  group('K. migration cannot loop', () {
    test('a second run is a no-op because the legacy slot is gone', () async {
      const url = 'https://examplerefonly.supabase.co';
      final backing = <String, String>{
        legacySharedSessionKey(url): _storedSession(anonymous: true),
      };
      final stores = <String, _MemoryStorage>{};
      _MemoryStorage factory(String key) =>
          stores.putIfAbsent(key, () => _MemoryStorage(key, backing));

      await migrateLegacySharedSession(
        supabaseUrl: url,
        storageFactory: factory,
      );
      final removalsAfterFirst =
          stores[legacySharedSessionKey(url)]!.removeCalls;

      await migrateLegacySharedSession(
        supabaseUrl: url,
        storageFactory: factory,
      );
      expect(
        stores[legacySharedSessionKey(url)]!.removeCalls,
        removalsAfterFirst,
        reason:
            'The second boot must not touch storage again — a repeated '
            'clear-and-reload is exactly the refresh loop this must not create.',
      );
    });
  });
}
