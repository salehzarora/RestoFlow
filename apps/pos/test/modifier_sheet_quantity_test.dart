import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenMeat, KitchenPrepComponent, OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/format/money_format.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show kdsTicketViewFromCartLines;
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/widgets/modifier_selection_sheet.dart';
import 'package:restoflow_pos/src/widgets/quantity_stepper.dart';

/// POS-MODIFIER-SHEET-QUANTITY-003 — the cashier picks HOW MANY of a configured
/// product to add, from inside the modifier sheet, BEFORE pressing Add.
///
/// The cart line model has always carried a quantity; what was missing was any
/// way to choose it at configuration time. The cashier had to add the item and
/// then tap the cart's plus button N−1 times, which is slow at a counter and
/// invites mistakes on a busy till.
///
/// The contract pinned here: ONE configured line carrying quantity N — never N
/// add-calls, never N duplicate lines — with the selections, note and frozen
/// snapshots applying per unit, and the money following the authoritative
/// per-unit formula (docs/MONEY_AND_TAX_SPEC.md §9):
///
///   lineTotalMinor = itemQuantity × (basePriceMinor + Σ(delta × modifierQty))
///
/// Every money expectation below is an INDEPENDENT literal, never a value
/// produced by the code under test.

const Key kQtyRow = Key('modifier-item-quantity-row');
const Key kQtyMinus = Key('modifier-item-quantity-decrease');
const Key kQtyValue = Key('modifier-item-quantity-value');
const Key kQtyPlus = Key('modifier-item-quantity-increase');
const Key kNoteKey = Key('modifier-item-note');
const Key kConfirmKey = Key('modifier-add-button');

const int kBase = 4000;
const int kPaidDelta = 500;

const DemoMenuItem kItem = DemoMenuItem(
  id: 'item-a',
  name: 'Burger',
  priceMinor: kBase,
  categoryId: 'burgers',
  categoryName: 'Burgers',
);

/// One OPTIONAL multi group (so confirm is enabled without a selection) holding
/// a free option and a paid one.
List<PosModifierGroup> kGroups = <PosModifierGroup>[
  const PosModifierGroup(
    id: 'g-extras',
    menuItemId: 'item-a',
    name: 'Extras',
    options: [
      PosModifierOption(id: 'opt-free', name: 'Ketchup', priceDeltaMinor: 0),
      PosModifierOption(
        id: 'opt-paid',
        name: 'Cheese',
        priceDeltaMinor: kPaidDelta,
      ),
    ],
  ),
];

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

