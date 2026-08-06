import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:test/test.dart';

/// RF-063: the pure error-code classifier (no Supabase SDK needed at test time).
///
/// [POS-OFFLINE-OPERATIONS-002 Pass B] UPDATED CONTRACT — '42501 -> auth' is
/// now CONDITIONAL on the exception message. `app.sync_push` (and friends)
/// raise 42501 for session refusals AND for batch-shape validation, permission
/// denials and RLS refusals; only the session-class subset is fixed by a fresh
/// sign-in, and the POS outbox parks kind-`auth` batch failures behind the
/// AUTH_HOLD state that ONLY a fresh ONLINE sign-in releases. Everything
/// non-session must therefore land `server` (retryable-visible), never `auth`
/// (a hold a re-auth replays or cannot even run). Source of truth for the
/// session-class messages:
/// supabase/migrations/20260803090000_kitchen_dispatch_enforce_001_server_guard.sql
void main() {
  group('classifyPostgrestCode', () {
    test('42501 with a SESSION-CLASS message -> auth (reauth signal)', () {
      // The four batch-level session refusals app.sync_push raises from its
      // preamble — each is genuinely re-authenticatable.
      const sessionMessages = [
        'sync_push: PIN session not found',
        'sync_push: PIN session is not valid (inactive/ended/expired)',
        'sync_push: backing device session not found',
        'sync_push: device_id does not match the PIN session device',
      ];
      for (final message in sessionMessages) {
        expect(
          classifyPostgrestCode('42501', message: message),
          SyncTransportErrorKind.auth,
          reason: message,
        );
      }
      // Case-insensitive contains: the function prefix and casing never
      // defeat the match (sync_pull/pos_menu raise the same session class).
      expect(
        classifyPostgrestCode(
          '42501',
          message: 'sync_pull: pin SESSION NOT found',
        ),
        SyncTransportErrorKind.auth,
      );
    });

    test('42501 with a batch-shape message -> server (a re-auth replays the '
        'identical refusal)', () {
      expect(
        classifyPostgrestCode(
          '42501',
          message: 'sync_push: p_operations must be a JSON array',
        ),
        SyncTransportErrorKind.server,
      );
      expect(
        classifyPostgrestCode(
          '42501',
          message: 'sync_push: batch too large (max 100 operations, got 250)',
        ),
        SyncTransportErrorKind.server,
      );
    });

    test('42501 PostgREST function ACL denial -> server (the hold could NEVER '
        'be released in-app: PIN sign-in dies on the same dead transport)', () {
      expect(
        classifyPostgrestCode(
          '42501',
          message: 'permission denied for function sync_push',
        ),
        SyncTransportErrorKind.server,
      );
    });

    test('42501 RLS refusal -> server', () {
      expect(
        classifyPostgrestCode(
          '42501',
          message:
              'new row violates row-level security policy for table "orders"',
        ),
        SyncTransportErrorKind.server,
      );
    });

    test('42501 with an unknown or missing message -> server (an unknown '
        'future session-class message degrades to retryable-visible, never a '
        'stuck hold)', () {
      expect(
        classifyPostgrestCode('42501', message: 'something new and unmapped'),
        SyncTransportErrorKind.server,
      );
      expect(classifyPostgrestCode('42501'), SyncTransportErrorKind.server);
      expect(
        classifyPostgrestCode('42501', message: ''),
        SyncTransportErrorKind.server,
      );
    });

    test('throttling/5xx codes -> transient', () {
      expect(classifyPostgrestCode('429'), SyncTransportErrorKind.transient);
      expect(classifyPostgrestCode('503'), SyncTransportErrorKind.transient);
      expect(classifyPostgrestCode('504'), SyncTransportErrorKind.transient);
    });

    test('PostgREST auth-adjacent HTTP codes stay server (pinned — they are '
        'not the session-class reauth signal)', () {
      expect(classifyPostgrestCode('PGRST301'), SyncTransportErrorKind.server);
      expect(classifyPostgrestCode('401'), SyncTransportErrorKind.server);
      expect(classifyPostgrestCode('403'), SyncTransportErrorKind.server);
    });

    test('null and other codes -> server', () {
      expect(classifyPostgrestCode(null), SyncTransportErrorKind.server);
      expect(classifyPostgrestCode('22000'), SyncTransportErrorKind.server);
      expect(classifyPostgrestCode('PGRST116'), SyncTransportErrorKind.server);
      // A session-class message under a NON-42501 code is not an auth signal.
      expect(
        classifyPostgrestCode('22000', message: 'PIN session not found'),
        SyncTransportErrorKind.server,
      );
    });
  });
}
