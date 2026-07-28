import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_printing/restoflow_printing.dart'
    show LogoValidationError;
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
  final List<Uint8List> uploadedBytes = [];
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
    uploadedBytes.add(bytes);
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

  // canManage true => editable (the backend capability drives the UI).
  const withLogo = RestaurantLogoSettings(
    path: 'org1/rest1/logo/old.png',
    enabled: true,
    version: 1,
    canManage: true,
  );

  testWidgets('null repo => honest unavailable note', (tester) async {
    await pump(tester, repo: null, storage: null);
    expect(find.byKey(const Key('branding-unavailable')), findsOneWidget);
    expect(find.byKey(const Key('branding-pick')), findsNothing);
  });

  testWidgets(
    'a covering non-manager (can_manage=false) is READ-ONLY — no controls',
    (tester) async {
      await pump(
        tester,
        repo: _FakeRepo(
          const RestaurantLogoSettings(
            path: 'org1/rest1/logo/old.png',
            enabled: true,
            version: 1,
            canManage: false, // backend says: read but cannot manage
          ),
          const RestaurantLogoWriteResult(RestaurantLogoWriteStatus.ok),
        ),
        storage: _FakeStorage(),
      );
      // No management controls; an honest read-only note; the preview shows.
      expect(find.byKey(const Key('branding-pick')), findsNothing);
      expect(find.byKey(const Key('branding-save')), findsNothing);
      expect(find.byKey(const Key('branding-remove')), findsNothing);
      expect(find.byKey(const Key('branding-enable')), findsNothing);
      expect(find.byKey(const Key('branding-readonly')), findsOneWidget);
    },
  );

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

  testWidgets(
    'UNCERTAIN outcome deletes NOTHING (orphan safer than authoritative)',
    (tester) async {
      final repo = _FakeRepo(
        withLogo,
        const RestaurantLogoWriteResult(RestaurantLogoWriteStatus.uncertain),
      );
      final storage = _FakeStorage();
      await pump(tester, repo: repo, storage: storage);
      await tester.tap(find.byKey(const Key('branding-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('branding-save')));
      await tester.pumpAndSettle();
      // Neither the new upload NOR the old object is deleted.
      expect(storage.removed, isEmpty);
      expect(
        find.text(
          'We could not confirm the change. Refresh and check before trying again.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('NOT-COMMITTED outcome deletes only the new orphan', (
    tester,
  ) async {
    final repo = _FakeRepo(
      withLogo,
      const RestaurantLogoWriteResult(
        RestaurantLogoWriteStatus.notCommitted,
        settings: withLogo, // authoritative is still the OLD one
      ),
    );
    final storage = _FakeStorage();
    await pump(tester, repo: repo, storage: storage);
    await tester.tap(find.byKey(const Key('branding-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branding-save')));
    await tester.pumpAndSettle();
    // The just-uploaded orphan is removed; the old object is KEPT.
    expect(
      storage.removed,
      contains('org1/rest1/logo/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.png'),
    );
    expect(storage.removed, isNot(contains('org1/rest1/logo/old.png')));
  });

  testWidgets('remove with an UNCERTAIN outcome keeps the old object', (
    tester,
  ) async {
    final repo = _FakeRepo(
      withLogo,
      const RestaurantLogoWriteResult(RestaurantLogoWriteStatus.uncertain),
    );
    final storage = _FakeStorage();
    await pump(tester, repo: repo, storage: storage);
    await tester.tap(find.byKey(const Key('branding-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branding-remove-confirm-action')));
    await tester.pumpAndSettle();
    expect(
      storage.removed,
      isEmpty,
      reason: 'never delete on an ambiguous remove',
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

  group('§7 pick → preview → save flow', () {
    const noLogo = RestaurantLogoSettings(
      path: null,
      enabled: false,
      version: 0,
      canManage: true,
    );
    const okResult = RestaurantLogoWriteResult(
      RestaurantLogoWriteStatus.ok,
      settings: RestaurantLogoSettings(
        path: 'org1/rest1/logo/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.png',
        enabled: true,
        version: 1,
        canManage: true,
      ),
    );

    PickedMenuImage png(List<int> b) => PickedMenuImage(
      bytes: Uint8List.fromList(b),
      mimeType: 'image/png',
      fileName: 'l.png',
    );

    Future<void> pumpFlow(
      WidgetTester tester, {
      required Future<PickedMenuImage?> Function() picker,
      required Future<LogoValidationError?> Function(Uint8List) validator,
      required _FakeStorage storage,
      required _FakeRepo repo,
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
                idGenerator: const FixedLogoImageIdGenerator(
                  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                ),
                picker: picker,
                pickerSupported: true,
                decodeValidator: validator,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('valid pick shows Save + preview; NO upload until Save', (
      tester,
    ) async {
      final storage = _FakeStorage();
      final repo = _FakeRepo(noLogo, okResult);
      await pumpFlow(
        tester,
        picker: () async => png([1, 2, 3]),
        validator: (_) async => null,
        storage: storage,
        repo: repo,
      );
      await tester.tap(find.byKey(const Key('branding-pick')));
      await tester.pumpAndSettle();
      // preview ready => Save shown, no error text, and NOTHING uploaded yet.
      expect(find.byKey(const Key('branding-save')), findsOneWidget);
      expect(find.byKey(const Key('branding-message')), findsNothing);
      expect(storage.uploaded, isEmpty, reason: 'no upload before Save');
      expect(repo.saveCalls, 0);
      // Press Save => upload happens now, exactly once.
      await tester.tap(find.byKey(const Key('branding-save')));
      await tester.pumpAndSettle();
      expect(storage.uploaded, hasLength(1));
      expect(repo.saveCalls, 1);
    });

    testWidgets('corrupt bytes show an error and NO Save/preview', (
      tester,
    ) async {
      final storage = _FakeStorage();
      final repo = _FakeRepo(noLogo, okResult);
      await pumpFlow(
        tester,
        picker: () async => png([9, 9, 9]),
        validator: (_) async => LogoValidationError.decodeFailed,
        storage: storage,
        repo: repo,
      );
      await tester.tap(find.byKey(const Key('branding-pick')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('branding-save')), findsNothing);
      expect(find.byKey(const Key('branding-message')), findsOneWidget);
      expect(storage.uploaded, isEmpty);
    });

    testWidgets('a prior INVALID pick does not poison the next VALID pick', (
      tester,
    ) async {
      final storage = _FakeStorage();
      final repo = _FakeRepo(noLogo, okResult);
      var bad = true;
      await pumpFlow(
        tester,
        picker: () async => png(bad ? [9] : [1, 2, 3]),
        validator: (_) async => bad ? LogoValidationError.decodeFailed : null,
        storage: storage,
        repo: repo,
      );
      await tester.tap(find.byKey(const Key('branding-pick')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('branding-save')), findsNothing); // rejected
      bad = false;
      await tester.tap(find.byKey(const Key('branding-pick')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('branding-save')),
        findsOneWidget,
      ); // recovers
      expect(find.byKey(const Key('branding-message')), findsNothing);
    });

    testWidgets('selecting another image REPLACES the pending preview', (
      tester,
    ) async {
      final storage = _FakeStorage();
      final repo = _FakeRepo(noLogo, okResult);
      var second = false;
      await pumpFlow(
        tester,
        picker: () async => png(second ? [7, 7, 7, 7] : [1, 1]),
        validator: (_) async => null,
        storage: storage,
        repo: repo,
      );
      await tester.tap(find.byKey(const Key('branding-pick')));
      await tester.pumpAndSettle();
      second = true;
      await tester.tap(find.byKey(const Key('branding-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('branding-save')));
      await tester.pumpAndSettle();
      // Only ONE upload, carrying the SECOND selection's bytes.
      expect(storage.uploaded, hasLength(1));
      expect(storage.uploadedBytes.single, orderedEquals([7, 7, 7, 7]));
    });

    testWidgets(
      'a STALE decode completing late cannot overwrite a newer pick',
      (tester) async {
        final storage = _FakeStorage();
        final repo = _FakeRepo(noLogo, okResult);
        final gates = <Completer<LogoValidationError?>>[];
        var call = 0;
        final picks = [
          png([10, 10]),
          png([20, 20, 20, 20]),
        ];
        await pumpFlow(
          tester,
          picker: () async => picks[call < 2 ? call : 1],
          validator: (_) {
            final c = Completer<LogoValidationError?>();
            gates.add(c);
            call++;
            return c.future;
          },
          storage: storage,
          repo: repo,
        );
        // Fire pick #1 (older); its decode stays pending.
        await tester.tap(find.byKey(const Key('branding-pick')));
        await tester.pump();
        // Fire pick #2 (newer) before #1's decode resolves.
        await tester.tap(find.byKey(const Key('branding-pick')));
        await tester.pump();
        expect(gates, hasLength(2));
        // Resolve the NEWER decode first, then the OLDER one.
        gates[1].complete(null);
        await tester.pumpAndSettle();
        gates[0].complete(null); // stale — must be discarded
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('branding-save')));
        await tester.pumpAndSettle();
        // The NEWER selection won; the stale older decode did not overwrite it.
        expect(storage.uploaded, hasLength(1));
        expect(storage.uploadedBytes.single, orderedEquals([20, 20, 20, 20]));
      },
    );
  });
}
