import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/widgets/order_setup_section.dart';

/// POS-ORDER-TYPE-SELECTOR-UI-001 — the cart's order-type selector used to read
/// BACKWARDS: the unselected option carried the warm filled surface while the
/// selected option turned white and dissolved into the white cart panel, with an
/// icon on both sides and only a subtle foreground colour to separate them.
///
/// These pin the CLARITY contract — selection is carried by fill, weight, icon
/// presence and semantic state, never by colour alone — plus the behaviour that
/// must NOT change. Token-level styling is owned by the design-system's own
/// tests; here we assert the distinctions the cashier actually sees.

const Key _dineInKey = Key('order-type-dine-in');
const Key _takeawayKey = Key('order-type-takeaway');

Future<AppLocalizations> _l10n(Locale locale) =>
    AppLocalizations.delegate.load(locale);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  double width = 380,
}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        theme: restoflowBaseTheme(),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          // A white panel, exactly like the cart the selector lives in — the
          // surface the old selected state disappeared into.
          backgroundColor: Colors.white,
          body: Align(
            alignment: AlignmentDirectional.topStart,
            child: SizedBox(
              width: width,
              child: const SingleChildScrollView(child: OrderSetupSection()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(OrderSetupSection)),
  );
}

/// The decorated surface of one segment — the thing whose fill the cashier
/// reads. Found through the segment's stable key, so it is locale-independent.
BoxDecoration _decorationOf(WidgetTester tester, Key key) {
  final container = tester.widget<Container>(
    find
        .descendant(of: find.byKey(key), matching: find.byType(Container))
        .first,
  );
  return container.decoration! as BoxDecoration;
}

Size _hitTargetOf(WidgetTester tester, Key key) => tester.getSize(
  find.descendant(of: find.byKey(key), matching: find.byType(InkWell)),
);

DemoTable _availableTable() => DemoTable(
  table: DiningTable(
    tableId: 't1',
    label: 'T1',
    organizationId: 'demo-org',
    restaurantId: 'demo-restaurant',
    branchId: 'demo-branch',
    seats: 4,
    isActive: true,
  ),
  status: TableStatusKind.available,
);