ProviderContainer _container() {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

CartController _cartOf(ProviderContainer c) =>
    c.read(cartControllerProvider.notifier);
CartViewState _viewOf(ProviderContainer c) => c.read(cartControllerProvider);

SelectedModifier _mod(int delta, {int quantity = 1, String? id}) =>
    SelectedModifier(
      optionId: id ?? 'opt-$delta',
      groupName: 'Extras',
      optionName: 'Opt$delta',
      priceDeltaMinor: delta,
      quantity: quantity,
      kitchenMeat: const KitchenMeat(quantity: 1, unit: 'patty'),
    );

int _qtyShown(WidgetTester tester) =>
    int.parse(tester.widget<Text>(find.byKey(kQtyValue)).data!);

/// Opens the sheet through the REAL modal route, capturing what confirm hands
/// back so the payload — not just the UI — is pinned.
Future<
  ({
    List<SelectedModifier>? Function() selections,
    String? Function() note,
    int Function() quantity,
    bool Function() confirmed,
  })
>
_openSheet(
  WidgetTester tester, {
  Size size = const Size(1280, 1800),
  Locale locale = const Locale('en'),
  List<SelectedModifier> initialSelections = const <SelectedModifier>[],
  String? initialNote,
  bool isEdit = false,
  int initialQuantity = 1,
  int? displayBasePriceMinor,
  List<PosModifierGroup>? groups,
}) async {
  List<SelectedModifier>? gotSelections;
  String? gotNote;
  var gotQuantity = -1;
  var didConfirm = false;

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('open-sheet'),
              onPressed: () => ModifierSelectionSheet.show(
                context,
                item: kItem,
                groups: groups ?? kGroups,
                currencyCode: 'ILS',
                initialSelections: initialSelections,
                initialNote: initialNote,
                isEdit: isEdit,
                initialQuantity: initialQuantity,
                displayBasePriceMinor: displayBasePriceMinor,
                onConfirm: (selections, note, quantity) {
                  gotSelections = selections;
                  gotNote = note;
                  gotQuantity = quantity;
                  didConfirm = true;
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-sheet')));
  await tester.pumpAndSettle();
  expect(find.byType(ModifierSelectionSheet), findsOneWidget);

  return (
    selections: () => gotSelections,
    note: () => gotNote,
    quantity: () => gotQuantity,
    confirmed: () => didConfirm,
  );
}

Future<void> _tapPlus(WidgetTester tester, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byKey(kQtyPlus));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _tapMinus(WidgetTester tester, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byKey(kQtyMinus));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  group('A. default quantity', () {
    testWidgets('003-A1. a NEW add sheet opens at 1 with a visible value, a '
        'DISABLED minus and an ENABLED plus', (tester) async {
      await _openSheet(tester);

      expect(find.byKey(kQtyRow), findsOneWidget);
      expect(find.byKey(kQtyValue), findsOneWidget);
      expect(_qtyShown(tester), 1);

      // Disabled minus: the stepper must refuse AND look refused.
      expect(
        tester
            .widget<InkResponse>(
              find.descendant(
                of: find.byKey(kQtyMinus),
                matching: find.byType(InkResponse),
              ),
            )
            .onTap,
        isNull,
      );
      expect(
        tester
            .widget<InkResponse>(
              find.descendant(
                of: find.byKey(kQtyPlus),
                matching: find.byType(InkResponse),
              ),
            )
            .onTap,
        isNotNull,
      );
    });

    testWidgets('003-A2. tapping the disabled minus at 1 changes nothing and '
        'never closes or removes anything', (tester) async {
      await _openSheet(tester);
      await _tapMinus(tester, times: 3);

      expect(_qtyShown(tester), 1);
      expect(find.byType(ModifierSelectionSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('B. stepper behaviour', () {
    testWidgets('003-B1. 1 -> 2 -> 3 and back down to 1, one unit per tap', (
      tester,
    ) async {
      await _openSheet(tester);
      expect(_qtyShown(tester), 1);

      await _tapPlus(tester);
      expect(_qtyShown(tester), 2);
      await _tapPlus(tester);
      expect(_qtyShown(tester), 3);

      await _tapMinus(tester);
      expect(_qtyShown(tester), 2);
      await _tapMinus(tester);
      expect(_qtyShown(tester), 1);

      // Floor holds.
      await _tapMinus(tester);
      expect(_qtyShown(tester), 1);
    });

    testWidgets('003-B2. five rapid plus taps apply exactly five increments', (
      tester,
    ) async {
      await _openSheet(tester);
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(kQtyPlus));
      }
      await tester.pumpAndSettle();
      expect(_qtyShown(tester), 6);
    });
  });

  group('C. the displayed total scales with quantity', () {
    testWidgets('003-C1. base-only: 4000 -> 8000 -> 12000', (tester) async {
      final l10n = await _en();
      await _openSheet(tester);

      String money(int minor) => MoneyFormatter.formatMinor(minor, 'ILS');
      Finder addLabel(int minor) =>
          find.text(l10n.posAddToCartWithTotal(ltrIsolate(money(minor))));

      expect(find.text(money(4000)), findsWidgets);
      expect(addLabel(4000), findsOneWidget);

      await _tapPlus(tester);
      expect(addLabel(8000), findsOneWidget);
      await _tapPlus(tester);
      expect(addLabel(12000), findsOneWidget);
    });

    testWidgets('003-C2. a PAID modifier scales exactly once per unit: '
        '3 x (4000 + 500) = 13500', (tester) async {
      final l10n = await _en();
      await _openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('modifier-option-opt-paid')));
      await tester.pumpAndSettle();
      await _tapPlus(tester, times: 2);
      expect(_qtyShown(tester), 3);

      expect(
        find.text(
          l10n.posAddToCartWithTotal(
            ltrIsolate(MoneyFormatter.formatMinor(13500, 'ILS')),
          ),
        ),
        findsOneWidget,
        reason: 'the surcharge must be charged per unit, exactly once each',
      );
    });

    testWidgets('003-C3. a FREE modifier stays free at any quantity', (
      tester,
    ) async {
      final l10n = await _en();
      await _openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('modifier-option-opt-free')));
      await tester.pumpAndSettle();
      await _tapPlus(tester, times: 2);

      expect(
        find.text(
          l10n.posAddToCartWithTotal(
            ltrIsolate(MoneyFormatter.formatMinor(12000, 'ILS')),
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('D. confirming a configured add', () {
    testWidgets('003-D1. confirm at 3 hands back quantity 3 ONCE, with the '
        'selections and note intact', (tester) async {
      final captured = await _openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('modifier-option-opt-paid')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(kNoteKey), 'بدون بصل');
      await tester.pumpAndSettle();
      await _tapPlus(tester, times: 2);

      await tester.ensureVisible(find.byKey(kConfirmKey));
      await tester.tap(find.byKey(kConfirmKey));
      await tester.pumpAndSettle();

      expect(captured.confirmed(), isTrue);
      expect(captured.quantity(), 3);
      expect(captured.note(), 'بدون بصل');
      expect(find.byType(ModifierSelectionSheet), findsNothing);
    });

    test('003-D2. addItemWithModifiers(quantity: 3) creates ONE configured '
        'line of quantity 3 — never three lines, never three add calls', () {
      final c = _container();
      _cartOf(c).addItemWithModifiers(kItem, [_mod(kPaidDelta)], quantity: 3);

      final lines = _viewOf(c).lines;
      expect(lines.length, 1);
      expect(lines.single.quantity, 3);
      // 3 × (4000 + 500) — an independent literal.
      expect(lines.single.lineTotalMinor, 13500);
    });

    test('003-D3. the note and modifier snapshots survive the quantity', () {
      final c = _container();
      _cartOf(c).addItemWithModifiers(
        kItem,
        [_mod(kPaidDelta)],
        note: '  بدون بصل  ',
        quantity: 2,
      );

      final line = _viewOf(c).lines.single;
      expect(line.quantity, 2);
      expect(line.note, 'بدون بصل', reason: 'trimming is unchanged');
      expect(line.modifiers.single.priceDeltaMinor, kPaidDelta);
      expect(line.lineTotalMinor, 9000);
    });

    test(
      '003-D4. quantity below 1 is rejected by the existing domain rule',
      () {
        final c = _container();
        expect(
          () => _cartOf(c).addItemWithModifiers(kItem, [_mod(0)], quantity: 0),
          throwsA(anything),
        );
        expect(_viewOf(c).lines, isEmpty);
      },
    );
  });

  group('E. merge / line-identity policy is unchanged', () {
    test('003-E1. two configured adds of the SAME product stay two lines even '
        'when both carry a quantity', () {
      final c = _container();
      _cartOf(c).addItemWithModifiers(kItem, [_mod(kPaidDelta)], quantity: 2);
      _cartOf(c).addItemWithModifiers(kItem, [_mod(kPaidDelta)], quantity: 3);

      final lines = _viewOf(c).lines;
      expect(lines.length, 2, reason: 'configured lines never merge');
      expect(lines[0].quantity, 2);
      expect(lines[1].quantity, 3);
    });

    test('003-E2. same product, different note / different modifiers stay '
        'distinct lines', () {
      final c = _container();
      _cartOf(
        c,
      ).addItemWithModifiers(kItem, [_mod(kPaidDelta)], note: 'a', quantity: 2);
      _cartOf(
        c,
      ).addItemWithModifiers(kItem, [_mod(kPaidDelta)], note: 'b', quantity: 2);
      _cartOf(
        c,
      ).addItemWithModifiers(kItem, [_mod(0, id: 'opt-free')], quantity: 2);
      expect(_viewOf(c).lines.length, 3);
    });

    test('003-E3. a PLAIN add of N merges by N into the existing plain line, '
        'not by one', () {
      final c = _container();
      _cartOf(c).addItem(kItem, quantity: 2);
      expect(_viewOf(c).lines.single.quantity, 2);

      _cartOf(c).addItem(kItem, quantity: 3);
      expect(_viewOf(c).lines.length, 1, reason: 'plain lines still merge');
      expect(_viewOf(c).lines.single.quantity, 5);

      // The default is still one, so every existing caller is unaffected.
      _cartOf(c).addItem(kItem);
      expect(_viewOf(c).lines.single.quantity, 6);
    });

    test('003-E4. a configured add with NO modifiers and NO note still falls '
        'back to the plain path, carrying its quantity', () {
      final c = _container();
      _cartOf(c).addItemWithModifiers(kItem, const [], quantity: 4);
      expect(_viewOf(c).lines.single.quantity, 4);
      expect(_viewOf(c).lines.single.lineTotalMinor, 16000);
    });
  });

  group('F. editing an existing configured line', () {
    testWidgets('003-F1. the sheet PRELOADS the line quantity and can step '
        'from it', (tester) async {
      await _openSheet(tester, isEdit: true, initialQuantity: 4);
      expect(_qtyShown(tester), 4);

      await _tapPlus(tester);
      expect(_qtyShown(tester), 5);
      await _tapMinus(tester, times: 2);
      expect(_qtyShown(tester), 3);
    });

    testWidgets('003-F2. cancelling an edit reports nothing at all', (
      tester,
    ) async {
      final captured = await _openSheet(
        tester,
        isEdit: true,
        initialQuantity: 4,
      );
      await _tapPlus(tester, times: 2);
      await tester.tap(find.byKey(const Key('modifier-close-button')));
      await tester.pumpAndSettle();

      expect(captured.confirmed(), isFalse);
      expect(find.byType(ModifierSelectionSheet), findsNothing);
    });

    test('003-F3. updateLineModifiers(quantity:) keeps the SAME lineId, the '
        'cart position and the frozen base snapshot', () {
      final c = _container();
      _cartOf(c).addItem(kItem); // position 0
      _cartOf(c).addItemWithModifiers(kItem, [_mod(kPaidDelta)], quantity: 2);
      final target = _viewOf(c).lines.last;
      final targetId = target.lineId;
      final frozenUnit = target.unitPriceMinor;

      _cartOf(c).updateLineModifiers(
        targetId,
        [_mod(kPaidDelta)],
        note: 'x',
        quantity: 5,
      );

      final lines = _viewOf(c).lines;
      expect(lines.length, 2, reason: 'never a new line');
      expect(lines.last.lineId, targetId);
      expect(lines.last.quantity, 5);
      expect(
        lines.last.unitPriceMinor,
        frozenUnit,
        reason: 'base stays frozen',
      );
      expect(lines.last.lineTotalMinor, 22500); // 5 × (4000 + 500)
    });

    test('003-F4. omitting quantity on an edit leaves it untouched', () {
      final c = _container();
      _cartOf(c).addItemWithModifiers(kItem, [_mod(kPaidDelta)], quantity: 3);
      final id = _viewOf(c).lines.single.lineId;

      _cartOf(c).updateLineModifiers(id, [_mod(kPaidDelta)], note: 'y');
      expect(_viewOf(c).lines.single.quantity, 3);
    });
  });

  group('G. equivalence with the existing increment path', () {
    test('003-G1. sheet add at quantity 3 == add at 1 then increment twice — '
        'same quantity, same money, same per-unit snapshots', () {
      final direct = _container();
      _cartOf(
        direct,
      ).addItemWithModifiers(kItem, [_mod(kPaidDelta)], note: 'n', quantity: 3);

      final stepped = _container();
      _cartOf(
        stepped,
      ).addItemWithModifiers(kItem, [_mod(kPaidDelta)], note: 'n');
      final id = _viewOf(stepped).lines.single.lineId;
      _cartOf(stepped).increaseQuantity(id);
      _cartOf(stepped).increaseQuantity(id);

      final a = _viewOf(direct).lines.single;
      final b = _viewOf(stepped).lines.single;

      expect(a.quantity, b.quantity);
      expect(a.quantity, 3);
      expect(a.lineTotalMinor, b.lineTotalMinor);
      expect(a.lineTotalMinor, 13500);
      expect(a.note, b.note);
      expect(a.modifiers.length, b.modifiers.length);
      expect(
        a.modifiers.single.priceDeltaMinor,
        b.modifiers.single.priceDeltaMinor,
      );
      // The PER-UNIT modifier quantity is never pre-multiplied by the item
      // quantity — the kitchen multiplies downstream.
      expect(a.modifiers.single.quantity, 1);
      expect(a.modifiers.single.quantity, b.modifiers.single.quantity);
    });
  });

  group('C4. the displayed total is the number the cart line will hold', () {
    testWidgets(
      '003-C4. sheet total at quantity 3 == CartLine.lineTotalMinor',
      (tester) async {
        final l10n = await _en();
        final captured = await _openSheet(tester);

        await tester.tap(
          find.byKey(const ValueKey('modifier-option-opt-paid')),
        );
        await tester.pumpAndSettle();
        await _tapPlus(tester, times: 2);
        // What the cashier READS on the button.
        expect(
          find.text(
            l10n.posAddToCartWithTotal(
              ltrIsolate(MoneyFormatter.formatMinor(13500, 'ILS')),
            ),
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(find.byKey(kConfirmKey));
        await tester.tap(find.byKey(kConfirmKey));
        await tester.pumpAndSettle();

        // What the cart ACTUALLY charges, through the real controller.
        final c = _container();
        _cartOf(c).addItemWithModifiers(
          kItem,
          captured.selections()!,
          note: captured.note(),
          quantity: captured.quantity(),
        );
        expect(_viewOf(c).lines.single.lineTotalMinor, 13500);
      },
    );
  });

  group('F5. the note-only degraded edit', () {
    testWidgets('003-F5. hides the sheet quantity control entirely', (
      tester,
    ) async {
      // groups: [] with stored selections is exactly the degraded path the cart
      // routes to updateLineNote — the sheet must not offer to re-price it.
      await _openSheet(
        tester,
        isEdit: true,
        initialQuantity: 3,
        initialSelections: [_mod(kPaidDelta)],
        groups: const <PosModifierGroup>[],
      );

      expect(
        find.byKey(const Key('modifier-options-unavailable')),
        findsOneWidget,
      );
      expect(find.byKey(kQtyRow), findsNothing);
      expect(find.byKey(kQtyPlus), findsNothing);
      expect(find.byKey(kQtyMinus), findsNothing);
    });
  });

  group('G2. preparation scales downstream, never in the sheet', () {
    test('003-G2. a 240g burger at quantity 3 keeps PER-UNIT snapshots and '
        'yields 3x bread / 3x meat, multiplied exactly once', () {
      // The item's PER-UNIT prep is configured through the real attributes bag
      // (`prep_components`), exactly as the Dashboard writes it.
      const burger = DemoMenuItem(
        id: 'burger-240',
        name: 'Burger 240g',
        priceMinor: kBase,
        categoryId: 'food',
        categoryName: 'Food',
        attributes: {
          'prep_components': [
            {'name': 'خبز', 'quantity': 1},
          ],
        },
      );
      final c = _container();
      _cartOf(c).addItemWithModifiers(burger, const [
        SelectedModifier(
          optionId: 'opt-240',
          groupName: 'Size',
          optionName: '240g',
          priceDeltaMinor: kPaidDelta,
          quantity: 1,
          kitchenMeat: KitchenMeat(quantity: 1, unit: 'قطع لحم'),
        ),
      ], quantity: 3);

      final line = _viewOf(c).lines.single;
      expect(line.quantity, 3);
      // The PER-UNIT snapshots are NOT pre-multiplied by the item quantity.
      expect(line.modifiers.single.quantity, 1);
      expect(line.modifiers.single.kitchenMeat!.quantity, 1);

      final ticket = kdsTicketViewFromCartLines(
        orderCode: '#000042',
        orderType: OrderType.takeaway,
        lines: _viewOf(c).lines,
        prepByItemId: const {
          'burger-240': [KitchenPrepComponent(name: 'خبز', quantity: 1)],
        },
      );

      // The kitchen is told to make THREE.
      expect(ticket.items.single.quantity, 3);
      int countOf(String label) => ticket.kitchenCounts
          .where((k) => k.label == label)
          .fold<num>(0, (a, k) => a + k.quantity)
          .toInt();
      // 1 bun per unit x 3 units; 1 patty per unit x 3 units — multiplied
      // exactly once, downstream.
      expect(countOf('خبز'), 3);
      expect(countOf('قطع لحم'), 3);
    });
  });

  group('I. layout across locales, geometries and the keyboard', () {
    for (final locale in const [Locale('en'), Locale('ar'), Locale('he')]) {
      final code = locale.languageCode;
      testWidgets('003-I1.$code. the quantity row renders and steps in '
          'landscape without overflow', (tester) async {
        await _openSheet(tester, locale: locale, size: const Size(1280, 800));
        expect(find.byKey(kQtyRow), findsOneWidget);
        await _tapPlus(tester);
        expect(_qtyShown(tester), 2);
        expect(tester.takeException(), isNull);
      });

      testWidgets('003-I2.$code. the quantity row survives portrait', (
        tester,
      ) async {
        await _openSheet(tester, locale: locale, size: const Size(800, 1280));
        expect(find.byKey(kQtyRow), findsOneWidget);
        await _tapPlus(tester);
        expect(_qtyShown(tester), 2);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('003-I3. with a Redmi-like keyboard inset the quantity row, '
        'the note and Confirm all stay reachable and the note keeps focus', (
      tester,
    ) async {
      await _openSheet(tester, size: const Size(1280, 800));

      // Focus the note first — the fix from
      // POS-PRODUCT-NOTE-LANDSCAPE-KEYBOARD-002 must still hold.
      await tester.ensureVisible(find.byKey(kNoteKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kNoteKey));
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 460);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(kNoteKey),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.focusNode.hasFocus, isTrue);

      // POS-PHASE1-FOLLOWUP-FIXES-008 moved the quantity band OUT of the
      // sticky footer and into the configuration area under the product
      // header, because a cashier deciding how many to add was having to look
      // to the very bottom of the sheet. It is therefore no longer pinned while
      // the keyboard is up — it is REACHABLE by scrolling the body, which is
      // what this test now proves. Confirm stays pinned and above the keyboard.
      expect(find.byKey(kQtyRow), findsOneWidget);
      await tester.ensureVisible(find.byKey(kQtyPlus));
      await tester.pumpAndSettle();
      await _tapPlus(tester);
      expect(_qtyShown(tester), 2);

      // Nothing overflowed, and the confirm action stays above the keyboard.
      expect(tester.takeException(), isNull);
      const keyboardTop = 800.0 - 460.0;
      expect(
        tester.getRect(find.byKey(kConfirmKey)).bottom,
        lessThanOrEqualTo(keyboardTop),
      );
    });

    for (final locale in const [Locale('en'), Locale('ar'), Locale('he')]) {
      testWidgets('003-I4.${locale.languageCode}. the row label is LOCALIZED, '
          'never hardcoded', (tester) async {
        final l10n = await AppLocalizations.delegate.load(locale);
        await _openSheet(tester, locale: locale);
        expect(
          find.descendant(
            of: find.byKey(kQtyRow),
            matching: find.text(l10n.posModifierQuantityLabel),
          ),
          findsOneWidget,
        );
      });
    }
  });

  group('K. the EXTRACTED stepper keeps the cart line exactly as it was', () {
    // The presentation moved out of cart_panel.dart into a shared POS-local
    // widget. These pin that the move changed nothing the cashier can see or
    // do — including the rule that only the CART's minus removes a line.
    Future<void> pumpStepper(
      WidgetTester tester, {
      required int quantity,
      required bool enableDecrease,
      bool dense = false,
    }) async {
      final l10n = await _en();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: PosQuantityStepper(
              quantity: quantity,
              l10n: l10n,
              dense: dense,
              decreaseKey: const Key('k-minus'),
              valueKey: const Key('k-value'),
              increaseKey: const Key('k-plus'),
              onDecrease: enableDecrease ? () {} : null,
              onIncrease: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    double opacityOf(WidgetTester tester, Key key) => tester
        .widget<Opacity>(
          find.descendant(of: find.byKey(key), matching: find.byType(Opacity)),
        )
        .opacity;

    testWidgets('003-K1. plus is FILLED brand green, minus is neutral white '
        'with a hairline border', (tester) async {
      await pumpStepper(tester, quantity: 2, enableDecrease: true);

      BoxDecoration decorationOf(Key key) =>
          tester
                  .widgetList<Container>(
                    find.descendant(
                      of: find.byKey(key),
                      matching: find.byType(Container),
                    ),
                  )
                  .last
                  .decoration!
              as BoxDecoration;

      final plus = decorationOf(const Key('k-plus'));
      final minus = decorationOf(const Key('k-minus'));
      expect(plus.color, isNot(Colors.white));
      expect(plus.border, isNull);
      expect(minus.color, Colors.white);
      expect(minus.border, isNotNull);
    });

    testWidgets('003-K2. a DISABLED minus is dimmed and refuses the tap; an '
        'enabled one is at full opacity', (tester) async {
      await pumpStepper(tester, quantity: 1, enableDecrease: false);
      expect(opacityOf(tester, const Key('k-minus')), 0.4);
      expect(opacityOf(tester, const Key('k-plus')), 1.0);

      await pumpStepper(tester, quantity: 2, enableDecrease: true);
      expect(opacityOf(tester, const Key('k-minus')), 1.0);
    });

    testWidgets('003-K3. the tap target stays 44dp (40dp dense)', (
      tester,
    ) async {
      await pumpStepper(tester, quantity: 2, enableDecrease: true);
      expect(tester.getSize(find.byKey(const Key('k-plus'))).height, 44.0);
      expect(tester.getSize(find.byKey(const Key('k-minus'))).height, 44.0);

      await pumpStepper(tester, quantity: 2, enableDecrease: true, dense: true);
      expect(tester.getSize(find.byKey(const Key('k-plus'))).height, 40.0);
    });

    testWidgets('003-K4. the REAL cart line still increments, and its minus at '
        'quantity 1 still REMOVES the line', (tester) async {
      final l10n = await _en();
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const PosMenuScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A PLAIN item (no modifier groups) goes straight to the cart.
      await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PosMenuScreen)),
      );
      CartViewState cart() => container.read(cartControllerProvider);
      expect(cart().lines.length, 1);
      expect(cart().lines.single.quantity, 1);

      Finder cartStepperButton(String tooltip) => find.descendant(
        of: find.byType(PosQuantityStepper),
        matching: find.byTooltip(tooltip),
      );

      await tester.tap(cartStepperButton(l10n.posIncreaseQuantity).first);
      await tester.pumpAndSettle();
      expect(cart().lines.single.quantity, 2);

      await tester.tap(cartStepperButton(l10n.posDecreaseQuantity).first);
      await tester.pumpAndSettle();
      expect(cart().lines.single.quantity, 1);

      // The cart's OWN rule, unchanged by the extraction: minus at one removes.
      await tester.tap(cartStepperButton(l10n.posDecreaseQuantity).first);
      await tester.pumpAndSettle();
      expect(cart().lines, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('J. accessibility', () {
    testWidgets('003-J1. plus and minus are semantic BUTTONS with localized '
        'tooltips, and the quantity is announced', (tester) async {
      final handle = tester.ensureSemantics();
      final l10n = await _en();
      await _openSheet(tester);

      expect(find.byTooltip(l10n.posIncreaseQuantity), findsWidgets);
      expect(find.byTooltip(l10n.posDecreaseQuantity), findsWidgets);
      expect(find.text('1'), findsWidgets);
      handle.dispose();
    });
  });
}
