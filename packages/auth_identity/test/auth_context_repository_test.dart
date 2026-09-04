import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:test/test.dart';

import 'fake_rpc_transport.dart';

Map<String, dynamic> validContext({
  bool isPlatformAdmin = false,
  List<Map<String, dynamic>>? memberships,
}) => {
  'ok': true,
  'app_user': {
    'id': 'u-1',
    'email': 'u@example.test',
    'display_name': 'U',
    'is_active': true,
  },
  'is_platform_admin': isPlatformAdmin,
  'memberships':
      memberships ??
      [
        {
          'id': 'm-a',
          'organization_id': 'org-a',
          'organization_name': 'Org A',
          'restaurant_id': null,
          'restaurant_name': null,
          'branch_id': null,
          'branch_name': null,
          'role': 'manager',
          'status': 'active',
        },
      ],
};

void main() {
  group('AuthContextRepository.fetchMyContext', () {
    test(
      'success parses the context and sends NO user id (identity is server-side)',
      () async {
        final transport = FakeRpcTransport(value: validContext());
        final repo = AuthContextRepository(transport);

        final result = await repo.fetchMyContext();

        expect(result.isSuccess, isTrue);
        final ctx = (result as Success<MyContext, AuthFailure>).value;
        expect(ctx.appUser.id, 'u-1');
        expect(ctx.memberships.single.role, MembershipRole.manager);
        // get_my_context takes NO arguments - identity comes from auth.uid().
        expect(transport.lastFunction, 'get_my_context');
        expect(transport.lastParams, isEmpty);
      },
    );

    test('42501 maps to AuthDeniedFailure', () async {
      final transport = FakeRpcTransport(
        error: const SyncTransportException(
          SyncTransportErrorKind.auth,
          code: '42501',
        ),
      );
      final result = await AuthContextRepository(transport).fetchMyContext();
      expect(
        (result as Failure<MyContext, AuthFailure>).failure,
        isA<AuthDeniedFailure>(),
      );
    });

    test(
      'AUTH-257: a 42501 the SHARED classifier calls `server` is still a denial',
      () async {
        // This is the production shape, and the reason a freshly confirmed
        // owner saw "Something went wrong" instead of onboarding.
        //
        // POS-OFFLINE-OPERATIONS-002 narrowed 42501 -> `auth` to an allowlist of
        // PIN/device-session messages, so that a batch-validation or RLS 42501
        // could never strand the POS in a re-auth hold. `get_my_context` raises
        // 42501 for exactly one reason — "no linked, authenticated principal" —
        // and that message is not on a list written for PIN sessions, so it
        // arrived here as `server` -> AuthUnknownFailure ->
        // AuthGateInvalidResponse -> the generic error page.
        //
        // The test above passes `kind: auth` and therefore never exercised this
        // at all.
        final transport = FakeRpcTransport(
          error: const SyncTransportException(
            SyncTransportErrorKind.server,
            code: '42501',
            message: 'get_my_context: no linked, authenticated principal',
          ),
        );
        final result = await AuthContextRepository(transport).fetchMyContext();
        expect(
          (result as Failure<MyContext, AuthFailure>).failure,
          isA<AuthDeniedFailure>(),
          reason: 'a 42501 from get_my_context has one meaning: not linked yet',
        );
      },
    );

    test('transient transport error maps to AuthNetworkFailure', () async {
      final transport = FakeRpcTransport(
        error: const SyncTransportException(SyncTransportErrorKind.transient),
      );
      final result = await AuthContextRepository(transport).fetchMyContext();
      expect(
        (result as Failure<MyContext, AuthFailure>).failure,
        isA<AuthNetworkFailure>(),
      );
    });

    test('server transport error maps to AuthUnknownFailure', () async {
      final transport = FakeRpcTransport(
        error: const SyncTransportException(
          SyncTransportErrorKind.server,
          code: '22000',
        ),
      );
      final result = await AuthContextRepository(transport).fetchMyContext();
      expect(
        (result as Failure<MyContext, AuthFailure>).failure,
        isA<AuthUnknownFailure>(),
      );
    });

    test('malformed response maps to AuthInvalidResponseFailure', () async {
      final transport = FakeRpcTransport(value: 'not an object');
      final result = await AuthContextRepository(transport).fetchMyContext();
      expect(
        (result as Failure<MyContext, AuthFailure>).failure,
        isA<AuthInvalidResponseFailure>(),
      );
    });

    test('ok != true maps to AuthInvalidResponseFailure', () async {
      final bad = validContext()..['ok'] = false;
      final result = await AuthContextRepository(
        FakeRpcTransport(value: bad),
      ).fetchMyContext();
      expect(
        (result as Failure<MyContext, AuthFailure>).failure,
        isA<AuthInvalidResponseFailure>(),
      );
    });

    test(
      'unknown membership role maps to AuthUnknownRoleFailure (fail-closed)',
      () async {
        final bad = validContext(
          memberships: [
            {
              'id': 'm-x',
              'organization_id': 'org-a',
              'organization_name': 'Org A',
              'restaurant_id': null,
              'restaurant_name': null,
              'branch_id': null,
              'branch_name': null,
              'role': 'superuser',
              'status': 'active',
            },
          ],
        );
        final result = await AuthContextRepository(
          FakeRpcTransport(value: bad),
        ).fetchMyContext();
        final failure = (result as Failure<MyContext, AuthFailure>).failure;
        expect(failure, isA<AuthUnknownRoleFailure>());
        expect((failure as AuthUnknownRoleFailure).role, 'superuser');
      },
    );
  });
}