void main() {
  group('order-type selector — default state', () {
    testWidgets('001-A1. defaults to Takeaway, and Takeaway is the SELECTED '
        'segment (not merely present)', (tester) async {
      final handle = tester.ensureSemantics();
      final l10n = await _l10n(const Locale('en'));
      final container = await _pump(tester);

      expect(
        container.read(orderSetupControllerProvider).orderType,
        OrderType.takeaway,
      );
      expect(find.byKey(_dineInKey), findsOneWidget);
      expect(find.byKey(_takeawayKey), findsOneWidget);

      // The SELECTED semantic state is what a screen reader announces, and what
      // the old control never made visually obvious. Both options stay BUTTONS,
      // so the inactive one still reads as clickable.
      expect(
        tester.getSemantics(find.bySemanticsLabel(l10n.posOrderTypeTakeaway)),
        matchesSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          label: l10n.posOrderTypeTakeaway,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(l10n.posOrderTypeDineIn)),
        matchesSemantics(
          isButton: true,
          isSelected: false,
          hasSelectedState: true,
          label: l10n.posOrderTypeDineIn,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('001-A2. the selected semantic state MOVES with the choice', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final l10n = await _l10n(const Locale('en'));
      await _pump(tester);

      await tester.tap(find.text(l10n.posOrderTypeDineIn));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.bySemanticsLabel(l10n.posOrderTypeDineIn)),
        matchesSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          label: l10n.posOrderTypeDineIn,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(l10n.posOrderTypeTakeaway)),
        matchesSemantics(
          isButton: true,
          isSelected: false,
          hasSelectedState: true,
          label: l10n.posOrderTypeTakeaway,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      handle.dispose();
    });
  });

  group('order-type selector — the selected state is unmistakable', () {
    testWidgets('001-B1. the SELECTED segment carries a solid brand fill while '
        'the unselected one does not', (tester) async {
      await _pump(tester);

      final takeaway = _decorationOf(tester, _takeawayKey); // selected
      final dineIn = _decorationOf(tester, _dineInKey); // unselected

      expect(
        takeaway.color,
        kRestoflowSeedColor,
        reason: 'the active choice must be the filled one',
      );
      expect(
        dineIn.color,
        isNot(kRestoflowSeedColor),
        reason: 'the inactive choice must not compete with the active fill',
      );
      // The regression being fixed: the selected surface must never be the same
      // white as the cart panel behind it.
      expect(takeaway.color, isNot(Colors.white));
    });

    testWidgets(
      '001-B2. selection is distinguished by more than colour — fill, '
      'elevation, icon presence and weight',
      (tester) async {
        final l10n = await _l10n(const Locale('en'));
        await _pump(tester);

        // 1. Fill + 2. elevation.
        final selected = _decorationOf(tester, _takeawayKey);
        final unselected = _decorationOf(tester, _dineInKey);
        expect(selected.color, isNot(unselected.color));
        expect(selected.boxShadow, isNotNull);
        expect(unselected.boxShadow, isNull);

        // 3. The icon appears ONLY on the active option (the old control showed
        // both icons, so the glyph carried no signal).
        expect(find.byIcon(Icons.takeout_dining), findsOneWidget);
        expect(find.byIcon(Icons.restaurant), findsNothing);

        // 4. Typographic weight.
        final selectedText = tester.widget<Text>(
          find.text(l10n.posOrderTypeTakeaway),
        );
        final unselectedText = tester.widget<Text>(
          find.text(l10n.posOrderTypeDineIn),
        );
        expect(selectedText.style!.fontWeight, FontWeight.w700);
        expect(unselectedText.style!.fontWeight, FontWeight.w600);
        expect(selectedText.style!.color, isNot(unselectedText.style!.color));
      },
    );

    testWidgets(
      '001-B3. the distinction FOLLOWS the selection when it changes',
      (tester) async {
        final l10n = await _l10n(const Locale('en'));
        await _pump(tester);

        await tester.tap(find.text(l10n.posOrderTypeDineIn));
        await tester.pumpAndSettle();

        // Everything inverts: fill, shadow and icon move to Dine-in.
        expect(_decorationOf(tester, _dineInKey).color, kRestoflowSeedColor);
        expect(
          _decorationOf(tester, _takeawayKey).color,
          isNot(kRestoflowSeedColor),
        );
        expect(_decorationOf(tester, _dineInKey).boxShadow, isNotNull);
        expect(find.byIcon(Icons.restaurant), findsOneWidget);
        expect(find.byIcon(Icons.takeout_dining), findsNothing);
      },
    );

    testWidgets('001-B4. each option keeps a >=44dp touch target', (
      tester,
    ) async {
      await _pump(tester);
      // The replaced SegmentedButton set minimumSize: Size.fromHeight(44); the
      // shared control's own default is 38, so this is the regression guard.
      expect(_hitTargetOf(tester, _dineInKey).height, greaterThanOrEqualTo(44));
      expect(
        _hitTargetOf(tester, _takeawayKey).height,
        greaterThanOrEqualTo(44),
      );
    });
  });

  group('order-type selector — behaviour is unchanged', () {
    testWidgets('001-C1. tapping Dine-in switches the state, tapping Takeaway '
        'switches it back', (tester) async {
      final l10n = await _l10n(const Locale('en'));
      final container = await _pump(tester);

      await tester.tap(find.text(l10n.posOrderTypeDineIn));
      await tester.pumpAndSettle();
      expect(
        container.read(orderSetupControllerProvider).orderType,
        OrderType.dineIn,
      );

      await tester.tap(find.text(l10n.posOrderTypeTakeaway));
      await tester.pumpAndSettle();
      expect(
        container.read(orderSetupControllerProvider).orderType,
        OrderType.takeaway,
      );
    });

    testWidgets('001-C2. tapping the ALREADY-selected option is a no-op that '
        'does not disturb the order', (tester) async {
      final l10n = await _l10n(const Locale('en'));
      final container = await _pump(tester);
      final controller = container.read(orderSetupControllerProvider.notifier);

      // Set up a dine-in order WITH a table and a customer name, then re-tap the
      // active option. The old M3 control suppressed the callback entirely; the
      // shared control forwards it, so the no-op must hold in the controller.
      controller.setOrderType(OrderType.dineIn);
      controller.assignTable(_availableTable());
      controller.setCustomerName('Dana');
      await tester.pumpAndSettle();

      final before = container.read(orderSetupControllerProvider);
      expect(before.assignedTable?.tableId, 't1');

      await tester.tap(find.text(l10n.posOrderTypeDineIn));
      await tester.pumpAndSettle();

      final after = container.read(orderSetupControllerProvider);
      expect(after.orderType, OrderType.dineIn);
      expect(after.assignedTable?.tableId, 't1', reason: 'table must survive');
      expect(after.customerName, 'Dana');
      expect(identical(before, after), isTrue, reason: 'no state was emitted');
    });

    testWidgets(
      '001-C3. switching AWAY from Dine-in clears the assigned table, '
      'exactly as before',
      (tester) async {
        final l10n = await _l10n(const Locale('en'));
        final container = await _pump(tester);
        final controller = container.read(
          orderSetupControllerProvider.notifier,
        );

        controller.setOrderType(OrderType.dineIn);
        controller.assignTable(_availableTable());
        controller.setCustomerName('Dana');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('assigned-table-card')), findsOneWidget);

        await tester.tap(find.text(l10n.posOrderTypeTakeaway));
        await tester.pumpAndSettle();

        final state = container.read(orderSetupControllerProvider);
        expect(state.orderType, OrderType.takeaway);
        expect(state.hasTable, isFalse);
        // The order-level customer name survives the switch (unchanged rule).
        expect(state.customerName, 'Dana');
      },
    );

    testWidgets(
      '001-C4. the table-required warning and the no-table hint still '
      'follow the selection',
      (tester) async {
        final l10n = await _l10n(const Locale('en'));
        await _pump(tester);

        // Takeaway (default): the hint, no warning, no assign button.
        expect(find.text(l10n.posTableNotNeeded), findsOneWidget);
        expect(find.byKey(const Key('table-required-warning')), findsNothing);
        expect(find.byKey(const Key('assign-table-button')), findsNothing);

        await tester.tap(find.text(l10n.posOrderTypeDineIn));
        await tester.pumpAndSettle();

        // Dine-in without a table: the warning + the assign button, no hint.
        expect(find.byKey(const Key('table-required-warning')), findsOneWidget);
        expect(find.text(l10n.posTableRequiredWarning), findsOneWidget);
        expect(find.byKey(const Key('assign-table-button')), findsOneWidget);
        expect(find.text(l10n.posTableNotNeeded), findsNothing);
      },
    );
  });

  group('order-type selector — layout across locales and widths', () {
    for (final locale in const [Locale('en'), Locale('ar'), Locale('he')]) {
      testWidgets(
        '001-D1.${locale.languageCode}. renders both localized labels '
        'with no overflow',
        (tester) async {
          final l10n = await _l10n(locale);
          await _pump(tester, locale: locale);

          expect(find.text(l10n.posOrderTypeDineIn), findsOneWidget);
          expect(find.text(l10n.posOrderTypeTakeaway), findsOneWidget);
          expect(find.byKey(_dineInKey), findsOneWidget);
          expect(find.byKey(_takeawayKey), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('001-D2.${locale.languageCode}. survives a narrow cart width '
          'without exceptions', (tester) async {
        final l10n = await _l10n(locale);
        // Narrower than any shipped cart panel — the labels must wrap, not clip
        // the layout or throw.
        await _pump(tester, locale: locale, width: 260);

        expect(find.text(l10n.posOrderTypeDineIn), findsOneWidget);
        expect(find.text(l10n.posOrderTypeTakeaway), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Still tappable at that width.
        await tester.tap(find.byKey(_dineInKey));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('001-D3. Arabic and Hebrew lay out RIGHT-to-left', (
      tester,
    ) async {
      for (final locale in const [Locale('ar'), Locale('he')]) {
        await _pump(tester, locale: locale);
        expect(
          Directionality.of(tester.element(find.byKey(_dineInKey))),
          TextDirection.rtl,
          reason: '${locale.languageCode} must mirror',
        );
        // Dine-in is FIRST in source, so under RTL it sits to the RIGHT of
        // Takeaway — the source order itself is unchanged.
        expect(
          tester.getCenter(find.byKey(_dineInKey)).dx,
          greaterThan(tester.getCenter(find.byKey(_takeawayKey)).dx),
        );
      }
    });

    testWidgets('001-D4. English lays out LEFT-to-right with Dine-in first', (
      tester,
    ) async {
      await _pump(tester);
      expect(
        Directionality.of(tester.element(find.byKey(_dineInKey))),
        TextDirection.ltr,
      );
      expect(
        tester.getCenter(find.byKey(_dineInKey)).dx,
        lessThan(tester.getCenter(find.byKey(_takeawayKey)).dx),
      );
    });
  });
}
