import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show kdsTicketViewFromCartLines, kdsTicketViewFromSubmittedOrder;
import 'package:restoflow_pos/src/print/print_document.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/modifier_selection_sheet.dart';
import 'package:restoflow_pos/src/widgets/order_confirmation.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildBillDocument;

/// POS-QUICK-NOTE-CHIPS-001 — DOWNSTREAM parity through the real demo POS.
///
/// The sheet-level tests prove that a note built from removable boxes is the
/// same string `onConfirm` would have handed over for the same typed text.
/// This suite follows that string the rest of the way, through the demo
/// [PosMenuScreen] exactly as a cashier drives it:
///
///  * F1 — the cart line renders the identical `Note: ...` text;
///  * F2 — the outbox payload's `order_items[0]` is identical (and carries no
///    preset id, and no `notes` key at all once the only box was removed);
///  * F3 — reopening a line restores its boxes, X + Save changes ONLY the note
///    (same line, same money);
///  * F4 — the kitchen ticket views, the customer bill and the on-screen order
///    confirmation carry the identical note line.
///
/// Every comparison is between the box path (tap `No onions`, tap
/// `Extra crispy`) and the typed path (type `No onions, Extra crispy` by hand),
/// each in its own fresh POS, with the same Cheeseburger configuration
/// (Medium + Cheese, ₪48 + ₪3 = 5100 minor units).

const Key _noteKey = Key('modifier-item-note');
const Key _confirmKey = Key('modifier-add-button');
const Key _warningKey = Key('quick-note-limit-warning');

/// The demo presets this suite taps (pinned against [kDemoQuickNotePresets]
/// by the first test, so a renamed demo preset fails loudly here).
const String _onionsId = 'qn-no-onions';
const String _crispyId = 'qn-extra-crispy';
const String _onions = 'No onions';
const String _crispy = 'Extra crispy';

/// What the cashier would have typed to get the same note before this ticket.
const String _combined = 'No onions, Extra crispy';

/// Medium (free, required Doneness) + Cheese (+₪3.00) on a ₪48.00 burger.
const int _burgerTotalMinor = 5100;

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// Pumps a FRESH demo POS (a new [ProviderScope] every call, so a second call
/// in the same test starts from an empty cart and an empty outbox) and returns
/// the outbox it writes to.
Future<DemoOutboxStore> _pumpPos(WidgetTester tester) async {
  final store = DemoOutboxStore(delay: (_) async {});
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [outboxRepositoryProvider.overrideWithValue(store)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosMenuScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(PosMenuScreen)),
  listen: false,
);

CartViewState _cart(WidgetTester tester) =>
    _container(tester).read(cartControllerProvider);

/// Scrolls [finder] into the sheet body's viewport.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

/// Opens the Cheeseburger sheet from its menu card and configures it as
/// Medium + Cheese, so the add is enabled and carries a paid modifier.
Future<void> _openConfiguredBurger(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.widgetWithText(Card, 'Cheeseburger').first,
      matching: find.byIcon(Icons.add_shopping_cart),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(ModifierSelectionSheet), findsOneWidget);
  await tester.tap(
    find.byKey(const ValueKey('modifier-option-demo-opt-medium')),
  );
  await tester.tap(
    find.byKey(const ValueKey('modifier-option-demo-opt-cheese')),
  );
  await tester.pump();
}

Finder _bandChip(String presetId) =>
    find.byKey(Key('quick-note-chip-$presetId'));

Finder _token(String presetId) => find.byKey(Key('quick-note-token-$presetId'));

Finder _tokenRemove(String presetId) =>
    find.byKey(Key('quick-note-token-remove-$presetId'));

Future<void> _tapChip(WidgetTester tester, String presetId) async {
  await _reveal(tester, _bandChip(presetId));
  await tester.tap(_bandChip(presetId));
  await tester.pumpAndSettle();
}

Future<void> _removeToken(WidgetTester tester, String presetId) async {
  await _reveal(tester, _tokenRemove(presetId));
  await tester.tap(_tokenRemove(presetId));
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester) async {
  await _reveal(tester, find.byKey(_confirmKey));
  await tester.tap(find.byKey(_confirmKey));
  await tester.pumpAndSettle();
  expect(find.byType(ModifierSelectionSheet), findsNothing);
}

String _noteFieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_noteKey)).controller!.text;

bool _bandChipEnabled(WidgetTester tester, String presetId) =>
    tester.widget<ActionChip>(_bandChip(presetId)).onPressed != null;

