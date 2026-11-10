import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_section.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

const _org = '11111111-1111-4111-8111-111111111111';
const _restaurant = '22222222-2222-4222-8222-222222222222';
const _branch = '33333333-3333-4333-8333-333333333333';

class _ReadinessTransport implements SyncRpcTransport {
  _ReadinessTransport({this.missing = false, this.dim, this.failure});
  final SyncTransportException? failure;
  final bool missing;
  final int? dim;
  final calls = <String>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add(function);
    expect(params, {'p_organization_id': _org, 'p_restaurant_id': _restaurant});
    if (failure != null) throw failure!;
    if (function == 'list_storefront_content_media_v2') {
      return {
        'ok': true,
        'entity': 'storefront_content_media',
        'restaurant_id': _restaurant,
        'version': 3,
        'media_prefix': 'synthetic',
        'media': <Object?>[],
      };
    }
    if (function != 'get_restaurant_storefront_content_v4') {
      throw StateError('Unexpected RPC: $function');
    }
    if (missing) {
      throw const SyncTransportException(
        SyncTransportErrorKind.server,
        code: 'PGRST202',
        message: 'Synthetic: readiness function absent',
      );
    }
    final document = StorefrontContentDocument.defaults();
    if (dim != null) {
      document['appearance'] = {
        'text_color': null,
        'button_text_color': null,
        'menu_background_media_id': null,
        'menu_background_dim': dim,
      };
    }
    return {
      'ok': true,
      'entity': storefrontContentEntity,
      'restaurant_id': _restaurant,
      'version': 3,
      'storefront_branch_id': _branch,
      'document': document,
      'warnings': <Object?>[],
    };
  }
}

class _Catalog implements StorefrontContentCatalog {
  int calls = 0;
  @override
  Future<StorefrontContentCatalogData?> loadContent(
    String savedBranchId,
  ) async {
    calls++;
    return const StorefrontContentCatalogData(categories: [], items: []);
  }
}

SupabaseStorefrontContentRepository _repository(
  _ReadinessTransport transport,
) => SupabaseStorefrontContentRepository(
  transport: transport,
  organizationId: _org,
  restaurantId: _restaurant,
);

void main() {
  test('missing migration is unavailable without falling back to v1', () async {
    final transport = _ReadinessTransport(missing: true);
    final result = await _repository(transport).readContent();
    expect(result.status, StorefrontContentReadStatus.unavailable);
    expect(result.snapshot, isNull);
    expect(transport.calls, ['get_restaurant_storefront_content_v4']);
  });

  for (final failure in const [
    SyncTransportException(SyncTransportErrorKind.server, code: '42501'),
    SyncTransportException(SyncTransportErrorKind.auth, code: 'PGRST301'),
    SyncTransportException(SyncTransportErrorKind.transient),
    SyncTransportException(SyncTransportErrorKind.server, code: 'PGRST202'),
  ]) {
    test(
      'content and media failures never downgrade: ${failure.code}',
      () async {
        final transport = _ReadinessTransport(failure: failure);
        final repo = _repository(transport);
        expect(
          (await repo.readContent()).status,
          StorefrontContentReadStatus.unavailable,
        );
        expect(await repo.listContentMedia(), isNull);
        expect(transport.calls, [
          'get_restaurant_storefront_content_v4',
          'list_storefront_content_media_v2',
        ]);
      },
    );
  }

  test('ready backend accepts an untouched legacy document', () async {
    final result = await _repository(_ReadinessTransport()).readContent();
    expect(result.isOk, isTrue);
    expect(result.snapshot!.document.json.containsKey('appearance'), isFalse);
  });

  for (final dim in [0, 15, 80]) {
    test('ready backend retains dim $dim in the existing envelope', () async {
      final result = await _repository(
        _ReadinessTransport(dim: dim),
      ).readContent();
      expect(result.isOk, isTrue);
      expect(
        (result.snapshot!.document.json['appearance']
            as Map)['menu_background_dim'],
        dim,
      );
    });
  }

  testWidgets('missing migration exposes reload but no editable content', (
    tester,
  ) async {
    final transport = _ReadinessTransport(missing: true);
    final catalog = _Catalog();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: StorefrontContentSection(
            repository: _repository(transport),
            catalog: catalog,
            profileVersion: 3,
            savedBranchId: _branch,
            onRefresh: () async => const StorefrontContentRefresh.unavailable(),
            onDraftChanged: (_) {},
            onBusyChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('storefront-content-editor')), findsOneWidget);
    expect(find.byKey(const Key('content-hero-headline')), findsNothing);
    expect(find.byKey(const Key('content-save')), findsNothing);
    expect(
      find.byKey(const Key('content-appearance.menu_background_dim')),
      findsNothing,
    );
    expect(find.byType(TextButton), findsOneWidget);
    expect(catalog.calls, 0);
    expect(transport.calls, contains('get_restaurant_storefront_content_v4'));
    expect(
      transport.calls,
      isNot(contains('get_restaurant_storefront_content_v1')),
    );
    expect(
      transport.calls,
      isNot(contains('set_restaurant_storefront_content_v1')),
    );
  });
}
