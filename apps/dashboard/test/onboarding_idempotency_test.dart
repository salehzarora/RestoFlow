import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/auth/onboarding_repository.dart';
import 'package:restoflow_dashboard/src/auth/supabase_dashboard_auth.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// A transport that records the last RPC call (no Supabase, no network).
class RecordingTransport implements SyncRpcTransport {
  Object? response = <String, dynamic>{'ok': true, 'idempotent_replay': false};
  String? lastFunction;
  Map<String, dynamic>? lastParams;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    lastFunction = function;
    lastParams = Map<String, dynamic>.of(params);
    return response;
  }
}

const _slugPattern = r'^[a-z0-9]+(-[a-z0-9]+)*$';

void main() {
  SupabaseOnboardingRepository repoFor(
    RecordingTransport t, {
    String userId = 'user-1',
  }) => SupabaseOnboardingRepository(t, currentUserId: () => userId);

  test(
    'retrying the SAME onboarding input reuses the same p_client_request_id '
    '(idempotent) and hits create_organization with the RF-150 params',
    () async {
      final t = RecordingTransport();
      final repo = repoFor(t);

      await repo.createOrganization(
        restaurantName: 'Bistro 21',
        branchName: 'Downtown',
      );
      final first = t.lastParams!['p_client_request_id'];
      final firstSlug = t.lastParams!['p_organization_slug'];

      await repo.createOrganization(
        restaurantName: 'Bistro 21',
        branchName: 'Downtown',
      );
      final second = t.lastParams!['p_client_request_id'];

      expect(second, first, reason: 'same input => same idempotency key');
      // A trivial edit (whitespace/case) is still the same attempt.
      await repo.createOrganization(
        restaurantName: '  bistro 21 ',
        branchName: 'downtown',
      );
      expect(t.lastParams!['p_client_request_id'], first);

      // Still targets the RF-150 wrapper with the p_ parameter names.
      expect(t.lastFunction, 'create_organization');
      expect(
        t.lastParams!.keys.toSet(),
        containsAll(<String>{
          'p_client_request_id',
          'p_organization_name',
          'p_organization_slug',
          'p_restaurant_name',
          'p_branch_name',
          'p_currency_code',
          'p_timezone',
          'p_default_station_name',
        }),
      );
      // A Latin name uses a real slugified slug (not the fallback).
      expect(firstSlug, 'bistro-21');
    },
  );

  test('a non-Latin (Arabic/Hebrew) name yields a STABLE fallback slug across '
      'retries', () async {
    final t = RecordingTransport();
    final repo = repoFor(t);

    await repo.createOrganization(restaurantName: 'مطعم الشرق');
    final slug1 = t.lastParams!['p_organization_slug'] as String;
    await repo.createOrganization(restaurantName: 'מסעדת המזרח');
    final hebrewSlug = t.lastParams!['p_organization_slug'] as String;

    // Retry the Arabic name -> identical fallback slug (no new random suffix).
    final t2 = RecordingTransport();
    await repoFor(t2).createOrganization(restaurantName: 'مطعم الشرق');
    final slug1Retry = t2.lastParams!['p_organization_slug'] as String;

    expect(slug1, startsWith('r-'));
    expect(
      slug1,
      matches(_slugPattern),
      reason: 'fallback slug is backend-valid',
    );
    expect(
      slug1Retry,
      slug1,
      reason: 'non-Latin fallback slug is stable on retry',
    );
    expect(hebrewSlug, startsWith('r-'));
    expect(hebrewSlug, matches(_slugPattern));
  });

  test('changing the restaurant OR the branch starts a new idempotency key; '
      'changing the restaurant also changes a non-Latin slug', () async {
    final t = RecordingTransport();
    final repo = repoFor(t);

    await repo.createOrganization(restaurantName: 'Bistro', branchName: 'Main');
    final baseKey = t.lastParams!['p_client_request_id'];

    await repo.createOrganization(
      restaurantName: 'Bistro',
      branchName: 'Airport',
    );
    expect(
      t.lastParams!['p_client_request_id'],
      isNot(baseKey),
      reason: 'a different branch is a new attempt',
    );

    await repo.createOrganization(restaurantName: 'Cafe', branchName: 'Main');
    expect(
      t.lastParams!['p_client_request_id'],
      isNot(baseKey),
      reason: 'a different restaurant is a new attempt',
    );

    // Non-Latin: a changed restaurant name changes the fallback slug.
    final ta = RecordingTransport();
    final arRepo = repoFor(ta);
    await arRepo.createOrganization(restaurantName: 'مطعم الشرق');
    final slugA = ta.lastParams!['p_organization_slug'];
    await arRepo.createOrganization(restaurantName: 'مطعم الغرب');
    expect(ta.lastParams!['p_organization_slug'], isNot(slugA));
  });

  test('different authenticated users get different keys/slugs for identical '
      'input', () async {
    final t1 = RecordingTransport();
    final t2 = RecordingTransport();
    await repoFor(
      t1,
      userId: 'user-1',
    ).createOrganization(restaurantName: 'مطعم');
    await repoFor(
      t2,
      userId: 'user-2',
    ).createOrganization(restaurantName: 'مطعم');

    expect(
      t2.lastParams!['p_client_request_id'],
      isNot(t1.lastParams!['p_client_request_id']),
    );
    expect(
      t2.lastParams!['p_organization_slug'],
      isNot(t1.lastParams!['p_organization_slug']),
    );
  });

  test(
    'a successful response is reported (idempotent_replay flag surfaced)',
    () async {
      final t = RecordingTransport()
        ..response = <String, dynamic>{'ok': true, 'idempotent_replay': true};
      final outcome = await repoFor(
        t,
      ).createOrganization(restaurantName: 'Bistro');
      expect(outcome, isA<OnboardingSucceeded>());
      expect((outcome as OnboardingSucceeded).idempotentReplay, isTrue);
    },
  );
}
