import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/widgets/modifier_selection_sheet.dart';

/// POS-QUICK-NOTES-124 — the cashier-facing half, plus the ORDER PARITY proof.
///
/// The parity group is the release blocker: a note produced by tapping chips
/// must be byte-identical to the same note typed by hand, all the way through
/// to what `onConfirm` hands the cart. If those two ever differ, quick notes
/// have quietly become a second note system — which is exactly what this
/// feature is not allowed to be.
///
/// POS-QUICK-NOTE-CHIPS-001: a tap now adds a removable box under the field
/// instead of writing into it, so the B group and D3 assert the boxes and the
/// note `onConfirm` hands the cart rather than the field's text. D1, D2 and D4
/// — the byte parity — are unchanged.

const Key _noteKey = Key('modifier-item-note');
const Key _chipsKey = Key('modifier-quick-notes');
const Key _chipsRowKey = Key('modifier-quick-notes-row');
const Key _moreKey = Key('quick-note-more');
const Key _warningKey = Key('quick-note-limit-warning');
const Key _confirmKey = Key('modifier-add-button');

DemoMenuItem _item() => const DemoMenuItem(
  id: 'item-a',
  name: 'Burger',
  priceMinor: 4000,
  categoryId: 'burgers',
  categoryName: 'Burgers',
);

/// One OPTIONAL group, so confirm is enabled without a selection: these tests
/// are about the note, not the selection rules.
List<PosModifierGroup> _groups() => <PosModifierGroup>[
  const PosModifierGroup(
    id: 'g-0',
    menuItemId: 'item-a',
    name: 'Extras',
    options: [
      PosModifierOption(id: 'opt-0', name: 'Cheese', priceDeltaMinor: 300),
    ],
  ),
];

List<PosQuickNotePreset> _presets(int n) => [
  for (var i = 0; i < n; i++)
    PosQuickNotePreset(id: 'q$i', label: 'Note $i', displayOrder: i),
];

/// The two phrases the parity proof composes, in both directions.
const _first = 'No onions';
const _second = 'Extra crispy';
const _combined = 'No onions, Extra crispy';

List<PosQuickNotePreset> _parityPresets() => const [
  PosQuickNotePreset(id: 'p1', label: _first, displayOrder: 0),
  PosQuickNotePreset(id: 'p2', label: _second, displayOrder: 1),
];

/// Opens the sheet through the REAL modal route, so the route constraints,
/// height cap and viewInsets are authentic.
Future<List<({List<SelectedModifier> selections, String? note, int quantity})>>
_openSheet(
  WidgetTester tester, {
  required List<PosQuickNotePreset> quickNotes,
  Size size = const Size(900, 1200),
  Locale locale = const Locale('en'),
  String? initialNote,
}) async {
  final confirmed =
      <({List<SelectedModifier> selections, String? note, int quantity})>[];
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
                item: _item(),
                groups: _groups(),
                currencyCode: 'ILS',
                quickNotes: quickNotes,
                initialNote: initialNote,
                onConfirm: (selections, note, quantity) => confirmed.add((
                  selections: selections,
                  note: note,
                  quantity: quantity,
                )),
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
  return confirmed;
}

/// Scrolls [finder] into the sheet body's viewport (the note band sits at the
/// end of the body, below the option groups).
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

String _noteText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_noteKey)).controller!.text;

