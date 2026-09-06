import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DevicePrinterAssignments, DevicePrinterAssignmentsFailure;
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/receipt_logo_raster_cache.dart';
import 'package:restoflow_pos/src/design/pos_visual_tokens.dart'
    show posTopBarMetricsFor;
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/print/receipt_logo_asset.dart';
import 'package:restoflow_pos/src/state/pos_printer_assignments.dart';
import 'package:restoflow_pos/src/state/pos_receipt_logo.dart';
import 'package:restoflow_pos/src/widgets/device_settings_menu.dart';
import 'package:restoflow_pos/src/widgets/language_selector.dart';
import 'package:restoflow_pos/src/widgets/outbox_status_indicator.dart';
import 'package:restoflow_pos/src/widgets/pos_identity_title.dart';
import 'package:restoflow_pos/src/widgets/ready_notification_bell.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';

/// POS-TOPBAR-RESTAURANT-IDENTITY-009 — the connected restaurant's identity in
/// the middle of the POS top bar.
///
/// The middle of the bar was empty while the one thing a cashier cannot verify
/// from the screen — WHICH restaurant/branch this station is bound to — was
/// three taps deep in device settings. These tests pin: the name comes from the
/// real token-proven assignments (never hardcoded), the receipt logo appears
/// only when the restaurant actually has one, a long Arabic/Hebrew name
/// truncates on one line instead of pushing the bar, the identity NEVER
/// overlaps the left brand block or the five actions, and every unknown/broken
/// case degrades quietly instead of crashing the cashier's screen.

const Key kIdentity = Key('pos-topbar-identity');
const Key kIdentityName = Key('pos-topbar-identity-name');
const Key kIdentityLogo = Key('pos-topbar-identity-logo');
const Key kBrandTile = Key('pos-brand-tile');

/// A real, decodable 1x1 PNG — so the logo path is exercised with genuine
/// image bytes rather than a shape the widget could accidentally special-case.
final Uint8List kPng1x1 = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

class _NoopCache implements ReceiptLogoRasterCache {
  @override
  Future<ReceiptLogoCacheEntry?> read(ReceiptLogoCacheKey key) async => null;

  @override
  Future<void> write(
    ReceiptLogoCacheKey key,
    ReceiptLogoCacheEntry entry,
  ) async {}
}

/// Publishes a fixed asset, standing in for the real resolve/cache pipeline.
class _StubLogoController extends PosReceiptLogoController {
  _StubLogoController(ReceiptLogoAsset? asset)
    : super(cache: _NoopCache(), reader: null) {
    state = asset;
  }
}

