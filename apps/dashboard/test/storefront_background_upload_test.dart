import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/branding/restaurant_logo_path.dart';
import 'package:restoflow_dashboard/src/branding/restaurant_logo_storage.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_background_upload.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_section.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_publisher.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_models.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

// Local adapter/widget checks with synthetic Storage and RPC responses.
// Real Auth/Storage permissions and persisted Hero/logo pointer invariance
// require the separate isolated end-to-end run; these tests do not prove them.
const _org = '11111111-1111-4111-8111-111111111111';
const _restaurant = '22222222-2222-4222-8222-222222222222';
const _branch = '33333333-3333-4333-8333-333333333333';
const _image = '44444444-4444-4444-8444-444444444444';
const _media = '55555555-5555-4555-8555-555555555555';
const _request = '66666666-6666-4666-8666-666666666666';
const _source = '$_org/$_restaurant/logo/$_image.jpg';

PickedMenuImage _picked({String mime = 'image/jpeg', int size = 20}) =>
    PickedMenuImage(
      bytes: Uint8List(size),
      mimeType: mime,
      fileName: '../../not-an-object-key.jpg',
    );

class _Storage implements RestaurantLogoStorage {
  final uploads = <({String key, String mime, Uint8List bytes})>[];
  Completer<void>? pending;
  @override
  Future<void> upload({
    required String objectKey,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    uploads.add((key: objectKey, mime: mimeType, bytes: bytes));
    await pending?.future;
  }

  @override
  Future<Uri> createSignedUrl(
    String key, {
    Duration expiresIn = const Duration(minutes: 30),
  }) => throw StateError('background upload must not sign receipt images');
  @override
  Future<void> remove(String key) =>
      throw StateError('background upload must not remove images');
}

class _Repo implements StorefrontContentRepository {
  var version = 3;
  var status = StorefrontContentReadStatus.ok;
  var document = StorefrontContentDocument.fromJson(
    StorefrontContentDocument.defaults(headline: 'Existing headline'),
  );
  final rows = <StorefrontContentMediaRow>[];
  final writes = <StorefrontContentAttempt>[];
  @override
  Future<StorefrontContentRead> readContent() async => StorefrontContentRead(
    status,
    snapshot: status == StorefrontContentReadStatus.ok
        ? StorefrontContentSnapshot(
            restaurantId: _restaurant,
            version: version,
            branchId: _branch,
            document: document,
            warnings: const [],
          )
        : null,
  );
  @override
  Future<StorefrontContentMediaList?> listContentMedia() async =>
      StorefrontContentMediaList(version: version, rows: rows);
  @override
  StorefrontContentAttempt prepareContent({
    required int expectedVersion,
    required String expectedBranchId,
    required StorefrontContentDocument document,
  }) => StorefrontContentAttempt(
    requestId: _request,
    expectedVersion: expectedVersion,
    expectedBranchId: expectedBranchId,
    document: document,
  );
  @override
  Future<StorefrontContentWrite> saveContent(
    StorefrontContentAttempt attempt,
  ) async {
    writes.add(attempt);
    document = attempt.document;
    version++;
    return StorefrontContentWrite(
      StorefrontContentWriteStatus.ok,
      attempt: attempt,
      version: version,
    );
  }
}

class _Catalog implements StorefrontContentCatalog {
  @override
  Future<StorefrontContentCatalogData?> loadContent(String branch) async =>
      const StorefrontContentCatalogData(categories: [], items: []);
}

class _Invoker implements StorefrontFunctionInvoker {
  _Invoker(this.repo);
  final _Repo repo;
  final calls = <Map<String, Object?>>[];
  String outcome = 'published';
  bool exposeMedia = true;
  Completer<void>? pending;
  Map<String, Object?> media(String source) => {
    'id': _media,
    'source_bucket': 'restaurant-logos',
    'source_key': source,
    'variant': 'w960',
    'object_key': 'synthetic/w960.webp',
    'content_hash': 'a' * 64,
    'width': 960,
    'height': 640,
    'bytes': 123,
    'state': 'published',
    'published_at': '2026-10-22T00:00:00Z',
    'unpublished_at': null,
    'created_at': '2026-10-22T00:00:00Z',
    'in_use': [],
    'content_in_use': [],
  };
  @override
  Future<StorefrontFunctionReply> invoke(Map<String, Object?> body) async {
    calls.add(Map.of(body));
    await pending?.future;
    if (outcome == 'uncertain')
      return const StorefrontFunctionReply.transportFailure();
    if (outcome == 'object_conflict') {
      return StorefrontFunctionReply.fromHttp(409, {
        'ok': false,
        'status': 'object_conflict',
      });
    }
    final row = media(
      outcome == 'mismatched'
          ? 'another/source.jpg'
          : body['source_key']! as String,
    );
    if (exposeMedia) {
      repo.rows
        ..clear()
        ..add(StorefrontContentMediaRow.fromJson(row));
    }
    return StorefrontFunctionReply.fromHttp(200, {
      'ok': true,
      'status': 'published',
      'media': row,
    });
  }
}

class _Rig {
  _Rig({Future<PickedMenuImage?> Function()? picker}) {
    upload = StorefrontBackgroundUpload(
      storage: storage,
      organizationId: _org,
      restaurantId: _restaurant,
      ids: const FixedLogoImageIdGenerator(_image),
      picker: picker ?? () async => _picked(),
      pickerSupported: true,
    );
    invoker = _Invoker(repo);
    publisher = StorefrontMediaPublisher(
      invoker: invoker,
      organizationId: _org,
      restaurantId: _restaurant,
      retryDelay: Duration.zero,
    );
  }
  final repo = _Repo();
  final storage = _Storage();
  final catalog = _Catalog();
  late final StorefrontBackgroundUpload upload;
  late final _Invoker invoker;
  late final StorefrontMediaPublisher publisher;
  bool enabled = true, includeUpload = true, includePublisher = true;
  int refreshes = 0;
  final busyEvents = <bool>[];
}

Future<void Function(_Rig)> _mount(WidgetTester tester, _Rig rig) async {
  await tester.binding.setSurfaceSize(const Size(1024, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  var current = rig;
  late StateSetter update;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              final binding = current;
              return Padding(
                padding: const EdgeInsets.all(16),
                child: StorefrontContentSection(
                  repository: binding.repo,
                  catalog: binding.catalog,
                  profileVersion: binding.repo.version,
                  savedBranchId: _branch,
                  enabled: binding.enabled,
                  publisher: binding.includePublisher
                      ? binding.publisher
                      : null,
                  backgroundUpload: binding.includeUpload
                      ? binding.upload
                      : null,
                  onRefresh: () async {
                    binding.refreshes++;
                    update(() {});
                    return StorefrontContentRefresh(
                      profileRead: true,
                      mediaRead: true,
                      version: binding.repo.version,
                      branchId: _branch,
                    );
                  },
                  onDraftChanged: (_) {},
                  onBusyChanged: binding.busyEvents.add,
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (next) => update(() => current = next);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder get _background => find.byWidgetPredicate(
  (w) =>
      w is DropdownButtonFormField<String> &&
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith(
        'content-appearance.menu_background_media_id-',
      ),
);

void main() {
  test(
    'private upload reuses scoped key and byte validation without receipt operations',
    () async {
      final rig = _Rig();
      final source = await rig.upload.pickAndUpload(isCurrent: () => true);
      expect(source!.bucket, StorefrontSourceBucket.restaurantLogos);
      expect(source.key, _source);
      expect(rig.storage.uploads.single.key, _source);
      expect(rig.storage.uploads.single.mime, 'image/jpeg');
    },
  );

  test('invalid MIME, empty and oversized bytes never reach Storage', () async {
    for (final pick in [
      _picked(mime: 'image/svg+xml'),
      _picked(size: 0),
      _picked(size: 2 * 1024 * 1024 + 1),
    ]) {
      final rig = _Rig(picker: () async => pick);
      await expectLater(
        rig.upload.pickAndUpload(isCurrent: () => true),
        throwsFormatException,
      );
      expect(rig.storage.uploads, isEmpty);
    }
  });

  testWidgets(
    'upload publishes, selects an unsaved background, saves and clears without changing hero content',
    (tester) async {
      final rig = _Rig();
      final hero = rig.repo.document.json['hero'];
      final headline = rig.repo.document.json['hero_headline'];
      expect(hero, isNotNull);
      expect(headline, 'Existing headline');
      await _mount(tester, rig);
      await _tap(tester, 'content-menu-background-upload');
      expect(rig.storage.uploads, hasLength(1));
      expect(rig.invoker.calls.single['slot'], 'hero');
      expect(rig.invoker.calls.single['variant'], 'w960');
      expect(rig.invoker.calls.single['source_key'], _source);
      expect(rig.repo.writes, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('content-save')))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const Key('content-menu-background-upload')),
            )
            .onPressed,
        isNull,
      );
      await _tap(tester, 'content-save');
      expect(
        (rig.repo.document.json['appearance']
            as Map)['menu_background_media_id'],
        _media,
      );
      expect(rig.repo.document.json['hero'], hero);
      expect(rig.repo.document.json['hero_headline'], headline);
      tester.widget<DropdownButtonFormField<String>>(_background).onChanged!(
        '',
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'content-save');
      expect(
        (rig.repo.document.json['appearance']
            as Map)['menu_background_media_id'],
        isNull,
      );
      expect(rig.repo.document.json['hero'], hero);
      expect(rig.repo.document.json['hero_headline'], headline);
      expect(rig.storage.uploads, hasLength(1));
    },
  );

  testWidgets(
    'uncertain retry retains source and request without another upload',
    (tester) async {
      final rig = _Rig()..invoker.outcome = 'uncertain';
      await _mount(tester, rig);
      await _tap(tester, 'content-menu-background-upload');
      expect(rig.invoker.calls, hasLength(2));
      final request = rig.invoker.calls.first['request_id'];
      rig.invoker.outcome = 'published';
      await _tap(tester, 'content-retry-publish');
      expect(rig.storage.uploads, hasLength(1));
      expect(rig.invoker.calls, hasLength(3));
      expect(rig.invoker.calls.map((c) => c['request_id']).toSet(), {request});
      expect(rig.invoker.calls.map((c) => c['source_key']).toSet(), {_source});
      expect(rig.repo.writes, isEmpty);
      await _tap(tester, 'content-save');
      expect(
        (rig.repo.document.json['appearance']
            as Map)['menu_background_media_id'],
        _media,
      );
    },
  );

  testWidgets(
    'definitive source conflict releases upload without selecting or saving',
    (tester) async {
      final rig = _Rig()..invoker.outcome = 'object_conflict';
      await _mount(tester, rig);
      await _tap(tester, 'content-menu-background-upload');
      expect(rig.repo.writes, isEmpty);
      expect(rig.refreshes, 0);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const Key('content-menu-background-upload')),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('content-save')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('published source mismatch is never selected into the draft', (
    tester,
  ) async {
    final rig = _Rig()..invoker.outcome = 'mismatched';
    await _mount(tester, rig);
    await _tap(tester, 'content-menu-background-upload');
    expect(rig.repo.writes, isEmpty);
    expect(rig.refreshes, 0);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('content-save')))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'confirmed publication waits for live media read before selecting',
    (tester) async {
      final rig = _Rig()..invoker.exposeMedia = false;
      await _mount(tester, rig);
      await _tap(tester, 'content-menu-background-upload');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('content-save')))
            .onPressed,
        isNull,
      );
      rig.repo.rows.add(
        StorefrontContentMediaRow.fromJson(rig.invoker.media(_source)),
      );
      await _tap(tester, 'content-resume-read');
      expect(rig.storage.uploads, hasLength(1));
      expect(rig.invoker.calls, hasLength(1));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('content-save')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'readiness denial and missing dependencies expose no upload action',
    (tester) async {
      for (final status in [
        StorefrontContentReadStatus.unavailable,
        StorefrontContentReadStatus.denied,
      ]) {
        final rig = _Rig()..repo.status = status;
        await _mount(tester, rig);
        expect(
          find.byKey(const Key('content-menu-background-upload')),
          findsNothing,
        );
        expect(rig.storage.uploads, isEmpty);
      }
      for (final rig in [
        _Rig()..includeUpload = false,
        _Rig()..includePublisher = false,
      ]) {
        await _mount(tester, rig);
        expect(
          find.byKey(const Key('content-menu-background-upload')),
          findsNothing,
        );
      }
    },
  );