Future<void> _tapChip(WidgetTester tester, String presetId) async {
  final chip = find.byKey(Key('quick-note-chip-$presetId'));
  await _reveal(tester, chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

/// POS-QUICK-NOTE-CHIPS-001 — the box an added preset becomes, and its X.
Finder _token(String presetId) => find.byKey(Key('quick-note-token-$presetId'));

Future<void> _removeToken(WidgetTester tester, String presetId) async {
  final remove = find.byKey(Key('quick-note-token-remove-$presetId'));
  await _reveal(tester, remove);
  await tester.tap(remove);
  await tester.pumpAndSettle();
}

/// Confirms the sheet and returns the note it handed the cart.
Future<String?> _confirmNote(
  WidgetTester tester,
  List<({List<SelectedModifier> selections, String? note, int quantity})>
  confirmed,
) async {
  await _reveal(tester, find.byKey(_confirmKey));
  await tester.tap(find.byKey(_confirmKey));
  await tester.pumpAndSettle();
  return confirmed.single.note;
}

void main() {
  group('A. presence and absence', () {
    testWidgets('A1. no presets => the note UI is EXACTLY as before', (
      tester,
    ) async {
      await _openSheet(tester, quickNotes: const []);
      await _reveal(tester, find.byKey(_noteKey));
      expect(find.byKey(_noteKey), findsOneWidget);
      // Not merely empty — the whole band is absent, so the note row keeps its
      // previous position and the sheet gains no height.
      expect(find.byKey(_chipsRowKey), findsNothing);
      expect(find.byKey(_chipsKey), findsNothing);
    });

    testWidgets('A2. presets render in display order, above the note', (
      tester,
    ) async {
      await _openSheet(tester, quickNotes: _presets(3));
      await _reveal(tester, find.byKey(_chipsKey));
      expect(find.byKey(_chipsKey), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(Key('quick-note-chip-q$i')), findsOneWidget);
      }
      // Order on screen follows display order...
      final xs = [
        for (var i = 0; i < 3; i++)
          tester.getTopLeft(find.byKey(Key('quick-note-chip-q$i'))).dx,
      ];
      expect(xs[0], lessThan(xs[1]));
      expect(xs[1], lessThan(xs[2]));
      // ...and the band sits ABOVE the field it fills.
      await _reveal(tester, find.byKey(_noteKey));
      expect(
        tester.getTopLeft(find.byKey(_chipsRowKey)).dy,
        lessThan(tester.getTopLeft(find.byKey(_noteKey)).dy),
      );
    });

    testWidgets('A3. exactly eight presets show with no "more" control', (
      tester,
    ) async {
      await _openSheet(tester, quickNotes: _presets(8));
      await _reveal(tester, find.byKey(_chipsKey));
      expect(find.byKey(Key('quick-note-chip-q7')), findsOneWidget);
      expect(find.byKey(_moreKey), findsNothing);
    });

    testWidgets('A4. past eight, the extras hide behind "more"', (
      tester,
    ) async {
      await _openSheet(tester, quickNotes: _presets(12));
      await _reveal(tester, find.byKey(_chipsKey));
      expect(find.byKey(Key('quick-note-chip-q7')), findsOneWidget);
      expect(find.byKey(Key('quick-note-chip-q8')), findsNothing);
      expect(find.byKey(_moreKey), findsOneWidget);
    });

    testWidgets('A5. "more" reveals every preset in the same band', (
      tester,
    ) async {
      await _openSheet(tester, quickNotes: _presets(12));
      await _reveal(tester, find.byKey(_moreKey));
      await tester.tap(find.byKey(_moreKey));
      await tester.pumpAndSettle();
      await _reveal(tester, find.byKey(_chipsKey));
      for (var i = 0; i < 12; i++) {
        expect(
          find.byKey(Key('quick-note-chip-q$i')),
          findsOneWidget,
          reason: 'preset q$i should be visible after expanding',
        );
      }
      expect(find.byKey(_moreKey), findsNothing);
    });

    testWidgets('A6. a chip is a real touch target (>= 44dp)', (tester) async {
      await _openSheet(tester, quickNotes: _presets(3));
      await _reveal(tester, find.byKey(_chipsKey));
      final size = tester.getSize(find.byKey(const Key('quick-note-chip-q0')));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  group('B. insertion through the real widget', () {
    testWidgets('B1. tapping a chip adds a box and leaves the field empty', (
      tester,
    ) async {
      final confirmed = await _openSheet(tester, quickNotes: _parityPresets());
      await _tapChip(tester, 'p1');
      expect(_token('p1'), findsOneWidget);
      expect(_noteText(tester), isEmpty);
      expect(await _confirmNote(tester, confirmed), _first);
    });

    testWidgets('B2. a second chip joins with the canonical separator', (
      tester,
    ) async {
      final confirmed = await _openSheet(tester, quickNotes: _parityPresets());
      await _tapChip(tester, 'p1');
      await _tapChip(tester, 'p2');
      expect(_token('p1'), findsOneWidget);
      expect(_token('p2'), findsOneWidget);
      expect(
        (await _confirmNote(tester, confirmed))!.codeUnits,
        _combined.codeUnits,
      );
    });

    testWidgets('B3. a chip tap leaves the typed text and caret untouched', (
      tester,
    ) async {
      await _openSheet(tester, quickNotes: _parityPresets());
      await _reveal(tester, find.byKey(_noteKey));
      await tester.enterText(find.byKey(_noteKey), 'well done');
      await tester.pumpAndSettle();
      final controller = tester
          .widget<TextField>(find.byKey(_noteKey))
          .controller!;
      final before = controller.value;
      await _tapChip(tester, 'p1');
      expect(controller.value, before);
    });

    testWidgets('B4. manual editing next to a chip still works', (
      tester,
    ) async {
      final confirmed = await _openSheet(tester, quickNotes: _parityPresets());
      await _tapChip(tester, 'p1');
      await tester.enterText(find.byKey(_noteKey), 'typed over');
      await tester.pumpAndSettle();
      expect(_noteText(tester), 'typed over');
      // Typing never touches the box.
      expect(_token('p1'), findsOneWidget);
      // Clearing it restores the ordinary empty-note behaviour.
      await tester.enterText(find.byKey(_noteKey), '');
      await tester.pumpAndSettle();
      expect(_noteText(tester), isEmpty);
      await tester.enterText(find.byKey(_noteKey), 'typed over');
      await tester.pumpAndSettle();
      expect(await _confirmNote(tester, confirmed), 'typed over, $_first');
    });

    testWidgets('B5. a chip joins onto text the cashier typed', (tester) async {
      final confirmed = await _openSheet(tester, quickNotes: _parityPresets());
      await _reveal(tester, find.byKey(_noteKey));
      await tester.enterText(find.byKey(_noteKey), _first);
      await tester.pumpAndSettle();
      await _tapChip(tester, 'p2');
      // The field keeps only what was typed; the note joins both.
      expect(_noteText(tester), _first);
      expect(
        (await _confirmNote(tester, confirmed))!.codeUnits,
        _combined.codeUnits,
      );
    });

    testWidgets('B6. an over-long tap is refused, inline, changing nothing', (
      tester,
    ) async {
      await _openSheet(tester, quickNotes: _parityPresets());
      await _reveal(tester, find.byKey(_noteKey));
      final long = 'x' * 138;
      await tester.enterText(find.byKey(_noteKey), long);
      await tester.pumpAndSettle();
      await _tapChip(tester, 'p1');
      // Refused: the note is untouched, and nothing was truncated to fit.
      expect(_noteText(tester), long);
      expect(_token('p1'), findsNothing);
      expect(find.byKey(_warningKey), findsOneWidget);
    });

    testWidgets('B7. the warning clears as soon as the note changes', (
      tester,
    ) async {
      await _openSheet(tester, quickNotes: _parityPresets());
      await _reveal(tester, find.byKey(_noteKey));
      await tester.enterText(find.byKey(_noteKey), 'x' * 138);
      await tester.pumpAndSettle();
      await _tapChip(tester, 'p1');
      expect(find.byKey(_warningKey), findsOneWidget);
      await tester.enterText(find.byKey(_noteKey), 'short');
      await tester.pumpAndSettle();
      expect(find.byKey(_warningKey), findsNothing);
      // ...and also when the note changes by a box going away.
      await tester.enterText(find.byKey(_noteKey), 'x' * 125);
      await tester.pumpAndSettle();
      await _tapChip(tester, 'p1');
      await _tapChip(tester, 'p2');
      expect(find.byKey(_warningKey), findsOneWidget);
      await _removeToken(tester, 'p1');
      expect(find.byKey(_warningKey), findsNothing);
    });

    testWidgets('B8. tapping a chip never confirms the sheet', (tester) async {
      final confirmed = await _openSheet(tester, quickNotes: _parityPresets());
      await _tapChip(tester, 'p1');
      expect(confirmed, isEmpty);
      expect(find.byType(ModifierSelectionSheet), findsOneWidget);
    });
  });

  group('C. layout', () {
    testWidgets('C1. an Arabic locale lays the band out right-to-left', (
      tester,
    ) async {
      await _openSheet(
        tester,
        quickNotes: _presets(3),
        locale: const Locale('ar'),
      );
      await _reveal(tester, find.byKey(_chipsKey));
      // Ambient direction — nothing is force-fed a textDirection, so the first
      // preset sits on the RIGHT.
      expect(
        Directionality.of(tester.element(find.byKey(_chipsKey))),
        TextDirection.rtl,
      );
      final first = tester
          .getTopLeft(find.byKey(const Key('quick-note-chip-q0')))
          .dx;
      final second = tester
          .getTopLeft(find.byKey(const Key('quick-note-chip-q1')))
          .dx;
      expect(first, greaterThan(second));
    });

    testWidgets('C2. a 360dp-wide sheet wraps instead of overflowing', (
      tester,
    ) async {
      await _openSheet(
        tester,
        quickNotes: _presets(12),
        size: const Size(360, 900),
      );
      await _reveal(tester, find.byKey(_chipsKey));
      expect(tester.takeException(), isNull);
      // Genuinely wrapped: the band is taller than a single chip row.
      final band = tester.getSize(find.byKey(_chipsKey));
      final chip = tester.getSize(find.byKey(const Key('quick-note-chip-q0')));
      expect(band.height, greaterThan(chip.height));
      expect(band.width, lessThanOrEqualTo(360));
    });

    testWidgets('C3. the band stays reachable with the keyboard up', (
      tester,
    ) async {
      await _openSheet(
        tester,
        quickNotes: _presets(3),
        size: const Size(1280, 800),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 460);
      await tester.pumpAndSettle();
      // It scrolls with the body rather than being clipped away.
      await _reveal(tester, find.byKey(_chipsKey));
      expect(find.byKey(_chipsKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('D. ORDER PARITY — the release blocker', () {
    testWidgets('D1. chips and typing produce the SAME note bytes', (
      tester,
    ) async {
      // The quick-note path.
      final viaChips = await _openSheet(tester, quickNotes: _parityPresets());
      await _tapChip(tester, 'p1');
      await _tapChip(tester, 'p2');
      await _reveal(tester, find.byKey(_confirmKey));
      await tester.tap(find.byKey(_confirmKey));
      await tester.pumpAndSettle();

      // The manual path, through the very same sheet with NO presets at all.
      final viaTyping = await _openSheet(tester, quickNotes: const []);
      await _reveal(tester, find.byKey(_noteKey));
      await tester.enterText(find.byKey(_noteKey), _combined);
      await tester.pumpAndSettle();
      await _reveal(tester, find.byKey(_confirmKey));
      await tester.tap(find.byKey(_confirmKey));
      await tester.pumpAndSettle();

      expect(viaChips.single.note, _combined);
      expect(viaTyping.single.note, _combined);
      // Byte-for-byte, not merely "equal after trimming".
      expect(viaChips.single.note!.codeUnits, viaTyping.single.note!.codeUnits);
    });

    testWidgets('D2. the chip path carries no extra payload', (tester) async {
      final confirmed = await _openSheet(tester, quickNotes: _parityPresets());
      await _tapChip(tester, 'p1');
      await _reveal(tester, find.byKey(_confirmKey));
      await tester.tap(find.byKey(_confirmKey));
      await tester.pumpAndSettle();
      final result = confirmed.single;
      // Exactly what the sheet has always returned: selections, a note string,
      // a quantity. No preset id, no marker, nothing new.
      expect(result.note, _first);
      expect(result.selections, isEmpty);
      expect(result.quantity, 1);
      expect(result.note!.contains('p1'), isFalse);
    });

    testWidgets('D3. a chip-only note that is then cleared submits as null', (
      tester,
    ) async {
      final confirmed = await _openSheet(tester, quickNotes: _parityPresets());
      await _tapChip(tester, 'p1');
      await _removeToken(tester, 'p1');
      await tester.enterText(find.byKey(_noteKey), '   ');
      await tester.pumpAndSettle();
      // The EXISTING trim-and-null rule, unchanged: whitespace is not a note.
      expect(await _confirmNote(tester, confirmed), isNull);
    });

    testWidgets('D3b. whitespace typed next to a chip adds nothing to it', (
      tester,
    ) async {
      final confirmed = await _openSheet(tester, quickNotes: _parityPresets());
      await _tapChip(tester, 'p1');
      await tester.enterText(find.byKey(_noteKey), '   ');
      await tester.pumpAndSettle();
      expect(await _confirmNote(tester, confirmed), _first);
    });

    testWidgets('D4. an edit prefilled with a note appends, never replaces', (
      tester,
    ) async {
      final confirmed = await _openSheet(
        tester,
        quickNotes: _parityPresets(),
        initialNote: _first,
      );
      await _tapChip(tester, 'p2');
      await _reveal(tester, find.byKey(_confirmKey));
      await tester.tap(find.byKey(_confirmKey));
      await tester.pumpAndSettle();
      expect(confirmed.single.note, _combined);
    });
  });
}
