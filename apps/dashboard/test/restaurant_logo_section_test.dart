import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/branding/restaurant_logo_path.dart';
import 'package:restoflow_dashboard/src/branding/restaurant_logo_repository.dart';
import 'package:restoflow_dashboard/src/branding/restaurant_logo_section.dart';
import 'package:restoflow_dashboard/src/branding/restaurant_logo_storage.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart'
    show PickedMenuImage;
import 'package:restoflow_l10n/restoflow_l10n.dart';

class _FakeRepo implements RestaurantLogoRepository {
  _FakeRepo(this._initial, this._saveResult);
  final RestaurantLogoSettings _initial;
  RestaurantLogoWriteResult _saveResult;
  int saveCalls = 0;
  final List<Map<String, Object?>> saves = [];

  set saveResult(RestaurantLogoWriteResult r) => _saveResult = r;

  @override
  Future<RestaurantLogoSettings?> read() async => _initial;

  @override
  Future<RestaurantLogoWriteResult> save({
    required String? path,
    required bool enabled,
    required int expectedVersion,
  }) async {
    saveCalls++;
    saves.add({'path': path, 'enabled': enabled, 'version': expectedVersion});
    return _saveResult;
  }
}

class _FakeStorage implements RestaurantLogoStorage {
  final List<String> uploaded = [];
  final List<String> removed = [];
  bool uploadThrows = false;
  bool removeThrows = false;

