import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

import 'package:restoflow_kiosk/src/data/kiosk_appearance.dart';
import 'package:restoflow_kiosk/src/data/kiosk_attract_media.dart';
import 'package:restoflow_kiosk/src/data/kiosk_fixtures.dart';
import 'package:restoflow_kiosk/src/data/kiosk_logo_picker.dart';
import 'package:restoflow_kiosk/src/data/kiosk_menu_data.dart';
import 'package:restoflow_kiosk/src/data/kiosk_order_submit.dart';
import 'package:restoflow_kiosk/src/print/kiosk_receipt_auto_print.dart';
import 'package:restoflow_kiosk/src/print/kiosk_receipt_document.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';

import 'package:restoflow_kiosk/src/state/kiosk_receipt_branding.dart';
import 'package:restoflow_kiosk/src/state/kiosk_staff_access.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

/// KIOSK-001-103 — curated attract media, the kiosk receipt document, the
/// exactly-once accepted-order auto-print, the printed-receipt ledger, and
/// the receipt-branding fallback chain. No network anywhere.

// ---------------------------------------------------------------------------
// shared fixtures
// ---------------------------------------------------------------------------

KioskMenuData _menu() => KioskMenuData(
  categories: [
    KioskFixtureCategory(
      id: 'c1',
      name: const KioskText3.same('Burgers'),
      items: const [
        KioskFixtureItem(
          id: 'i1',
          name: KioskText3.same('Burger A'),
          description: KioskText3.same(''),
          basePriceMinor: 4000,
          groupIds: [],
          imagePath: 'org/a.png',
        ),
        KioskFixtureItem(
          id: 'i2',
          name: KioskText3.same('Burger B'),
          description: KioskText3.same(''),
          basePriceMinor: 4200,
          groupIds: [],
          imagePath: 'org/b.png',
        ),
        KioskFixtureItem(
          id: 'i3',
          name: KioskText3.same('Sold out'),
          description: KioskText3.same(''),
          basePriceMinor: 1000,
          groupIds: [],
          imagePath: 'org/c.png',
          available: false,
        ),
        KioskFixtureItem(
          id: 'i4',
          name: KioskText3.same('No photo'),
          description: KioskText3.same(''),
          basePriceMinor: 900,
          groupIds: [],
        ),
      ],
    ),
  ],
  groups: const {},
  currencyCode: 'ILS',
  live: true,
);

const _urls = {'org/a.png': 'https://s/a', 'org/b.png': 'https://s/b'};