/// THE BOX PATH: the two demo presets tapped in order, nothing typed.
Future<void> _addBurgerViaBoxes(WidgetTester tester) async {
  await _openConfiguredBurger(tester);
  await _tapChip(tester, _onionsId);
  await _tapChip(tester, _crispyId);
  // Sanity: they really are boxes, and the field really is empty — otherwise
  // this would be a second typed path, not the box path.
  expect(_token(_onionsId), findsOneWidget);
  expect(_token(_crispyId), findsOneWidget);
  expect(_noteFieldText(tester), isEmpty);
  expect(find.byKey(_warningKey), findsNothing);
  await _confirm(tester);
}

/// THE TYPED PATH: the same phrases typed by hand, no box touched.
Future<void> _addBurgerViaTyping(WidgetTester tester) async {
  await _openConfiguredBurger(tester);
  await _reveal(tester, find.byKey(_noteKey));
  await tester.enterText(find.byKey(_noteKey), _combined);
  await tester.pumpAndSettle();
  expect(_token(_onionsId), findsNothing);
  expect(_token(_crispyId), findsNothing);
  await _confirm(tester);
}

/// Every rendered `Note: ...` text under [scope] (or anywhere).
List<String> _renderedNoteTexts(
  WidgetTester tester,
  AppLocalizations l10n, {
  Finder? scope,
}) {
  final prefix = '${l10n.posItemNoteLabel}: ';
  final matcher = find.byWidgetPredicate(
    (w) => w is Text && (w.data?.startsWith(prefix) ?? false),
  );
  final finder = scope == null
      ? matcher
      : find.descendant(of: scope, matching: matcher);
  return [for (final e in finder.evaluate()) (e.widget as Text).data!];
}

/// Sends the current cart through the real Send action and returns the ONE
/// outbox entry's payload JSON plus the submit-time snapshot the receipt and
/// the kitchen reprint are built from.
Future<({String payloadJson, SubmittedOrderView submitted})> _send(
  WidgetTester tester,
  AppLocalizations l10n,
  DemoOutboxStore store,
) async {
  final container = _container(tester);
  await tester.tap(find.text(l10n.posSendOrder));
  await tester.pumpAndSettle();
  final entries = await store.recentEntries();
  expect(entries, hasLength(1));
  final submitted = container.read(cartControllerProvider).submittedOrder;
  expect(submitted, isNotNull);
  return (payloadJson: entries.single.payloadJson, submitted: submitted!);
}

Map<String, dynamic> _firstItem(String payloadJson) {
  final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
  final items = (payload['order_items'] as List).cast<Map<String, dynamic>>();
  expect(items, hasLength(1));
  return items.first;
}

/// The note line(s) of the customer bill built from [submitted].
List<String> _billNoteLines(
  AppLocalizations l10n,
  SubmittedOrderView submitted,
) {
  final prefix = '${l10n.posItemNoteLabel}: ';
  return [
    for (final line in buildBillDocument(l10n, submitted).lines)
      if (line.kind == PrintLineKind.sub &&
          (line.left?.startsWith(prefix) ?? false))
        line.left!,
  ];
}