  @override
  Future<void> upload({
    required String objectKey,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    if (uploadThrows) throw StateError('upload failed');
    uploaded.add(objectKey);
  }

  @override
  Future<Uri> createSignedUrl(
    String objectKey, {
    Duration expiresIn = const Duration(minutes: 30),
  }) async => Uri.parse('https://example.test/$objectKey');

  @override
  Future<void> remove(String objectKey) async {
    if (removeThrows) throw StateError('remove failed');
    removed.add(objectKey);
  }
}

Future<PickedMenuImage?> _picker() async => PickedMenuImage(
  bytes: Uint8List.fromList([1, 2, 3]),
  mimeType: 'image/png',
  fileName: 'logo.png',
);

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required RestaurantLogoRepository? repo,
    required RestaurantLogoStorage? storage,
    bool canEdit = true,
    LogoImageIdGenerator? ids,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RestaurantLogoSection(
              repository: repo,
              storage: storage,
              organizationId: 'org1',
              restaurantId: 'rest1',
              canEdit: canEdit,
              idGenerator:
                  ids ??
                  const FixedLogoImageIdGenerator(
                    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                  ),
              picker: _picker,
              pickerSupported: true,
              decodeValidator: (bytes) async => null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const noLogo = RestaurantLogoSettings(path: null, enabled: false, version: 0);
  const withLogo = RestaurantLogoSettings(
    path: 'org1/rest1/logo/old.png',
    enabled: true,
    version: 1,
  );

  testWidgets('null repo => honest unavailable note', (tester) async {
    await pump(tester, repo: null, storage: null);
    expect(find.byKey(const Key('branding-unavailable')), findsOneWidget);
    expect(find.byKey(const Key('branding-pick')), findsNothing);
  });

  testWidgets('unauthorized role hides the edit actions', (tester) async {
    await pump(
      tester,
      repo: _FakeRepo(
        noLogo,
        const RestaurantLogoWriteResult(RestaurantLogoWriteStatus.ok),
      ),
      storage: _FakeStorage(),
      canEdit: false,
    );
    expect(find.byKey(const Key('branding-pick')), findsNothing);
  });

  testWidgets('pick + preview + save uploads then commits + cleans old', (
    tester,
  ) async {
    final repo = _FakeRepo(
      withLogo,
      const RestaurantLogoWriteResult(
        RestaurantLogoWriteStatus.ok,
        settings: RestaurantLogoSettings(
          path: 'org1/rest1/logo/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.png',
          enabled: true,
          version: 2,
        ),
      ),
    );
    final storage = _FakeStorage();
    await pump(tester, repo: repo, storage: storage);
    await tester.tap(find.byKey(const Key('branding-pick')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('branding-preview-picked')), findsOneWidget);
    await tester.tap(find.byKey(const Key('branding-save')));
    await tester.pumpAndSettle();
    expect(repo.saveCalls, 1);
    expect(repo.saves.single['version'], 1); // sent the current version
    expect(storage.uploaded.length, 1); // uploaded the new object first
    expect(storage.removed, contains('org1/rest1/logo/old.png')); // old cleaned
    expect(find.text('Logo saved.'), findsOneWidget);
  });

  testWidgets('upload failure => no pointer write, honest error', (
    tester,
  ) async {
    final repo = _FakeRepo(
      withLogo,
      const RestaurantLogoWriteResult(RestaurantLogoWriteStatus.ok),
    );
    final storage = _FakeStorage()..uploadThrows = true;
    await pump(tester, repo: repo, storage: storage);
    await tester.tap(find.byKey(const Key('branding-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branding-save')));
    await tester.pumpAndSettle();
    expect(repo.saveCalls, 0); // pointer never written
    expect(find.text('Upload failed. Nothing was changed.'), findsOneWidget);
  });

  testWidgets('CAS conflict => orphan cleaned, conflict message', (
    tester,
  ) async {
    final repo = _FakeRepo(
      withLogo,
      const RestaurantLogoWriteResult(
        RestaurantLogoWriteStatus.conflict,
        settings: RestaurantLogoSettings(
          path: 'org1/rest1/logo/other.png',
          enabled: true,
          version: 5,
        ),
      ),
    );
    final storage = _FakeStorage();
    await pump(tester, repo: repo, storage: storage);
    await tester.tap(find.byKey(const Key('branding-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branding-save')));
    await tester.pumpAndSettle();
    // The just-uploaded orphan is cleaned; the old object is NOT deleted.
    expect(
      storage.removed,
      contains('org1/rest1/logo/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.png'),
    );
    expect(storage.removed, isNot(contains('org1/rest1/logo/old.png')));
    expect(
      find.text('Branding was changed by someone else. Showing the latest.'),
      findsOneWidget,
    );
  });

  testWidgets('old-object cleanup failure keeps the new setting (warning)', (
    tester,
  ) async {
    final repo = _FakeRepo(
      withLogo,
      const RestaurantLogoWriteResult(
        RestaurantLogoWriteStatus.ok,
        settings: RestaurantLogoSettings(
          path: 'org1/rest1/logo/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.png',
          enabled: true,
          version: 2,
        ),
      ),
    );
    final storage = _FakeStorage()..removeThrows = true;
    await pump(tester, repo: repo, storage: storage);
    await tester.tap(find.byKey(const Key('branding-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branding-save')));
    await tester.pumpAndSettle();
    expect(repo.saveCalls, 1); // pointer committed (never rolled back)
    expect(
      find.text('Logo saved. The previous image could not be removed.'),
      findsOneWidget,
    );
  });

  testWidgets('remove asks to confirm then clears', (tester) async {
    final repo = _FakeRepo(
      withLogo,
      const RestaurantLogoWriteResult(
        RestaurantLogoWriteStatus.ok,
        settings: RestaurantLogoSettings(
          path: null,
          enabled: false,
          version: 2,
        ),
      ),
    );
    final storage = _FakeStorage();
    await pump(tester, repo: repo, storage: storage);
    await tester.tap(find.byKey(const Key('branding-remove')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('branding-remove-confirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('branding-remove-confirm-action')));
    await tester.pumpAndSettle();
    expect(repo.saves.single['path'], isNull);
    expect(repo.saves.single['enabled'], false);
    expect(find.text('Logo removed.'), findsOneWidget);
  });

  testWidgets('toggle sends the CAS write with the current version', (
    tester,
  ) async {
    final repo = _FakeRepo(
      withLogo,
      const RestaurantLogoWriteResult(
        RestaurantLogoWriteStatus.ok,
        settings: RestaurantLogoSettings(
          path: 'org1/rest1/logo/old.png',
          enabled: false,
          version: 2,
        ),
      ),
    );
    await pump(tester, repo: repo, storage: _FakeStorage());
    await tester.tap(find.byKey(const Key('branding-enable')));
    await tester.pumpAndSettle();
    expect(repo.saveCalls, 1);
    expect(repo.saves.single['enabled'], false); // toggled off
    expect(repo.saves.single['version'], 1);
  });
}