DevicePrinterAssignments _assignments({
  String? restaurantName = 'Falafel House',
  String? branchName = 'Main Branch',
}) => DevicePrinterAssignments(
  fetchedAt: DateTime.utc(2026, 8, 3),
  restaurantName: restaurantName,
  branchName: branchName,
  organizationId: '0a000000-0000-4000-8000-000000000001',
  restaurantId: '0b000000-0000-4000-8000-000000000001',
);

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  double height = 800,
  Locale locale = const Locale('en'),
  DevicePrinterAssignments? assignments,
  ReceiptLogoAsset? logo,
  bool noAssignmentsAtAll = false,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        posPrinterAssignmentsProvider.overrideWith((ref) async {
          if (noAssignmentsAtAll) return null;
          return Success<
            DevicePrinterAssignments,
            DevicePrinterAssignmentsFailure
          >(assignments ?? _assignments());
        }),
        posReceiptLogoAssetProvider.overrideWith(
          (ref) => _StubLogoController(logo),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosMenuScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ReceiptLogoAsset _logoAsset([Uint8List? bytes]) =>
    ReceiptLogoAsset(sourceBytes: bytes ?? kPng1x1, sourceMime: 'image/png');

/// Every control the identity must never sit on top of.
List<Finder> _neighbours() => <Finder>[
  find.byKey(kBrandTile),
  find.byType(ReadyNotificationBell),
  find.byType(RecentOrdersButton),
  find.byType(OutboxStatusIndicator),
  find.byType(LanguageSelector),
  find.byType(DeviceSettingsMenu),
];

void _expectNoOverlapWithControls(WidgetTester tester) {
  final identity = tester.getRect(find.byKey(kIdentity));
  for (final neighbour in _neighbours()) {
    expect(neighbour, findsOneWidget);
    final other = tester.getRect(neighbour);
    expect(
      identity.overlaps(other),
      isFalse,
      reason: 'identity $identity overlaps a top-bar control at $other',
    );
  }
}

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // 1. NAME ONLY — the restaurant has no receipt logo configured.
  // ─────────────────────────────────────────────────────────────────────────
  group('009-1 name only', () {
    testWidgets('the connected restaurant name is in the top bar centre', (
      tester,
    ) async {
      await _pump(tester, width: 1280);

      expect(find.byKey(kIdentity), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(kIdentityName)).data,
        'Falafel House',
      );
      // It really is inside the AppBar, not somewhere in the body.
      expect(
        find.ancestor(of: find.byKey(kIdentity), matching: find.byType(AppBar)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no logo is rendered when the restaurant has none', (
      tester,
    ) async {
      await _pump(tester, width: 1280);

      expect(find.byKey(kIdentityLogo), findsNothing);
      expect(find.byKey(kIdentityName), findsOneWidget);
    });

    testWidgets('a moderately long Arabic name does not overflow', (
      tester,
    ) async {
      await _pump(
        tester,
        width: 1280,
        locale: const Locale('ar'),
        assignments: _assignments(restaurantName: 'مطعم الشام للمأكولات'),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(kIdentityName), findsOneWidget);
      _expectNoOverlapWithControls(tester);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. NAME + LOGO — the restaurant HAS a receipt logo configured.
  // ─────────────────────────────────────────────────────────────────────────
  group('009-2 name and logo', () {
    testWidgets('the receipt logo renders beside the name', (tester) async {
      await _pump(tester, width: 1280, logo: _logoAsset());

      expect(find.byKey(kIdentityLogo), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(kIdentityName)).data,
        'Falafel House',
      );

      // It is the RECEIPT logo bytes that are shown — the same asset the
      // receipt prints, not a second POS-only image.
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byKey(kIdentityLogo),
          matching: find.byType(Image),
        ),
      );
      expect(image.image, isA<MemoryImage>());
      expect((image.image as MemoryImage).bytes, kPng1x1);
    });

    testWidgets('the logo LEADS the name, and the block stays in the bar', (
      tester,
    ) async {
      await _pump(tester, width: 1280, logo: _logoAsset());

      final logoX = tester.getCenter(find.byKey(kIdentityLogo)).dx;
      final nameX = tester.getCenter(find.byKey(kIdentityName)).dx;
      expect(logoX, lessThan(nameX));
      expect(
        find.ancestor(of: find.byKey(kIdentity), matching: find.byType(AppBar)),
        findsOneWidget,
      );
    });

    testWidgets('the identity never overlaps the brand tile or the actions', (
      tester,
    ) async {
      await _pump(tester, width: 1280, logo: _logoAsset());
      _expectNoOverlapWithControls(tester);
      expect(tester.takeException(), isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. LONG NAMES — one line, ellipsis, capped, never pushes the controls.
  // ─────────────────────────────────────────────────────────────────────────
  group('009-3 long names', () {
    const cases = <String, (Locale, String)>{
      'arabic': (
        Locale('ar'),
        'مطعم الشام الكبير للمأكولات الشرقية والمشاوي والحلويات الفاخرة',
      ),
      'hebrew': (
        Locale('he'),
        'מסעדת השף הגדולה למאכלים מזרחיים ומנגלים וקינוחים משובחים',
      ),
      'english': (
        Locale('en'),
        'The Extremely Long Restaurant Name Of Grilled Delights And Desserts',
      ),
    };

    cases.forEach((label, data) {
      final (locale, name) = data;
      testWidgets('$label: single line, truncates, no overflow', (
        tester,
      ) async {
        await _pump(
          tester,
          width: 1280,
          locale: locale,
          assignments: _assignments(restaurantName: name),
          logo: _logoAsset(),
        );

        expect(tester.takeException(), isNull);

        final text = tester.widget<Text>(find.byKey(kIdentityName));
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(text.data, name, reason: 'the real name, never truncated data');

        // ONE rendered line, and the block honours its own cap.
        final nameSize = tester.getSize(find.byKey(kIdentityName));
        final identitySize = tester.getSize(find.byKey(kIdentity));
        expect(nameSize.height, lessThan(40));
        expect(identitySize.width, lessThanOrEqualTo(kPosIdentityMaxWidth));

        _expectNoOverlapWithControls(tester);
      });
    });

    testWidgets('a long name still leaves every action hit-testable', (
      tester,
    ) async {
      await _pump(
        tester,
        width: 1024,
        height: 600,
        assignments: _assignments(
          restaurantName: 'A Ridiculously Long Restaurant Name That Never Ends',
        ),
        logo: _logoAsset(),
      );

      expect(tester.takeException(), isNull);
      for (final neighbour in _neighbours()) {
        expect(neighbour, findsOneWidget);
      }
      _expectNoOverlapWithControls(tester);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 4. GRACEFUL FALLBACK — unknown name, unknown logo, broken image.
  // ─────────────────────────────────────────────────────────────────────────
  group('009-4 fallback', () {
    testWidgets('falls back to the BRANCH name when no restaurant name', (
      tester,
    ) async {
      await _pump(
        tester,
        width: 1280,
        assignments: _assignments(restaurantName: null, branchName: 'Herzliya'),
      );

      expect(tester.widget<Text>(find.byKey(kIdentityName)).data, 'Herzliya');
    });

    testWidgets('blank names are treated as unknown, not printed blank', (
      tester,
    ) async {
      await _pump(
        tester,
        width: 1280,
        assignments: _assignments(restaurantName: '   ', branchName: '  '),
      );

      expect(find.byKey(kIdentity), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nothing connected: the bar stays stable and complete', (
      tester,
    ) async {
      await _pump(tester, width: 1280, noAssignmentsAtAll: true);

      expect(find.byKey(kIdentity), findsNothing);
      expect(tester.takeException(), isNull);
      // The bar itself is unharmed — no placeholder copy was invented.
      for (final neighbour in _neighbours()) {
        expect(neighbour, findsOneWidget);
      }
    });

    testWidgets('undecodable logo bytes do not crash; text identity remains', (
      tester,
    ) async {
      await _pump(
        tester,
        width: 1280,
        logo: _logoAsset(Uint8List.fromList(const [1, 2, 3, 4, 5])),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(kIdentityName), findsOneWidget);

      // The image degrades to NOTHING rather than a broken-image glyph.
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byKey(kIdentityLogo),
          matching: find.byType(Image),
        ),
      );
      expect(image.errorBuilder, isNotNull);
      final degraded = image.errorBuilder!(
        tester.element(find.byKey(kIdentityLogo)),
        Exception('decode failed'),
        null,
      );
      expect(degraded, isA<SizedBox>());
      expect((degraded as SizedBox).width, 0);
      expect(degraded.height, 0);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 5. EXISTING APP-BAR BEHAVIOUR PRESERVED.
  // ─────────────────────────────────────────────────────────────────────────
  group('009-5 existing behaviour preserved', () {
    testWidgets('all five actions, the brand tile and the wordmark survive', (
      tester,
    ) async {
      await _pump(tester, width: 1280, logo: _logoAsset());

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // POS-NAVBAR-BRAND-LOCKUP: the brand block is the OFFICIAL lockup —
      // symbol + English wordmark ARTWORK over the smaller product line (the
      // typed brand name is gone; a typed `BIZBOT` may only be the wordmark
      // Image's errorBuilder when the package asset is absent from an app
      // test bundle, never a sibling substitute).
      expect(find.byKey(kBrandTile), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(kBrandTile),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Image &&
                w.image is AssetImage &&
                (w.image as AssetImage).assetName ==
                    RestoflowBrandMark.wordmarkLatinAsset,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.posBrandTagline), findsOneWidget);
      for (final typed in find.text(l10n.posBrandName).evaluate()) {
        expect(typed.findAncestorWidgetOfExactType<Image>(), isNotNull);
      }
      for (final neighbour in _neighbours()) {
        expect(neighbour, findsOneWidget);
      }
    });

    testWidgets('compact phone bar: identity yields, actions keep their room', (
      tester,
    ) async {
      await _pump(
        tester,
        width: 320,
        locale: const Locale('ar'),
        logo: _logoAsset(),
      );

      // ZERO layout overflow at the tightest supported bar.
      expect(tester.takeException(), isNull);
      // The identity gives way rather than ellipsizing into a meaningless "…".
      expect(find.byKey(kIdentity), findsNothing);
      expect(find.byKey(kBrandTile), findsOneWidget);
      for (final neighbour in _neighbours()) {
        expect(neighbour, findsOneWidget);
      }
    });

    testWidgets('compact landscape keeps the identity AND the actions', (
      tester,
    ) async {
      await _pump(tester, width: 1024, height: 600, logo: _logoAsset());

      expect(tester.takeException(), isNull);
      expect(find.byKey(kIdentity), findsOneWidget);
      expect(find.byKey(kIdentityLogo), findsOneWidget);
      _expectNoOverlapWithControls(tester);
    });
  });
  // ─────────────────────────────────────────────────────────────────────────
  // 6. POS-NAVBAR-TRANSPARENT-BRAND — centred on the BAR, as tall as the mark.
  // ─────────────────────────────────────────────────────────────────────────
  group('bar-centred identity', () {
    for (final locale in const [Locale('en'), Locale('ar')]) {
      testWidgets('${locale.languageCode}: the chip sits on the bar\'s own '
          'midpoint (not the free region\'s) and stands as tall as the brand '
          'mark', (tester) async {
        for (final width in const [1280.0, 1920.0]) {
          await _pump(tester, width: width, locale: locale, logo: _logoAsset());
          expect(tester.takeException(), isNull);
          // The visible chip is the padded Container around the keyed Row
          // (its padding is 9 / 14 start / end, so the Row's own centre sits
          // 2.5 px off the chip's).
          final chipBox = tester.getRect(
            find
                .ancestor(
                  of: find.byKey(kIdentity),
                  matching: find.byType(Container),
                )
                .first,
          );
          expect(
            chipBox.center.dx,
            closeTo(width / 2, 1.0),
            reason: '${locale.languageCode} @ $width: centred on the bar',
          );
          final mark = posTopBarMetricsFor(width).markSize;
          final logo = tester.getSize(find.byKey(kIdentityLogo));
          expect(logo.width, mark);
          expect(logo.height, mark);
          // Chip outer box = logo + 5 px padding + 1 px edge per side — the
          // brand lockup's own height (mark + its 6 px insets).
          expect(chipBox.height, mark + 12);
          _expectNoOverlapWithControls(tester);
        }
      });
    }

    testWidgets('when the free region cannot reach the midpoint the chip '
        'clamps inside it — never over the brand block or the actions', (
      tester,
    ) async {
      await _pump(
        tester,
        width: 1024,
        height: 600,
        logo: _logoAsset(),
        assignments: _assignments(
          restaurantName: 'A Very Long Restaurant Name For The Bar Test',
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(kIdentity), findsOneWidget);
      _expectNoOverlapWithControls(tester);
    });
  });
}