void main() {
  test('F0. the demo presets this suite taps exist, labelled as assumed, '
      'inside the collapsed band', () {
    PosQuickNotePreset byId(String id) =>
        kDemoQuickNotePresets.singleWhere((p) => p.id == id);
    expect(byId(_onionsId).label, _onions);
    expect(byId(_crispyId).label, _crispy);
    // Both sit in the first eight by display order, so no "more" tap is
    // needed to reach them.
    final ordered = [...kDemoQuickNotePresets]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    final shown = ordered.take(8).map((p) => p.id).toList();
    expect(shown, containsAll(<String>[_onionsId, _crispyId]));
    // The typed text the parity compares against is the canonical join.
    expect(_combined, '$_onions, $_crispy');
  });

  group('F1. cart tile parity', () {
    testWidgets('boxes and typing render the identical cart-line note', (
      tester,
    ) async {
      final l10n = await _en();
      final expected = '${l10n.posItemNoteLabel}: $_combined';

      // The box path.
      await _pumpPos(tester);
      await _addBurgerViaBoxes(tester);
      final viaBoxesLine = _cart(tester).lines.single;
      final viaBoxesRendered = _renderedNoteTexts(tester, l10n);
      expect(find.text(expected), findsOneWidget);

      // The typed path, in a fresh POS.
      await _pumpPos(tester);
      expect(_cart(tester).lines, isEmpty);
      await _addBurgerViaTyping(tester);
      final viaTypingLine = _cart(tester).lines.single;
      final viaTypingRendered = _renderedNoteTexts(tester, l10n);
      expect(find.text(expected), findsOneWidget);

      // The cart state holds the same note string...
      expect(viaBoxesLine.note, _combined);
      expect(viaBoxesLine.note!.codeUnits, viaTypingLine.note!.codeUnits);
      // ...and the tile renders it byte-for-byte the same, exactly once.
      expect(viaBoxesRendered, [expected]);
      expect(viaTypingRendered, [expected]);
      expect(
        viaBoxesRendered.single.codeUnits,
        viaTypingRendered.single.codeUnits,
      );
      // The rest of the line is untouched by how the note was entered.
      expect(viaBoxesLine.lineTotalMinor, _burgerTotalMinor);
      expect(viaBoxesLine.lineTotalMinor, viaTypingLine.lineTotalMinor);
      expect(viaBoxesLine.quantity, viaTypingLine.quantity);
    });
  });

  group('F2. outbox payload parity', () {
    testWidgets('order_items[0] is identical for boxes and typing, and the '
        'payload carries no preset id', (tester) async {
      final l10n = await _en();

      final boxesStore = await _pumpPos(tester);
      await _addBurgerViaBoxes(tester);
      final viaBoxes = await _send(tester, l10n, boxesStore);

      final typingStore = await _pumpPos(tester);
      await _addBurgerViaTyping(tester);
      final viaTyping = await _send(tester, l10n, typingStore);

      final boxesItem = _firstItem(viaBoxes.payloadJson);
      final typingItem = _firstItem(viaTyping.payloadJson);

      expect(boxesItem['notes'], _combined);
      expect(
        (boxesItem['notes'] as String).codeUnits,
        (typingItem['notes'] as String).codeUnits,
      );
      // Not just the note: the WHOLE item (name/price snapshots, modifiers,
      // prep, line total) is the same — the box path adds nothing to the wire.
      expect(boxesItem, equals(typingItem));
      expect(boxesItem['line_total_minor'], _burgerTotalMinor);

      // No preset identity ever leaves the sheet.
      for (final json in [viaBoxes.payloadJson, viaTyping.payloadJson]) {
        expect(json, isNot(contains('qn-')));
        expect(json, isNot(contains(_onionsId)));
        expect(json, isNot(contains(_crispyId)));
      }
    });

    testWidgets('a box added then removed, with nothing typed, sends NO notes '
        'key', (tester) async {
      final l10n = await _en();
      final store = await _pumpPos(tester);
      await _openConfiguredBurger(tester);
      await _tapChip(tester, _onionsId);
      expect(_token(_onionsId), findsOneWidget);
      await _removeToken(tester, _onionsId);
      expect(_token(_onionsId), findsNothing);
      expect(_noteFieldText(tester), isEmpty);
      await _confirm(tester);

      // The cart line has no note, and the tile shows none.
      expect(_cart(tester).lines.single.note, isNull);
      expect(_renderedNoteTexts(tester, l10n), isEmpty);

      final sent = await _send(tester, l10n, store);
      final item = _firstItem(sent.payloadJson);
      expect(item.containsKey('notes'), isFalse);
      expect(item['line_total_minor'], _burgerTotalMinor);
      expect(sent.payloadJson, isNot(contains('qn-')));
      expect(sent.payloadJson, isNot(contains(_onions)));
      expect(sent.submitted.lines.single.note, isNull);
    });
  });

  group('F3. edit: X then Save', () {
    testWidgets('reopening restores both boxes; removing one and saving '
        'changes only the note — same line, same money', (tester) async {
      final l10n = await _en();
      final store = await _pumpPos(tester);
      await _addBurgerViaBoxes(tester);
      final before = _cart(tester).lines.single;
      expect(before.note, _combined);
      expect(before.lineTotalMinor, _burgerTotalMinor);
      final subtotalBefore = _cart(tester).subtotalMinor;

      await tester.tap(find.byKey(Key('cart-edit-${before.lineId}')));
      await tester.pumpAndSettle();
      expect(find.byType(ModifierSelectionSheet), findsOneWidget);

      // The stored note came back as the two boxes, in note order, with an
      // empty field — not as text in the field.
      await _reveal(tester, _token(_crispyId));
      expect(_token(_onionsId), findsOneWidget);
      expect(_token(_crispyId), findsOneWidget);
      expect(
        tester.getTopLeft(_token(_onionsId)).dx,
        lessThan(tester.getTopLeft(_token(_crispyId)).dx),
      );
      expect(_noteFieldText(tester), isEmpty);
      // Restored boxes disable their band chips, like freshly added ones.
      expect(_bandChipEnabled(tester, _onionsId), isFalse);
      expect(_bandChipEnabled(tester, _crispyId), isFalse);

      await _removeToken(tester, _crispyId);
      expect(_token(_crispyId), findsNothing);
      expect(_token(_onionsId), findsOneWidget);
      expect(_bandChipEnabled(tester, _crispyId), isTrue);
      expect(_bandChipEnabled(tester, _onionsId), isFalse);

      await _confirm(tester);

      final after = _cart(tester).lines;
      // Edited in place: still one line, the same line.
      expect(after, hasLength(1));
      expect(after.single.lineId, before.lineId);
      // Money untouched.
      expect(after.single.lineTotalMinor, before.lineTotalMinor);
      expect(after.single.lineTotalMinor, _burgerTotalMinor);
      expect(after.single.unitPriceMinor, before.unitPriceMinor);
      expect(after.single.quantity, before.quantity);
      expect(_cart(tester).subtotalMinor, subtotalBefore);
      expect(
        [
          for (final m in after.single.modifiers)
            (m.optionId, m.quantity, m.priceDeltaMinor),
        ],
        [
          for (final m in before.modifiers)
            (m.optionId, m.quantity, m.priceDeltaMinor),
        ],
      );
      // Only the note changed.
      expect(after.single.note, _onions);
      expect(_renderedNoteTexts(tester, l10n), [
        '${l10n.posItemNoteLabel}: $_onions',
      ]);

      // And that is what goes on the wire.
      final sent = await _send(tester, l10n, store);
      final item = _firstItem(sent.payloadJson);
      expect(item['notes'], _onions);
      expect(item['line_total_minor'], _burgerTotalMinor);
      expect(sent.payloadJson, isNot(contains(_crispy)));
      expect(sent.payloadJson, isNot(contains('qn-')));
    });
  });

  group('F4. kitchen and receipt parity', () {
    testWidgets('the kitchen ticket views and the customer bill carry the '
        'identical note for boxes and typing', (tester) async {
      final l10n = await _en();
      final expectedPrintLine = '${l10n.posItemNoteLabel}: $_combined';

      // The box path: kitchen view from the LIVE cart lines (the automatic
      // submit-time ticket), then the submit snapshot (manual reprint + bill).
      final boxesStore = await _pumpPos(tester);
      await _addBurgerViaBoxes(tester);
      final boxesCartTicket = kdsTicketViewFromCartLines(
        orderCode: '#PARITY',
        orderType: OrderType.takeaway,
        lines: _cart(tester).lines,
      );
      final viaBoxes = await _send(tester, l10n, boxesStore);
      final boxesConfirmation = _renderedNoteTexts(
        tester,
        l10n,
        scope: find.byType(OrderConfirmation),
      );

      // The typed path.
      final typingStore = await _pumpPos(tester);
      await _addBurgerViaTyping(tester);
      final typingCartTicket = kdsTicketViewFromCartLines(
        orderCode: '#PARITY',
        orderType: OrderType.takeaway,
        lines: _cart(tester).lines,
      );
      final viaTyping = await _send(tester, l10n, typingStore);
      final typingConfirmation = _renderedNoteTexts(
        tester,
        l10n,
        scope: find.byType(OrderConfirmation),
      );

      // Kitchen ticket from the cart lines (auto print on submit).
      final typedNote = typingCartTicket.items.single.note!;
      expect(typedNote, _combined);
      expect(boxesCartTicket.items.single.note!.codeUnits, typedNote.codeUnits);

      // Kitchen ticket from the submitted snapshot (manual reprint).
      final boxesReprint = kdsTicketViewFromSubmittedOrder(viaBoxes.submitted);
      final typingReprint = kdsTicketViewFromSubmittedOrder(
        viaTyping.submitted,
      );
      expect(typingReprint.items.single.note, _combined);
      expect(
        boxesReprint.items.single.note!.codeUnits,
        typingReprint.items.single.note!.codeUnits,
      );

      // The customer bill's note line (same item loop as the paid receipt).
      final boxesBill = _billNoteLines(l10n, viaBoxes.submitted);
      final typingBill = _billNoteLines(l10n, viaTyping.submitted);
      expect(boxesBill, [expectedPrintLine]);
      expect(typingBill, [expectedPrintLine]);
      expect(boxesBill.single.codeUnits, typingBill.single.codeUnits);

      // The on-screen order confirmation lists the line with the same note on
      // both paths.
      expect(boxesConfirmation, [expectedPrintLine]);
      expect(typingConfirmation, [expectedPrintLine]);
      expect(
        boxesConfirmation.single.codeUnits,
        typingConfirmation.single.codeUnits,
      );
    });
  });
}
