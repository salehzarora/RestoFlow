import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_kiosk/src/widgets/category_wheel.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KIOSK-001 Phase 1 — screen-level widget coverage of the fixture flow at
/// the canonical 1080×1920 frame (menu, item sheet required flow + live
/// total, cart editing, table states, confirmation, PIN, RTL/LTR bar).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            locale: Locale(ref.watch(kioskFlowProvider.select((s) => s.lang))),
            debugShowCheckedModeBanner: false,
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const KioskShell(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  KioskFlowController controller() =>
      container.read(kioskFlowProvider.notifier);
  KioskState state() => container.read(kioskFlowProvider);

  Future<void> toMenu(WidgetTester tester) async {
    controller().startFromAttract();
    controller().pickService(KioskServiceType.takeaway);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('menu screen', () {
    testWidgets('renders the wheel, grid cards and both bottom pills (AR)', (
      tester,
    ) async {
      await pumpShell(tester);
      await toMenu(tester);
      expect(find.byType(KioskCategoryWheel), findsOneWidget);
      expect(find.text('إمبر سماش'), findsOneWidget); // b1 card
      expect(find.byKey(const Key('kiosk-cart-pill')), findsOneWidget);
      expect(find.byKey(const Key('kiosk-checkout-pill')), findsOneWidget);
      // RTL: the wheel sits on the RIGHT half of the frame.
      final railX = tester.getCenter(find.byType(KioskCategoryWheel)).dx;
      expect(railX, greaterThan(540));
    });

    testWidgets('EN mirrors the wheel to the left', (tester) async {
      await pumpShell(tester);
      controller().setLanguage('en');
      await toMenu(tester);
      final railX = tester.getCenter(find.byType(KioskCategoryWheel)).dx;
      expect(railX, lessThan(540));
      expect(find.text('Ember Smash'), findsOneWidget);
    });

    testWidgets('selecting a category swaps the grid content', (tester) async {
      await pumpShell(tester);
      await toMenu(tester);
      controller().setCategoryIndex(3); // drinks
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('كولا'), findsWidgets);
      expect(find.text('إمبر سماش'), findsNothing);
    });
  });

  group('item sheet', () {
    testWidgets(
      'required weight preselects included; deltas render; CTA carries the '
      'live total and updates on selection + quantity',
      (tester) async {
        await pumpShell(tester);
        await toMenu(tester);
        await tester.tap(find.text('إمبر سماش'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        // Included preselected → CTA total = base 40.
        expect(find.textContaining('40 ₪'), findsWidgets);
        // Delta labels (+15 ₪ / +25 ₪) rendered on the weight options.
        expect(find.text('+15 ₪'), findsOneWidget);
        expect(find.text('+25 ₪'), findsOneWidget);
        await tester.tap(find.byKey(const Key('kiosk-option-w240')));
        await tester.pump(const Duration(milliseconds: 200));
        expect(state().draft!.totalMinor, 5500);
        await tester.tap(find.byKey(const Key('kiosk-qty-inc')));
        await tester.pump(const Duration(milliseconds: 200));
        expect(state().draft!.totalMinor, 11000);
        await tester.tap(find.byKey(const Key('kiosk-item-cta')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(state().cart.single.lineTotalMinor, 11000);
      },
    );

    testWidgets('unmet required blocks the CTA and shows the shake hint', (
      tester,
    ) async {
      await pumpShell(tester);
      await toMenu(tester);
      controller().setCategoryIndex(1); // meals
      await tester.pump(const Duration(milliseconds: 900));
      await tester.tap(find.text('وجبة إمبر'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('kiosk-required-error')), findsNothing);
      await tester.tap(find.byKey(const Key('kiosk-item-cta')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(state().cart, isEmpty);
      expect(find.byKey(const Key('kiosk-required-error')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('cart sheet', () {
    testWidgets('shows lines, edits via tap, steppers and total', (
      tester,
    ) async {
      await pumpShell(tester);
      await toMenu(tester);
      await tester.tap(find.text('إمبر سماش'));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.tap(find.byKey(const Key('kiosk-option-w360')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('kiosk-item-cta')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('kiosk-cart-pill')));
      await tester.pump(const Duration(milliseconds: 800));
      final lineId = state().cart.single.lineId;
      expect(find.byKey(Key('kiosk-cart-line-$lineId')), findsOneWidget);
      // 360g summary shows on the line; total = 65.
      expect(find.textContaining('360غ'), findsOneWidget);
      expect(find.byKey(const Key('kiosk-cart-total')), findsOneWidget);
      await tester.tap(find.byKey(Key('kiosk-line-inc-$lineId')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(state().cart.single.quantity, 2);
      await tester.tap(find.byKey(Key('kiosk-line-remove-$lineId')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(state().cart, isEmpty);
      expect(find.text('سلتك فارغة'), findsOneWidget);
    });
  });

  group('table picker', () {
    testWidgets(
      'occupied/reserved/out-of-service are visible but not selectable; '
      'continue enables only with a selection',
      (tester) async {
        await pumpShell(tester);
        controller().startFromAttract();
        controller().pickService(KioskServiceType.dineIn);
        await tester.pump(const Duration(milliseconds: 900));
        // Occupied T2 is on screen but tapping it selects nothing.
        await tester.tap(find.text('T2'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(state().selectedTable, isNull);
        // Continue with no selection keeps the screen.
        await tester.tap(find.byKey(const Key('kiosk-table-continue')));
        await tester.pump(const Duration(milliseconds: 100));
        expect(state().screen, KioskScreen.tables);
        // Available T4 selects, check bubble appears, continue proceeds.
        await tester.tap(find.text('T4'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(state().selectedTable, 'T4');
        await tester.tap(find.byKey(const Key('kiosk-table-continue')));
        await tester.pump(const Duration(milliseconds: 900));
        expect(state().screen, KioskScreen.menu);
        expect(find.textContaining('T4'), findsWidgets);
      },
    );
  });

  group('confirmation', () {
    testWidgets('shows the number, slip lines and localized totals', (
      tester,
    ) async {
      await pumpShell(tester);
      await toMenu(tester);
      await tester.tap(find.text('إمبر سماش'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(state().sheet, KioskSheet.item);
      await tester.tap(find.byKey(const Key('kiosk-item-cta')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(state().cart, hasLength(1));
      controller().openCart();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('kiosk-place-order')));
      await tester.pump(const Duration(milliseconds: 900));
      expect(state().screen, KioskScreen.confirm);
      expect(find.byKey(const Key('kiosk-confirm-number')), findsOneWidget);
      expect(find.byKey(const Key('kiosk-slip-total')), findsOneWidget);
      expect(find.text('ادفع عند الكاشير'.toUpperCase()), findsOneWidget);
      await tester.tap(find.byKey(const Key('kiosk-new-order')));
      await tester.pump(const Duration(milliseconds: 900));
      expect(state().screen, KioskScreen.attract);
    });
  });

  group('PIN gate + idle overlay', () {
    testWidgets('triple-tap opens the gate; the fixture PIN opens settings', (
      tester,
    ) async {
      await pumpShell(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('kiosk-staff-dots')));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('kiosk-pin-2')), findsOneWidget);
      for (final k in ['2', '4', '6', '8']) {
        await tester.tap(find.byKey(Key('kiosk-pin-$k')));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(state().screen, KioskScreen.settings);
      expect(find.byKey(const Key('kiosk-settings-exit')), findsOneWidget);
      // The tables toggle mutates fixture settings only.
      await tester.tap(find.byKey(const Key('kiosk-settings-tables-toggle')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(state().settings.tablePickerEnabled, isFalse);
    });

    testWidgets('the idle warning overlay renders and I\'m-here dismisses it', (
      tester,
    ) async {
      await pumpShell(tester);
      await toMenu(tester);
      for (var i = 0; i < 55; i++) {
        controller().tick();
      }
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('kiosk-idle-count')), findsOneWidget);
      await tester.tap(find.byKey(const Key('kiosk-im-here')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('kiosk-idle-count')), findsNothing);
      expect(state().screen, KioskScreen.menu);
    });
  });
}
