import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// The REAL image panel (menu/media sprint): pick -> validate -> preview ->
/// confirm uploads THEN persists (never a fake success), replace/remove, the
/// honest unavailable / unsupported-platform / demo states.

MenuItem _item({String? imagePath}) => MenuItem(
  id: 'item-1',
  organizationId: demoMenuScope.organizationId,
  restaurantId: demoMenuScope.restaurantId,
  branchId: demoMenuScope.branchId,
  menuCategoryId: 'cat-1',
  name: 'Espresso',
  description: null,
  basePriceMinor: 350,
  currencyCode: demoCurrencyCode,
  defaultStationId: null,
  displayOrder: 0,
  isActive: true,
  imagePath: imagePath,
);

InMemoryMenuStore _store({String? imagePath, bool readOnly = false}) =>
    InMemoryMenuStore(
      categories: [
        MenuCategory(
          id: 'cat-1',
          organizationId: demoMenuScope.organizationId,
          restaurantId: demoMenuScope.restaurantId,
          branchId: null,
          name: 'Drinks',
          displayOrder: 0,
          isActive: true,
        ),
      ],
      items: [_item(imagePath: imagePath)],
      readOnly: readOnly,
    );

PickedMenuImage _png({int size = 16}) => PickedMenuImage(
  bytes: Uint8List.fromList(List<int>.filled(size, 7)),
  mimeType: 'image/png',
  fileName: 'photo.png',
);

/// A storage whose upload always fails (the panel must show a danger notice
/// and persist NOTHING).
class _ThrowingUploadStorage extends FakeMenuImageStorage {
  @override
  Future<MenuImageUpload> upload({
    required String objectKey,
    required List<int> bytes,
    required String mimeType,
  }) async {
    throw Exception('upload boom');
  }
}