KioskOrderSnapshot _snapshot({String? orderId = 'ord-1'}) => KioskOrderSnapshot(
  number: 7,
  code: '#ABC123',
  orderId: orderId,
  lines: const [
    KioskCartLine(
      lineId: 1,
      itemId: 'i1',
      quantity: 2,
      selected: {
        'g1': ['o2'],
      },
      note: 'no salt',
      capturedUnitMinor: 5500,
    ),
  ],
  lineDisplays: const [
    KioskFrozenLineDisplay(
      lineId: 1,
      itemName: KioskText3.same('Frozen Burger'),
      modifierNames: [KioskText3.same('240g')],
    ),
  ],
  totalMinor: 12870,
  subtotalMinor: 11000,
  taxMinor: 1870,
  taxInclusive: false,
  service: KioskServiceType.dineIn,
  table: 'T1',
  customerName: 'Sam',
);

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('appearance model — 103 fields', () {
    test('json roundtrip preserves mode, ordered featured ids and refs', () {
      final settings = KioskAppearanceSettings.defaults(fallbackName: 'x')
          .copyWith(
            attractMediaMode: KioskAttractMediaMode.customVideo,
            featuredMenuItemIds: const ['i2', 'i1', 'i9'],
            customImageRef: 'attract_image_1.png',
            customVideoRef: 'attract_video_2.mp4',
          );
      final restored = KioskAppearanceSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())),
        KioskAppearanceSettings.defaults(fallbackName: 'x'),
      );
      expect(restored.attractMediaMode, KioskAttractMediaMode.customVideo);
      expect(restored.featuredMenuItemIds, ['i2', 'i1', 'i9']);
      expect(restored.customImageRef, 'attract_image_1.png');
      expect(restored.customVideoRef, 'attract_video_2.mp4');
    });

    test('malformed 103 fields degrade safely (never crash, never trust)', () {
      final fallback = KioskAppearanceSettings.defaults(fallbackName: 'x');
      final restored = KioskAppearanceSettings.fromJson({
        'attract_media_mode': 'evil_mode',
        'featured_menu_item_ids': [
          1,
          'ok-1',
          '',
          'ok-1', // dupe dropped
          'x' * 200, // over-long id dropped
          for (var i = 0; i < 20; i++) 'fill-$i', // capped at 8 total
        ],
        'custom_image_ref': 42,
        'custom_video_ref': 'y' * 500,
      }, fallback);
      expect(
        restored.attractMediaMode,
        KioskAttractMediaMode.selectedMenuPhotos,
      );
      expect(restored.featuredMenuItemIds.length, 8);
      expect(restored.featuredMenuItemIds.first, 'ok-1');
      expect(restored.featuredMenuItemIds.where((e) => e == 'ok-1').length, 1);
      expect(restored.customImageRef, isNull);
      expect(restored.customVideoRef, isNull);
    });

    test('featured carousel maps ids in OPERATOR order, skips stale, never '
        'substitutes', () {
      final menu = _menu();
      // i2 before i1 (operator order), i3 unavailable, i4 no photo,
      // 'gone' deleted from the menu.
      final urls = kioskFeaturedCarouselUrls(menu, _urls, [
        'i2',
        'gone',
        'i3',
        'i4',
        'i1',
      ]);
      expect(urls, ['https://s/b', 'https://s/a']);
      expect(kioskFeaturedCarouselUrls(menu, _urls, const []), isEmpty);
      // An empty usable set yields EMPTY — never unrelated products.
      expect(
        kioskFeaturedCarouselUrls(menu, _urls, const ['i3', 'i4']),
        isEmpty,
      );
    });

    test('media ref pattern refuses traversal and junk', () {
      expect(
        kioskAttractMediaRefPattern.hasMatch('attract_image_123.png'),
        isTrue,
      );
      expect(
        kioskAttractMediaRefPattern.hasMatch('attract_video_456.mp4'),
        isTrue,
      );
      for (final bad in [
        '../attract_image_1.png',
        'attract_image_1.png/../x',
        '/etc/passwd',
        'attract_other_1.png',
        'attract_image_.png',
        'attract_image_1.',
        'attract_image_1.veryverylong',
      ]) {
        expect(kioskAttractMediaRefPattern.hasMatch(bad), isFalse, reason: bad);
      }
    });

    test('attract image validation: junk refused, oversize refused', () async {
      final junk = await validateKioskImageBytes(
        Uint8List.fromList(List.filled(32, 9)),
        maxBytes: KioskAppearanceLimits.attractImageBytes,
      );
      expect(junk.error, KioskLogoPickError.unsupportedType);

      final hugePng = Uint8List(KioskAppearanceLimits.attractImageBytes + 1);
      hugePng.setRange(0, 4, const [0x89, 0x50, 0x4E, 0x47]);
      final big = await validateKioskImageBytes(
        hugePng,
        maxBytes: KioskAppearanceLimits.attractImageBytes,
      );
      expect(big.error, KioskLogoPickError.tooLarge);
    });
  });

  group('attract media store (device-local files)', () {
    late Directory temp;
    setUp(() {
      temp = Directory.systemTemp.createTempSync('kiosk103');
      PathProviderPlatform.instance = _FakePathProvider(temp.path);
    });
    tearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('persist -> resolve -> replace -> delete lifecycle', () async {
      const store = KioskAttractMediaStore();
      expect(store.supported, isTrue);
      final bytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
      final first = await store.persistImage(deviceId: 'dev-1', bytes: bytes);
      expect(first.ref, isNotNull);
      expect(kioskAttractMediaRefPattern.hasMatch(first.ref!), isTrue);

      final path = await store.absolutePathOf(
        deviceId: 'dev-1',
        ref: first.ref!,
      );
      expect(path, isNotNull);
      expect(File(path!).readAsBytesSync(), bytes);

      // A NEW store instance (an app restart) resolves the same ref.
      const restarted = KioskAttractMediaStore();
      expect(
        await restarted.absolutePathOf(deviceId: 'dev-1', ref: first.ref!),
        isNotNull,
      );

      await store.delete(deviceId: 'dev-1', ref: first.ref!);
      expect(
        await store.absolutePathOf(deviceId: 'dev-1', ref: first.ref!),
        isNull,
      );
    });

    test('video copy enforces the byte cap and the ext whitelist', () async {
      const store = KioskAttractMediaStore();
      final source = File('${temp.path}${Platform.pathSeparator}src.mp4')
        ..writeAsBytesSync(List.filled(1024, 7));
      final ok = await store.persistVideoFromPath(
        deviceId: 'dev-1',
        sourcePath: source.path,
        ext: 'mp4',
      );
      expect(ok.ref, isNotNull);
      expect(ok.ref!, endsWith('.mp4'));

      // Oversize refused before any copy lands.
      final big = File('${temp.path}${Platform.pathSeparator}big.mp4');
      final raf = big.openSync(mode: FileMode.write);
      raf.truncateSync(KioskAppearanceLimits.attractVideoBytes + 1);
      raf.closeSync();
      final refused = await store.persistVideoFromPath(
        deviceId: 'dev-1',
        sourcePath: big.path,
        ext: 'mp4',
      );
      expect(refused.ref, isNull);
      expect(refused.error, KioskAttractMediaError.storeFailed);
    });

    test('absolutePathOf refuses malformed refs outright', () async {
      const store = KioskAttractMediaStore();
      for (final bad in ['../x.png', 'attract_image_1.exe..', 'nope']) {
        expect(
          await store.absolutePathOf(deviceId: 'dev-1', ref: bad),
          isNull,
          reason: bad,
        );
      }
    });
  });

  group('kiosk receipt document (§11)', () {
    AppLocalizations l10nFor(String lang) =>
        lookupAppLocalizations(Locale(lang));

    List<String> textsOf(pp.PrintDocument doc) => [
      for (final line in doc.lines)
        if (line is pp.PrintTextLine) line.text,
    ];

    test('renders the FROZEN order exactly — and zero EMBER', () {
      final doc = buildKioskReceiptDocument(
        l10n: l10nFor('en'),
        order: _snapshot(),
        restaurantName: 'Maps Burger',
        lang: 'en',
      );
      final texts = textsOf(doc);
      final joined = texts.join('\n');
      expect(texts.first, 'Maps Burger');
      expect(joined, contains('#ABC123'));
      expect(joined, contains('2× Frozen Burger'));
      expect(joined, contains('+ 240g'));
      expect(joined, contains('* no salt'));
      expect(joined, contains('₪110')); // subtotal 11000 minor
      expect(joined, contains('₪18.70')); // tax 1870 minor
      expect(joined, contains('₪128.70')); // total 12870 minor
      expect(joined, contains('T1'));
      expect(joined, contains('Sam'));
      expect(joined.toUpperCase(), isNot(contains('EMBER')));
      // No fixture daily number: the shared display code is the identity.
      expect(joined, isNot(contains('#007')));
      expect(doc.lines.last, isA<pp.PrintCutLine>());
      // Unpaid semantics: the pay-at-counter stamp, never a payment claim.
      expect(joined, contains(l10nFor('en').kioskPayAtCounter));
    });

    test('logo raster leads the document when branding is available', () {
      final raster = pp.LogoRaster(
        widthDots: 8,
        widthBytes: 1,
        heightDots: 1,
        data: Uint8List(1),
      );
      final doc = buildKioskReceiptDocument(
        l10n: l10nFor('ar'),
        order: _snapshot(),
        restaurantName: 'برجر الخرائط',
        lang: 'ar',
        logoRaster: raster,
      );
      expect(doc.lines.first, isA<pp.PrintRasterImageLine>());
      expect(doc.localeTag, 'ar');
    });

    test('a line without a frozen display falls back to the raw id — '
        'never a live-menu lookup', () {
      final order = KioskOrderSnapshot(
        number: 1,
        code: '#X',
        orderId: 'o',
        lines: const [
          KioskCartLine(
            lineId: 9,
            itemId: 'item-raw-id',
            quantity: 1,
            selected: {},
            note: '',
            capturedUnitMinor: 100,
          ),
        ],
        totalMinor: 100,
        service: KioskServiceType.takeaway,
        table: null,
        customerName: '',
      );
      final texts = textsOf(
        buildKioskReceiptDocument(
          l10n: l10nFor('en'),
          order: order,
          restaurantName: 'R',
          lang: 'en',
        ),
      );
      expect(texts.join('\n'), contains('item-raw-id'));
    });
  });

  group('printed-receipt ledger', () {
    test('bounded newest-first at $kKioskPrintedLedgerLimit', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final ledger = KioskPrintedReceiptLedger(prefs);
      for (var i = 0; i < kKioskPrintedLedgerLimit + 5; i++) {
        await ledger.record('dev-1', 'order-$i');
      }
      expect(ledger.contains('dev-1', 'order-104'), isTrue);
      expect(ledger.contains('dev-1', 'order-0'), isFalse); // pruned
      final raw = prefs.getString(kioskPrintedLedgerKey('dev-1'))!;
      final ids = (jsonDecode(raw)['ids'] as List).length;
      expect(ids, kKioskPrintedLedgerLimit);
    });

    test('unreadable envelope degrades to empty and self-heals', () async {
      SharedPreferences.setMockInitialValues({
        kioskPrintedLedgerKey('dev-1'): '{not json',
      });
      final prefs = await SharedPreferences.getInstance();
      final ledger = KioskPrintedReceiptLedger(prefs);
      expect(ledger.contains('dev-1', 'x'), isFalse);
      await ledger.record('dev-1', 'x');
      expect(ledger.contains('dev-1', 'x'), isTrue);
    });
  });

  group('auto-print — exactly once, accepted only (§10)', () {
    Future<
      ({
        ProviderContainer container,
        List<pp.PrintDocument> sent,
        KioskPrintedReceiptLedger ledger,
      })
    >
    autoPrintHarness({
      bool enabled = true,
      bool configured = true,
      bool failSend = false,
      KioskReceiptBranding? branding,
    }) async {
      SharedPreferences.setMockInitialValues({
        if (enabled) kioskAutoPrintPrefKey('dev-1'): true,
      });
      final prefs = await SharedPreferences.getInstance();
      final sent = <pp.PrintDocument>[];
      final ledger = KioskPrintedReceiptLedger(prefs);
      final container = ProviderContainer(
        overrides: [
          kioskPrintedReceiptLedgerProvider.overrideWithValue(ledger),
          kioskReceiptSendProvider.overrideWithValue(() async {
            if (!configured) return null;
            return (doc) async {
              sent.add(doc);
              return failSend
                  ? const pp.BridgeSubmitResult.failed(
                      pp.PrinterErrorCategory.unknown,
                      'boom',
                    )
                  : const pp.BridgeSubmitResult.sentToPrinter(mode: 'native');
            };
          }),
          if (branding != null)
            kioskReceiptBrandingProvider.overrideWith((ref) async => branding),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(kioskDeviceContextProvider.notifier)
          .state = const DeviceContext(
        organizationId: 'org',
        branchId: 'br',
        deviceId: 'dev-1',
      );
      return (container: container, sent: sent, ledger: ledger);
    }

    test('OFF by default => zero prints', () async {
      final h = await autoPrintHarness(enabled: false);
      await h.container
          .read(kioskReceiptAutoPrintProvider)
          .onOrderAccepted(order: _snapshot(), lang: 'en');
      expect(h.sent, isEmpty);
      expect(h.container.read(kioskReceiptPrintStatusProvider), isNull);
    });

    test('ON + configured => EXACTLY one print, ledger recorded', () async {
      final h = await autoPrintHarness();
      final printer = h.container.read(kioskReceiptAutoPrintProvider);
      await printer.onOrderAccepted(order: _snapshot(), lang: 'ar');
      expect(h.sent.length, 1);
      expect(h.ledger.contains('dev-1', 'ord-1'), isTrue);
      final status = h.container.read(kioskReceiptPrintStatusProvider);
      expect(status?.outcome, KioskReceiptPrintOutcome.sent);
      expect(status?.orderId, 'ord-1');
      // Idempotent replay of the SAME logical order: still one.
      await printer.onOrderAccepted(order: _snapshot(), lang: 'ar');
      expect(h.sent.length, 1);
    });

    test('concurrent double-fire => one print (in-flight latch)', () async {
      final h = await autoPrintHarness();
      final printer = h.container.read(kioskReceiptAutoPrintProvider);
      await Future.wait([
        printer.onOrderAccepted(order: _snapshot(), lang: 'en'),
        printer.onOrderAccepted(order: _snapshot(), lang: 'en'),
      ]);
      expect(h.sent.length, 1);
    });

    test('a ledger hit from a previous RUN suppresses the print', () async {
      final h = await autoPrintHarness();
      await h.ledger.record('dev-1', 'ord-1');
      await h.container
          .read(kioskReceiptAutoPrintProvider)
          .onOrderAccepted(order: _snapshot(), lang: 'en');
      expect(h.sent, isEmpty);
    });

    test('print failure: order stays accepted, status failed, NO ledger '
        'record, no auto-retry loop', () async {
      final h = await autoPrintHarness(failSend: true);
      final printer = h.container.read(kioskReceiptAutoPrintProvider);
      await printer.onOrderAccepted(order: _snapshot(), lang: 'en');
      expect(h.sent.length, 1);
      expect(h.ledger.contains('dev-1', 'ord-1'), isFalse);
      expect(
        h.container.read(kioskReceiptPrintStatusProvider)?.outcome,
        KioskReceiptPrintOutcome.failed,
      );
      // No spontaneous retry happened; a deliberate REPLAY may try again.
      await printer.onOrderAccepted(order: _snapshot(), lang: 'en');
      expect(h.sent.length, 2);
    });

    test('no configured printer => notConfigured, zero sends', () async {
      final h = await autoPrintHarness(configured: false);
      await h.container
          .read(kioskReceiptAutoPrintProvider)
          .onOrderAccepted(order: _snapshot(), lang: 'en');
      expect(h.sent, isEmpty);
      expect(
        h.container.read(kioskReceiptPrintStatusProvider)?.outcome,
        KioskReceiptPrintOutcome.notConfigured,
      );
    });

    test('a demo order (no UUID) never prints', () async {
      final h = await autoPrintHarness();
      await h.container
          .read(kioskReceiptAutoPrintProvider)
          .onOrderAccepted(order: _snapshot(orderId: null), lang: 'en');
      expect(h.sent, isEmpty);
    });

    test('§12: the printed identity is the Dashboard branding name — the '
        'device appearance logo/name never overrides it', () async {
      final h = await autoPrintHarness(
        branding: const KioskReceiptBranding(restaurantName: 'Real Rest'),
      );
      await h.container
          .read(kioskReceiptAutoPrintProvider)
          .onOrderAccepted(order: _snapshot(), lang: 'en');
      final texts = [
        for (final line in h.sent.single.lines)
          if (line is pp.PrintTextLine) line.text,
      ].join('\n');
      expect(texts, contains('Real Rest'));
      expect(texts.toUpperCase(), isNot(contains('EMBER')));
    });
  });
}