  testWidgets('dirty draft and disabled editor block upload', (tester) async {
    final rig = _Rig()..enabled = false;
    final replace = await _mount(tester, rig);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('content-menu-background-upload')),
          )
          .onPressed,
      isNull,
    );
    rig.enabled = true;
    replace(rig);
    await tester.pumpAndSettle();
    final headline = find.byKey(const Key('content-hero-headline'));
    await tester.ensureVisible(headline);
    await tester.enterText(headline, 'Unsaved draft');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('content-menu-background-upload')),
          )
          .onPressed,
      isNull,
    );
    expect(rig.storage.uploads, isEmpty);
  });

  testWidgets(
    'binding replacement while picking discards bytes before upload',
    (tester) async {
      final pick = Completer<PickedMenuImage?>();
      final old = _Rig(picker: () => pick.future);
      final replace = await _mount(tester, old);
      await _tap(tester, 'content-menu-background-upload');
      final next = _Rig();
      replace(next);
      await tester.pumpAndSettle();
      pick.complete(_picked());
      await tester.pumpAndSettle();
      expect(old.storage.uploads, isEmpty);
      expect(old.invoker.calls, isEmpty);
      expect(next.storage.uploads, isEmpty);
      expect(next.busyEvents.last, false);
    },
  );

  testWidgets(
    'binding replacement during publication cannot select on new binding',
    (tester) async {
      final pending = Completer<void>();
      final old = _Rig()..invoker.pending = pending;
      final replace = await _mount(tester, old);
      await _tap(tester, 'content-menu-background-upload');
      final next = _Rig();
      replace(next);
      await tester.pumpAndSettle();
      pending.complete();
      await tester.pumpAndSettle();
      expect(old.refreshes, 0);
      expect(next.refreshes, 0);
      expect(next.repo.writes, isEmpty);
      expect(next.invoker.calls, isEmpty);
    },
  );
}