Future<AppLocalizations> _pumpPanel(
  WidgetTester tester, {
  required InMemoryMenuStore store,
  MenuImageStorageConfig? config,
  PickedMenuImage? picked,
  bool pickerSupported = true,
  MenuItem? item,
}) async {
  late AppLocalizations l10n;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...menuFeatureOverrides(
          scope: demoMenuScope,
          readSource: store,
          writer: store,
          imageStorage: config,
        ),
        menuImagePickerSupportedProvider.overrideWithValue(pickerSupported),
        menuImageFilePickerProvider.overrideWithValue(() async => picked),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
              return SingleChildScrollView(
                child: MenuImagePanel(item: item ?? _item()),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return l10n;
}

Future<MenuItem> _storedItem(InMemoryMenuStore store) async =>
    (await store.load(demoMenuScope)).items.single;

void main() {
  testWidgets('pick -> preview -> save uploads to the RF-110 key and persists '
      'image_path', (tester) async {
    final store = _store();
    final storage = FakeMenuImageStorage();
    final l10n = await _pumpPanel(
      tester,
      store: store,
      config: MenuImageStorageConfig(storage: storage),
      picked: _png(),
    );

    // Idle: a pick affordance, no image yet.
    expect(find.byKey(const ValueKey('menu-image-pick')), findsOneWidget);
    expect(find.text(l10n.menuImagePickAction), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('menu-image-pick')));
    await tester.pumpAndSettle();

    // Local preview + explicit confirm — nothing uploaded yet.
    expect(find.byKey(const ValueKey('menu-image-save')), findsOneWidget);
    expect(storage.uploads, isEmpty);

    await tester.tap(find.byKey(const ValueKey('menu-image-save')));
    await tester.pumpAndSettle();

    // Uploaded to a buildMenuImageObjectKey path...
    expect(storage.uploads, hasLength(1));
    final key = storage.uploads.single.objectKey;
    expect(
      key,
      startsWith(
        '${demoMenuScope.organizationId}/${demoMenuScope.restaurantId}/'
        '${demoMenuScope.branchId}/menu_item/item-1/',
      ),
    );
    expect(key, endsWith('.png'));
    // ...and the pointer was persisted through the item upsert.
    expect((await _storedItem(store)).imagePath, key);
  });

  testWidgets('a disallowed MIME type shows the localized error and uploads '
      'nothing', (tester) async {
    final store = _store();
    final storage = FakeMenuImageStorage();
    final l10n = await _pumpPanel(
      tester,
      store: store,
      config: MenuImageStorageConfig(storage: storage),
      picked: PickedMenuImage(
        bytes: Uint8List.fromList(const [1, 2, 3]),
        mimeType: 'image/gif',
        fileName: 'anim.gif',
      ),
    );

    await tester.tap(find.byKey(const ValueKey('menu-image-pick')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.menuImageInvalidType), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-image-save')), findsNothing);
    expect(storage.uploads, isEmpty);
  });

  testWidgets('an over-limit image shows the localized error and uploads '
      'nothing', (tester) async {
    final store = _store();
    final storage = FakeMenuImageStorage();
    final l10n = await _pumpPanel(
      tester,
      store: store,
      config: MenuImageStorageConfig(storage: storage),
      picked: _png(size: kMaxMenuImageBytes + 1),
    );

    await tester.tap(find.byKey(const ValueKey('menu-image-pick')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.menuImageTooLarge), findsOneWidget);
    expect(storage.uploads, isEmpty);
  });

  testWidgets('a failed upload shows a danger notice and persists NOTHING '
      '(no fake success)', (tester) async {
    final store = _store();
    final storage = _ThrowingUploadStorage();
    final l10n = await _pumpPanel(
      tester,
      store: store,
      config: MenuImageStorageConfig(storage: storage),
      picked: _png(),
    );

    await tester.tap(find.byKey(const ValueKey('menu-image-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-image-save')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.menuImageUploadFailed), findsOneWidget);
    expect((await _storedItem(store)).imagePath, isNull);
  });

  testWidgets('a denied persist shows the write failure and cleans up the '
      'fresh blob', (tester) async {
    final store = _store(readOnly: true); // server-mirrored permission_denied
    final storage = FakeMenuImageStorage();
    final l10n = await _pumpPanel(
      tester,
      store: store,
      config: MenuImageStorageConfig(storage: storage),
      picked: _png(),
    );

    await tester.tap(find.byKey(const ValueKey('menu-image-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-image-save')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.menuWritePermissionDenied), findsOneWidget);
    // The blob went up but the pointer write was denied — best-effort cleanup.
    expect(storage.uploads, hasLength(1));
    expect(storage.removals, [storage.uploads.single.objectKey]);
  });

  testWidgets('remove persists a null pointer and best-effort deletes the '
      'blob', (tester) async {
    const existing =
        'demo-org/demo-restaurant/demo-branch/menu_item/item-1/'
        '00000000-0000-0000-0000-000000000001.png';
    final store = _store(imagePath: existing);
    final storage = FakeMenuImageStorage();
    await _pumpPanel(
      tester,
      store: store,
      config: MenuImageStorageConfig(storage: storage),
      item: _item(imagePath: existing),
    );

    // An existing image offers replace + remove.
    expect(find.byKey(const ValueKey('menu-image-remove')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('menu-image-remove')));
    await tester.pumpAndSettle();

    expect((await _storedItem(store)).imagePath, isNull);
    expect(storage.removals, [existing]);
  });

  testWidgets('no wired storage renders the honest not-connected state', (
    tester,
  ) async {
    final store = _store();
    final l10n = await _pumpPanel(tester, store: store);

    expect(find.text(l10n.menuImageDeferredTitle), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-image-pick')), findsNothing);
  });

  testWidgets('an unsupported platform shows the honest note instead of a '
      'pick button', (tester) async {
    final store = _store();
    final l10n = await _pumpPanel(
      tester,
      store: store,
      config: MenuImageStorageConfig(storage: FakeMenuImageStorage()),
      pickerSupported: false,
    );

    expect(find.text(l10n.menuImageUnsupportedPlatform), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-image-pick')), findsNothing);
  });

  testWidgets('the demo surface is labelled "not uploaded to a server"', (
    tester,
  ) async {
    final store = _store();
    final l10n = await _pumpPanel(
      tester,
      store: store,
      config: MenuImageStorageConfig(
        storage: FakeMenuImageStorage(),
        isDemo: true,
      ),
    );

    expect(find.text(l10n.menuImageDemoNote), findsOneWidget);
  });
}
