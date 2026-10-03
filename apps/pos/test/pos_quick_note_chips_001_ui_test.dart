import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/widgets/modifier_selection_sheet.dart';
import 'package:restoflow_pos/src/widgets/quick_note_chip.dart';

/// POS-QUICK-NOTE-CHIPS-001 — removable quick-note chips, through the REAL
/// modal route.
///
/// A quick-note tap no longer writes into the item-note field: it adds a
/// removable box under the field, and the sheet folds the boxes onto the typed
/// text only when it confirms. These tests pin what the cashier sees and
/// touches (boxes, their X, the disabled band chip, the length refusal, the
/// typing budget, RTL, the keyboard) AND the single plain note the sheet hands
/// the cart, byte for byte.
///
/// Labels appear twice on screen (band chip + box), so every finder here is a
/// key or a descendant of a keyed box, never a bare `find.text(label)`.

const Key _noteKey = Key('modifier-item-note');
const Key _noteRowKey = Key('modifier-note-row');
const Key _bandRowKey = Key('modifier-quick-notes-row');
const Key _tokensKey = Key('modifier-quick-note-tokens');
const Key _tokensRowKey = Key('modifier-quick-note-tokens-row');
const Key _warningKey = Key('quick-note-limit-warning');
const Key _confirmKey = Key('modifier-add-button');
const Key _openKey = Key('open-sheet');

typedef _Confirmed = ({
  List<SelectedModifier> selections,
  String? note,
  int quantity,
});

const DemoMenuItem _burger = DemoMenuItem(
  id: 'item-a',
  name: 'Burger',
  priceMinor: 4000,
  categoryId: 'burgers',
  categoryName: 'Burgers',
);

/// One small OPTIONAL group: confirm is enabled without a selection, and the
/// sheet stays content-sized on a normal screen.
List<PosModifierGroup> _groups() => const <PosModifierGroup>[
  PosModifierGroup(
    id: 'g-0',
    menuItemId: 'item-a',
    name: 'Extras',
    options: [
      PosModifierOption(id: 'opt-0', name: 'Cheese', priceDeltaMinor: 300),
    ],
  ),
];

const String _first = 'No onions';
const String _second = 'Extra crispy';

const PosQuickNotePreset _p1 = PosQuickNotePreset(
  id: 'p1',
  label: _first,
  displayOrder: 0,
);
const PosQuickNotePreset _p2 = PosQuickNotePreset(
  id: 'p2',
  label: _second,
  displayOrder: 1,
);
const PosQuickNotePreset _p3 = PosQuickNotePreset(
  id: 'p3',
  label: 'Well done',
  displayOrder: 2,
);

const PosQuickNotePreset _p4 = PosQuickNotePreset(
  id: 'p4',
  label: 'Hot',
  displayOrder: 3,
);

const List<PosQuickNotePreset> _pair = <PosQuickNotePreset>[_p1, _p2];

List<PosQuickNotePreset> _numbered(int n) => <PosQuickNotePreset>[
  for (var i = 0; i < n; i++)
    PosQuickNotePreset(id: 'q$i', label: 'Note $i', displayOrder: i),
];

/// Two 60-character Arabic phrases (they fit together: 60 + 2 + 60 = 122) and
/// a third that the 140-character contract must refuse.
const String _arLong1 =
    'بدون بصل وبدون طماطم وبدون خس مع صلصة إضافية على الجانب رجاء';
const String _arLong2 =
    'اللحم مستوي تماما والبطاطا مقرمشة جدا مع ملح قليل وبدون فلفل';
const String _arLong3 =
    'تغليف منفصل لكل صنف مع ملاعق بلاستيكية ومناديل إضافية للطلب';

const List<PosQuickNotePreset> _arabicLong = <PosQuickNotePreset>[
  PosQuickNotePreset(id: 'a1', label: _arLong1, displayOrder: 0),
  PosQuickNotePreset(id: 'a2', label: _arLong2, displayOrder: 1),
  PosQuickNotePreset(id: 'a3', label: _arLong3, displayOrder: 2),
];

/// The host app. The MediaQuery builder is ALWAYS present (scale 1.0 by
/// default), so re-pumping with another text scale keeps the tree shape — and
/// therefore the open route — intact.
Widget _hostApp({
  required Locale locale,
  required double textScale,
  required Widget home,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: restoflowLocalizationsDelegates,
  supportedLocales: kSupportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: home,
);

/// An opened sheet: what it confirmed, and a way to re-pump the SAME host
/// (same route, same sheet state) under another locale / text scale.
class _Harness {
  _Harness(this.tester, this.home, this.confirmed);

  final WidgetTester tester;
  final Widget home;
  final List<_Confirmed> confirmed;

  Future<void> repump({required Locale locale, double textScale = 1.0}) async {
    await tester.pumpWidget(
      _hostApp(locale: locale, textScale: textScale, home: home),
    );
    await tester.pumpAndSettle();
  }
}

void _setView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

/// Opens the sheet through the REAL modal route (`ModifierSelectionSheet.show`),
/// so the route constraints, height cap and viewInsets are authentic.
Future<_Harness> _openSheet(
  WidgetTester tester, {
  List<PosQuickNotePreset> quickNotes = _pair,
  Size size = const Size(900, 1200),
  Locale locale = const Locale('en'),
  String? initialNote,
  List<PosModifierGroup>? groups,
  bool isEdit = false,
  List<SelectedModifier> initialSelections = const <SelectedModifier>[],
  DemoMenuItem item = _burger,
}) async {
  _setView(tester, size);
  final confirmed = <_Confirmed>[];
  final home = Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          key: _openKey,
          onPressed: () => ModifierSelectionSheet.show(
            context,
            item: item,
            groups: groups ?? _groups(),
            currencyCode: 'ILS',
            quickNotes: quickNotes,
            initialNote: initialNote,
            isEdit: isEdit,
            initialSelections: initialSelections,
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
  );
  await tester.pumpWidget(_hostApp(locale: locale, textScale: 1.0, home: home));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(_openKey));
  await tester.pumpAndSettle();
  expect(find.byType(ModifierSelectionSheet), findsOneWidget);
  return _Harness(tester, home, confirmed);
}

/// The sheet pumped DIRECTLY (no route), for the widget-reuse checks that need
/// the parent to hand the same position a different item.
Future<void> _pumpDirect(
  WidgetTester tester, {
  required DemoMenuItem item,
  List<PosQuickNotePreset> quickNotes = _pair,
  Locale locale = const Locale('en'),
  double textScale = 1.0,
  Size size = const Size(1000, 1400),
}) async {
  _setView(tester, size);
  await tester.pumpWidget(
    _hostApp(
      locale: locale,
      textScale: textScale,
      home: Scaffold(
        body: Center(
          child: ModifierSelectionSheet(
            key: const ValueKey('customization'),
            item: item,
            groups: _groups(),
            currencyCode: 'ILS',
            quickNotes: quickNotes,
            onConfirm: (selections, note, quantity) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Scrolls [finder] into the sheet body's viewport.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ModifierSelectionSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Finder _bandChip(String id) => find.byKey(Key('quick-note-chip-$id'));
Finder _token(String id) => find.byKey(Key('quick-note-token-$id'));
Finder _removeButton(String id) =>
    find.byKey(Key('quick-note-token-remove-$id'));

/// The label [Text] inside one box (the X is an [Icon], not a [Text]).
Finder _tokenLabel(String id) =>
    find.descendant(of: _token(id), matching: find.byType(Text));

/// Every box currently under the field.
Finder _allBoxes() => find.descendant(
  of: find.byKey(_tokensKey),
  matching: find.byType(QuickNoteChip),
);

/// The keys of the boxes, in the order the sheet holds them.
List<String> _boxOrder(WidgetTester tester) => <String>[
  for (final child in tester.widget<Wrap>(find.byKey(_tokensKey)).children)
    (child.key! as ValueKey<String>).value,
];

TextField _noteField(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_noteKey));

TextEditingController _controller(WidgetTester tester) =>
    _noteField(tester).controller!;

/// The decoration the field ACTUALLY renders (TextField adds an error here
/// when its own maxLength is exceeded).
InputDecoration _renderedDecoration(WidgetTester tester) => tester
    .widget<InputDecorator>(
      find.descendant(
        of: find.byKey(_noteKey),
        matching: find.byType(InputDecorator),
      ),
    )
    .decoration;

Finder _editable() => find.descendant(
  of: find.byKey(_noteKey),
  matching: find.byType(EditableText),
);

/// Whether box [id] sits on the same Wrap run as box [other] or a later one.
bool _isAfterOrOn(WidgetTester tester, String id, String other) =>
    tester.getRect(_token(id)).top >= tester.getRect(_token(other)).top - 0.5;

bool _bandChipEnabled(WidgetTester tester, String id) =>
    tester.widget<ActionChip>(_bandChip(id)).onPressed != null;

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ModifierSelectionSheet)));

Future<void> _tapChip(WidgetTester tester, String id) async {
  await _reveal(tester, _bandChip(id));
  await tester.tap(_bandChip(id));
  await tester.pumpAndSettle();
}

Future<void> _removeToken(WidgetTester tester, String id) async {
  await _reveal(tester, _removeButton(id));
  await tester.tap(_removeButton(id));
  await tester.pumpAndSettle();
}

Future<void> _typeNote(WidgetTester tester, String text) async {
  await _reveal(tester, find.byKey(_noteKey));
  await tester.enterText(find.byKey(_noteKey), text);
  await tester.pumpAndSettle();
}

/// Confirms the sheet and returns the note it handed the cart.
Future<String?> _confirm(WidgetTester tester, _Harness h) async {
  await _reveal(tester, find.byKey(_confirmKey));
  await tester.tap(find.byKey(_confirmKey));
  await tester.pumpAndSettle();
  expect(find.byType(ModifierSelectionSheet), findsNothing);
  return h.confirmed.single.note;
}

void main() {
  group('A. adding and removing boxes', () {
    testWidgets('T1. a chip tap adds ONE box under the field and leaves the '
        'field untouched', (tester) async {
      final h = await _openSheet(tester);
      await _typeNote(tester, 'well done');
      final controller = _controller(tester);
      final before = controller.value;

      await _tapChip(tester, 'p1');

      expect(_token('p1'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(_tokensRowKey), matching: _token('p1')),
        findsOneWidget,
      );
      expect(_allBoxes(), findsOneWidget);
      // Directly UNDER the field.
      final noteRow = tester.getRect(find.byKey(_noteRowKey));
      final box = tester.getRect(_token('p1'));
      expect(box.top, greaterThan(noteRow.top));
      expect(box.top, greaterThanOrEqualTo(noteRow.bottom));
      // The field's whole value (text, caret, composing) is unchanged.
      expect(identical(_controller(tester), controller), isTrue);
      expect(controller.value, before);
      expect(controller.text, 'well done');
      // The band chip is disabled while its box exists.
      expect(tester.widget<ActionChip>(_bandChip('p1')).onPressed, isNull);
      // A tap is never a confirm.
      expect(find.byType(ModifierSelectionSheet), findsOneWidget);
      expect(h.confirmed, isEmpty);
    });

    testWidgets('T2. boxes keep tap order and the note follows it', (
      tester,
    ) async {
      final h = await _openSheet(tester);
      await _tapChip(tester, 'p2');
      await _tapChip(tester, 'p1');

      expect(_boxOrder(tester), <String>[
        'quick-note-token-p2',
        'quick-note-token-p1',
      ]);
      expect(
        tester.getCenter(_token('p2')).dx,
        lessThan(tester.getCenter(_token('p1')).dx),
      );
      final note = await _confirm(tester, h);
      expect(note, 'Extra crispy, No onions');
      expect(note!.codeUnits, 'Extra crispy, No onions'.codeUnits);
    });

    testWidgets('T3. the X removes only its own box; the others keep their '
        'order and the preset can be tapped again', (tester) async {
      final h = await _openSheet(tester, quickNotes: _numbered(3));
      await _tapChip(tester, 'q0');
      await _tapChip(tester, 'q1');
      await _tapChip(tester, 'q2');
      expect(_allBoxes(), findsNWidgets(3));
      expect(_bandChipEnabled(tester, 'q1'), isFalse);

      await _removeToken(tester, 'q1');

      expect(_token('q1'), findsNothing);
      expect(_token('q0'), findsOneWidget);
      expect(_token('q2'), findsOneWidget);
      expect(_boxOrder(tester), <String>[
        'quick-note-token-q0',
        'quick-note-token-q2',
      ]);
      expect(
        tester.getCenter(_token('q0')).dx,
        lessThan(tester.getCenter(_token('q2')).dx),
      );
      expect(tester.widget<ActionChip>(_bandChip('q1')).onPressed, isNotNull);
      // The X neither confirmed nor closed the sheet.
      expect(h.confirmed, isEmpty);
      expect(find.byType(ModifierSelectionSheet), findsOneWidget);

      expect(await _confirm(tester, h), 'Note 0, Note 2');
    });

    testWidgets('T4. adding and then removing the only box with an empty field '
        'confirms a null note', (tester) async {
      final h = await _openSheet(tester);
      await _tapChip(tester, 'p1');
      await _removeToken(tester, 'p1');
      expect(_allBoxes(), findsNothing);
      expect(await _confirm(tester, h), isNull);
    });

    testWidgets('T5. the X is a full 48dp target and the box label is not a '
        'remove target', (tester) async {
      await _openSheet(tester);
      await _tapChip(tester, 'p1');

      final x = tester.getSize(_removeButton('p1'));
      expect(x.width, greaterThanOrEqualTo(48));
      expect(x.height, greaterThanOrEqualTo(48));
      expect(tester.getSize(_token('p1')).height, greaterThanOrEqualTo(48));

      expect(_tokenLabel('p1'), findsOneWidget);
      await tester.tap(_tokenLabel('p1'));
      await tester.pumpAndSettle();
      expect(_token('p1'), findsOneWidget);
      expect(_bandChipEnabled(tester, 'p1'), isFalse);
    });
  });

  group('B. localization and direction', () {
    const cases = <({String code, String expected})>[
      (code: 'en', expected: 'Delete'),
      (code: 'ar', expected: 'حذف'),
      (code: 'he', expected: 'מחיקה'),
    ];
    for (final c in cases) {
      testWidgets('T6 [${c.code}]. each box carries exactly one localized '
          'Delete tooltip', (tester) async {
        await _openSheet(tester, locale: Locale(c.code));
        await _tapChip(tester, 'p1');
        await _tapChip(tester, 'p2');

        final tooltip = MaterialLocalizations.of(
          tester.element(find.byKey(_tokensKey)),
        ).deleteButtonTooltip;
        expect(tooltip, c.expected);
        expect(find.byTooltip(tooltip), findsNWidgets(2));
        for (final id in const ['p1', 'p2']) {
          expect(
            find.descendant(of: _token(id), matching: find.byTooltip(tooltip)),
            findsOneWidget,
            reason: 'box $id must carry exactly one Delete tooltip',
          );
          expect(
            tester
                .widget<Tooltip>(
                  find
                      .ancestor(
                        of: _removeButton(id),
                        matching: find.byType(Tooltip),
                      )
                      .first,
                )
                .message,
            tooltip,
          );
        }
      });
    }

    testWidgets('T7. ar/he lay boxes out right-to-left with the X at the end '
        'edge; en is mirrored; the note bytes are identical', (tester) async {
      final notes = <String, String?>{};
      for (final code in const ['en', 'ar', 'he']) {
        final h = await _openSheet(tester, locale: Locale(code));
        await _tapChip(tester, 'p1');
        await _tapChip(tester, 'p2');

        final direction = Directionality.of(
          tester.element(find.byKey(_tokensKey)),
        );
        final rtl = code != 'en';
        expect(
          direction,
          rtl ? TextDirection.rtl : TextDirection.ltr,
          reason: '$code direction',
        );
        final first = tester.getCenter(_token('p1'));
        final second = tester.getCenter(_token('p2'));
        expect(first.dy, second.dy, reason: '$code: both boxes on one run');
        if (rtl) {
          expect(first.dx, greaterThan(second.dx), reason: '$code order');
        } else {
          expect(first.dx, lessThan(second.dx), reason: '$code order');
        }
        for (final id in const ['p1', 'p2']) {
          final xCenter = tester.getCenter(_removeButton(id)).dx;
          final labelCenter = tester.getCenter(_tokenLabel(id)).dx;
          if (rtl) {
            expect(xCenter, lessThan(labelCenter), reason: '$code X of $id');
          } else {
            expect(xCenter, greaterThan(labelCenter), reason: '$code X of $id');
          }
        }
        notes[code] = await _confirm(tester, h);
      }
      expect(notes['en'], 'No onions, Extra crispy');
      expect(notes['ar']!.codeUnits, notes['en']!.codeUnits);
      expect(notes['he']!.codeUnits, notes['en']!.codeUnits);
    });

    testWidgets('T8. two 60-character Arabic phrases on a 360dp screen wrap '
        'inside their boxes without overflow; a third is refused', (
      tester,
    ) async {
      expect(_arLong1.length, 60);
      expect(_arLong2.length, 60);
      final h = await _openSheet(
        tester,
        quickNotes: _arabicLong,
        size: const Size(360, 900),
        locale: const Locale('ar'),
      );
      await _tapChip(tester, 'a1');
      await _tapChip(tester, 'a2');
      expect(_allBoxes(), findsNWidgets(2));

      // The third would break the 140-character contract: refused whole.
      await _tapChip(tester, 'a3');
      expect(_token('a3'), findsNothing);
      expect(find.byKey(_warningKey), findsOneWidget);
      expect(_allBoxes(), findsNWidgets(2));

      await _reveal(tester, find.byKey(_tokensRowKey));
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(_tokensRowKey)).width,
        lessThanOrEqualTo(360),
      );
      for (final id in const ['a1', 'a2']) {
        final rect = tester.getRect(_token(id));
        expect(rect.left, greaterThanOrEqualTo(0), reason: id);
        expect(rect.right, lessThanOrEqualTo(360), reason: id);
        // Wrapped onto two or more lines inside the box.
        expect(rect.height, greaterThan(48), reason: id);
        final text = tester.widget<Text>(_tokenLabel(id));
        expect(text.overflow, isNot(TextOverflow.ellipsis), reason: id);
        expect(text.softWrap, isTrue, reason: id);
        expect(
          tester
              .renderObject<RenderParagraph>(_tokenLabel(id))
              .didExceedMaxLines,
          isFalse,
          reason: id,
        );
      }

      final note = await _confirm(tester, h);
      expect(note, '$_arLong1, $_arLong2');
      expect(note!.length, lessThanOrEqualTo(140));
    });
  });

  group('C. composition rules', () {
    testWidgets('T9a. an added preset cannot be added twice', (tester) async {
      final h = await _openSheet(tester);
      await _tapChip(tester, 'p1');
      expect(_bandChipEnabled(tester, 'p1'), isFalse);

      await tester.tap(_bandChip('p1'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_allBoxes(), findsOneWidget);
      expect(_token('p1'), findsOneWidget);
      expect(await _confirm(tester, h), _first);
    });

    testWidgets('T9b. after X the preset is tappable again and re-adding puts '
        'it at the END', (tester) async {
      final h = await _openSheet(tester);
      await _tapChip(tester, 'p1');
      await _tapChip(tester, 'p2');
      await _removeToken(tester, 'p1');
      expect(_bandChipEnabled(tester, 'p1'), isTrue);

      await _tapChip(tester, 'p1');

      expect(_boxOrder(tester), <String>[
        'quick-note-token-p2',
        'quick-note-token-p1',
      ]);
      expect(
        (await _confirm(tester, h))!.codeUnits,
        'Extra crispy, No onions'.codeUnits,
      );
    });

    testWidgets('T10. the typed text always comes first, whichever was done '
        'first', (tester) async {
      final tapFirst = await _openSheet(tester);
      await _tapChip(tester, 'p1');
      await _typeNote(tester, 'please hurry');
      final viaTapFirst = await _confirm(tester, tapFirst);

      final typeFirst = await _openSheet(tester);
      await _typeNote(tester, 'please hurry');
      await _tapChip(tester, 'p1');
      final viaTypeFirst = await _confirm(tester, typeFirst);

      expect(viaTapFirst, 'please hurry, No onions');
      expect(viaTypeFirst!.codeUnits, viaTapFirst!.codeUnits);
    });

    testWidgets('T11. a tap that would exceed 140 characters is refused whole '
        'and the warning clears on a text change', (tester) async {
      await _openSheet(
        tester,
        quickNotes: const <PosQuickNotePreset>[_p1, _p2, _p4],
      );
      await _typeNote(tester, 'x' * 130);
      final before = _controller(tester).value;

      // 130 + ', ' + 9 = 141 > 140.
      await _tapChip(tester, 'p1');

      expect(_token('p1'), findsNothing);
      expect(_allBoxes(), findsNothing);
      expect(find.byKey(_warningKey), findsOneWidget);
      expect(_controller(tester).value, before);
      expect(_controller(tester).text, 'x' * 130);
      expect(_bandChipEnabled(tester, 'p1'), isTrue);
      expect(_noteField(tester).maxLength, 140);

      // A tap that DOES fit clears the warning by itself, with no typing:
      // 130 + ', ' + 3 = 135, and 130 <= 140 - 2 - 3.
      await _tapChip(tester, 'p4');
      expect(_token('p4'), findsOneWidget);
      expect(find.byKey(_warningKey), findsNothing);
      await _removeToken(tester, 'p4');

      // Refused again, then cleared by typing.
      await _tapChip(tester, 'p1');
      expect(find.byKey(_warningKey), findsOneWidget);
      await tester.enterText(find.byKey(_noteKey), 'x' * 129);
      await tester.pumpAndSettle();
      expect(find.byKey(_warningKey), findsNothing);

      // 129 + ', ' + 9 = 140 fits exactly.
      await _tapChip(tester, 'p1');
      expect(_token('p1'), findsOneWidget);
      expect(find.byKey(_warningKey), findsNothing);
    });

    testWidgets('T12a. with a box the field only takes what is left of the 140 '
        'characters, without an error', (tester) async {
      final h = await _openSheet(tester);
      expect(_noteField(tester).maxLength, 140);
      await _tapChip(tester, 'p1');
      // 140 - 2 (separator) - 9 ('No onions').
      expect(_noteField(tester).maxLength, 129);

      await _typeNote(tester, 'x' * 300);
      expect(_controller(tester).text, 'x' * 129);
      expect(_renderedDecoration(tester).errorText, isNull);

      await _removeToken(tester, 'p1');
      expect(_noteField(tester).maxLength, 140);
      expect(_controller(tester).text, 'x' * 129);

      // The budget is exact: 129 typed + the box is exactly 140.
      await _tapChip(tester, 'p1');
      expect(_token('p1'), findsOneWidget);
      expect(_noteField(tester).maxLength, 129);
      final note = await _confirm(tester, h);
      expect(note, '${'x' * 129}, No onions');
      expect(note!.length, lessThanOrEqualTo(140));
    });

    testWidgets('T12b. with no boxes the field keeps its 140-character limit', (
      tester,
    ) async {
      await _openSheet(tester);
      expect(_noteField(tester).maxLength, 140);
      await _typeNote(tester, 'x' * 141);
      expect(_controller(tester).text, 'x' * 140);
      expect(_renderedDecoration(tester).errorText, isNull);
    });

    testWidgets('T13. zero presets leave the note field exactly as before', (
      tester,
    ) async {
      final h = await _openSheet(tester, quickNotes: const []);
      await _reveal(tester, find.byKey(_noteKey));
      expect(find.byKey(_tokensRowKey), findsNothing);
      expect(find.byKey(_tokensKey), findsNothing);
      expect(find.byKey(_bandRowKey), findsNothing);
      expect(_noteField(tester).maxLength, 140);
      expect(
        _noteField(tester).decoration!.hintText,
        _l10n(tester).posModifierItemNoteHint,
      );

      await _typeNote(tester, '  hi  ');
      expect(await _confirm(tester, h), 'hi');
    });

    testWidgets('T14. the example hint shows only while there are no boxes', (
      tester,
    ) async {
      await _openSheet(tester);
      final l10n = _l10n(tester);
      expect(
        _noteField(tester).decoration!.hintText,
        l10n.posModifierItemNoteHint,
      );
      expect(
        _noteField(tester).decoration!.labelText,
        l10n.posModifierItemNoteLabel,
      );

      await _tapChip(tester, 'p1');
      expect(_noteField(tester).decoration!.hintText, isNull);
      expect(
        _noteField(tester).decoration!.labelText,
        l10n.posModifierItemNoteLabel,
      );

      await _removeToken(tester, 'p1');
      expect(
        _noteField(tester).decoration!.hintText,
        l10n.posModifierItemNoteHint,
      );
    });
  });

  group('D. layout stability, keyboard and focus', () {
    testWidgets('T15. adding and removing a box never moves the band or the '
        'field (the row is reserved)', (tester) async {
      await _openSheet(tester, size: const Size(1280, 800));
      await _reveal(tester, find.byKey(_noteKey));

      // Precondition: content-sized, not capped — nothing to scroll.
      final body = tester.state<ScrollableState>(
        find
            .ancestor(
              of: find.byKey(_noteRowKey),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(body.position.maxScrollExtent, 0);

      final watched = <Finder>[
        find.byKey(_bandRowKey),
        _bandChip('p2'),
        find.byKey(_noteKey),
      ];
      List<Offset> positions() => <Offset>[
        for (final f in watched) tester.getTopLeft(f),
      ];

      final before = positions();
      expect(
        tester.getSize(find.byKey(_tokensRowKey)).height,
        greaterThanOrEqualTo(48),
      );

      await tester.tap(_bandChip('p1'));
      await tester.pumpAndSettle();
      expect(_token('p1'), findsOneWidget);
      expect(positions(), before);

      await tester.tap(_removeButton('p1'));
      await tester.pumpAndSettle();
      expect(_token('p1'), findsNothing);
      expect(positions(), before);
      expect(
        tester.getSize(find.byKey(_tokensRowKey)).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('T16. the focused field survives the landscape keyboard and '
        'band / X taps (same EditableText, still focused)', (tester) async {
      await _openSheet(
        tester,
        quickNotes: const <PosQuickNotePreset>[_p1, _p2, _p3],
        size: const Size(1280, 800),
      );
      await _tapChip(tester, 'p1');
      await _tapChip(tester, 'p2');

      await _reveal(tester, find.byKey(_noteKey));
      await tester.tap(find.byKey(_noteKey));
      await tester.pumpAndSettle();
      final state = tester.state<EditableTextState>(_editable());
      expect(state.widget.focusNode.hasFocus, isTrue);

      // Before the keyboard the header is fixed above the body...
      expect(
        find.byKey(const Key('modifier-sheet-scrolled-header')),
        findsNothing,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 460);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // ...and the keyboard really pushed the sheet into its compact layout
      // (header moved INTO the scroll body), so this is a KEYBOARD-002 repro.
      expect(
        find.byKey(const Key('modifier-sheet-scrolled-header')),
        findsOneWidget,
      );
      expect(
        identical(tester.state<EditableTextState>(_editable()), state),
        isTrue,
      );
      expect(state.widget.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      await _reveal(tester, _bandChip('p3'));
      await tester.tap(_bandChip('p3'));
      await tester.pump();
      expect(_token('p3'), findsOneWidget);
      expect(
        identical(tester.state<EditableTextState>(_editable()), state),
        isTrue,
      );
      expect(state.widget.focusNode.hasFocus, isTrue);

      await _reveal(tester, _removeButton('p1'));
      await tester.tap(_removeButton('p1'));
      await tester.pump();
      expect(_token('p1'), findsNothing);
      expect(
        identical(tester.state<EditableTextState>(_editable()), state),
        isTrue,
      );
      expect(state.widget.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('T17. a mouse tap on a band chip or an X keeps focus (the '
        'web-style outside-tap), while a tap elsewhere drops it', (
      tester,
    ) async {
      await _openSheet(tester);
      await _tapChip(tester, 'p2');
      await _reveal(tester, find.byKey(_noteKey));
      await tester.tap(find.byKey(_noteKey));
      await tester.pumpAndSettle();
      final focusNode = tester
          .state<EditableTextState>(_editable())
          .widget
          .focusNode;
      expect(focusNode.hasFocus, isTrue);

      await tester.tap(_bandChip('p1'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(_token('p1'), findsOneWidget);
      expect(focusNode.hasFocus, isTrue, reason: 'band chip tap');

      await tester.tap(_removeButton('p2'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(_token('p2'), findsNothing);
      expect(focusNode.hasFocus, isTrue, reason: 'X tap');

      // Control: the same kind of tap OUTSIDE the field's region unfocuses it,
      // so the two checks above are not vacuous.
      await tester.tap(
        find.descendant(
          of: find.byType(ModifierSelectionSheet),
          matching: find.text('Burger'),
        ),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isFalse, reason: 'outside tap');
    });
  });

  group('E. sheet lifecycle and editing a line', () {
    testWidgets('T18a. boxes and typed text survive a locale + text-scale '
        're-pump of the open route', (tester) async {
      final h = await _openSheet(tester);
      await _tapChip(tester, 'p1');
      await _tapChip(tester, 'p2');
      await _typeNote(tester, 'keep me');

      await h.repump(locale: const Locale('he'), textScale: 1.3);

      // The re-pump really happened.
      expect(
        Directionality.of(tester.element(find.byKey(_tokensKey))),
        TextDirection.rtl,
      );
      expect(
        MediaQuery.textScalerOf(
          tester.element(find.byKey(_tokensKey)),
        ).scale(10),
        closeTo(13, 1e-9),
      );
      expect(_boxOrder(tester), <String>[
        'quick-note-token-p1',
        'quick-note-token-p2',
      ]);
      expect(_controller(tester).text, 'keep me');
      expect(_bandChipEnabled(tester, 'p1'), isFalse);
      expect(_bandChipEnabled(tester, 'p2'), isFalse);
      expect(tester.takeException(), isNull);

      expect(await _confirm(tester, h), 'keep me, No onions, Extra crispy');
    });

    testWidgets('T18b. same item survives a re-pump; a different item id '
        'resets boxes and text', (tester) async {
      await _pumpDirect(tester, item: _burger);
      await _tapChip(tester, 'p1');
      await _tapChip(tester, 'p2');
      await _typeNote(tester, 'keep me');

      await _pumpDirect(
        tester,
        item: _burger,
        locale: const Locale('he'),
        textScale: 1.3,
      );
      expect(_boxOrder(tester), <String>[
        'quick-note-token-p1',
        'quick-note-token-p2',
      ]);
      expect(_controller(tester).text, 'keep me');

      await _pumpDirect(
        tester,
        item: const DemoMenuItem(
          id: 'item-b',
          name: 'Pizza',
          priceMinor: 5000,
          categoryId: 'burgers',
          categoryName: 'Burgers',
        ),
      );
      expect(_allBoxes(), findsNothing);
      expect(find.byKey(_tokensRowKey), findsOneWidget);
      expect(_controller(tester).text, isEmpty);
      expect(_bandChipEnabled(tester, 'p1'), isTrue);
      expect(_bandChipEnabled(tester, 'p2'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('T19a. a saved note ending in presets reopens as boxes and '
        'saves back byte-identical', (tester) async {
      const saved = 'No onions, Extra crispy';
      final h = await _openSheet(tester, isEdit: true, initialNote: saved);
      await _reveal(tester, find.byKey(_noteKey));

      expect(_controller(tester).text, isEmpty);
      expect(_boxOrder(tester), <String>[
        'quick-note-token-p1',
        'quick-note-token-p2',
      ]);
      expect(_bandChipEnabled(tester, 'p1'), isFalse);
      expect(_bandChipEnabled(tester, 'p2'), isFalse);

      expect((await _confirm(tester, h))!.codeUnits, saved.codeUnits);
    });

    testWidgets('T19b. an Arabic comma before a trailing preset is kept in '
        'the field and saves back byte-identical', (tester) async {
      const saved = 'abc، Extra crispy';
      final h = await _openSheet(tester, isEdit: true, initialNote: saved);
      await _reveal(tester, find.byKey(_noteKey));

      expect(_controller(tester).text, 'abc،');
      expect(_boxOrder(tester), <String>['quick-note-token-p2']);
      expect(_bandChipEnabled(tester, 'p1'), isTrue);
      expect(_bandChipEnabled(tester, 'p2'), isFalse);

      expect((await _confirm(tester, h))!.codeUnits, saved.codeUnits);
    });

    testWidgets('T20a. legacy free text stays in the field and a new box '
        'joins after it', (tester) async {
      final h = await _openSheet(
        tester,
        isEdit: true,
        initialNote: 'no onions please',
      );
      await _reveal(tester, find.byKey(_noteKey));
      expect(_controller(tester).text, 'no onions please');
      expect(_allBoxes(), findsNothing);

      await _tapChip(tester, 'p1');
      expect(await _confirm(tester, h), 'no onions please, No onions');
    });

    testWidgets('T20b. a preset that is not at the END, or differs in case, '
        'stays verbatim text', (tester) async {
      for (final saved in const [
        'Extra crispy, typed',
        'well done, no onions',
      ]) {
        final h = await _openSheet(tester, isEdit: true, initialNote: saved);
        await _reveal(tester, find.byKey(_noteKey));
        expect(_controller(tester).text, saved, reason: saved);
        expect(_allBoxes(), findsNothing, reason: saved);
        expect(_bandChipEnabled(tester, 'p1'), isTrue, reason: saved);
        expect(_bandChipEnabled(tester, 'p2'), isTrue, reason: saved);
        expect(
          (await _confirm(tester, h))!.codeUnits,
          saved.codeUnits,
          reason: saved,
        );
      }
    });

    testWidgets('T21. the note-only degraded edit restores boxes and edits '
        'them like any other sheet', (tester) async {
      final h = await _openSheet(
        tester,
        isEdit: true,
        groups: const <PosModifierGroup>[],
        initialSelections: const <SelectedModifier>[
          SelectedModifier(
            optionId: 'opt-gone',
            modifierGroupId: 'g-gone',
            groupName: 'Extras',
            optionName: 'Cheese',
            priceDeltaMinor: 300,
          ),
        ],
        initialNote: 'well done, No onions',
      );

      expect(
        find.byKey(const Key('modifier-options-unavailable')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('modifier-item-quantity-row')), findsNothing);

      await _reveal(tester, find.byKey(_noteKey));
      expect(_controller(tester).text, 'well done');
      expect(_boxOrder(tester), <String>['quick-note-token-p1']);

      await _removeToken(tester, 'p1');
      await _tapChip(tester, 'p2');
      expect(_boxOrder(tester), <String>['quick-note-token-p2']);

      expect(await _confirm(tester, h), 'well done, Extra crispy');
    });
  });
  group('F. review follow-ups', () {
    testWidgets('T22. with the landscape keyboard up, a box added below the '
        'visible body is scrolled just into reach of its X', (tester) async {
      // Two long phrases already added fill the first box row(s), so the new
      // box lands on a LATER row of the Wrap — well below the field.
      const long1 = PosQuickNotePreset(
        id: 'l1',
        label: 'Please cut the burger in half and wrap each half',
        displayOrder: 0,
      );
      const long2 = PosQuickNotePreset(
        id: 'l2',
        label: 'Sauce on the side with extra napkins for the bag',
        displayOrder: 1,
      );
      await _openSheet(
        tester,
        quickNotes: const <PosQuickNotePreset>[long1, long2, _p1],
        size: const Size(1280, 800),
        groups: <PosModifierGroup>[
          for (var g = 0; g < 4; g++)
            PosModifierGroup(
              id: 'g-$g',
              menuItemId: 'item-a',
              name: 'Extras $g',
              options: <PosModifierOption>[
                PosModifierOption(
                  id: 'opt-$g',
                  name: 'Option $g',
                  priceDeltaMinor: 0,
                ),
              ],
            ),
        ],
      );
      await _tapChip(tester, 'l1');
      await _tapChip(tester, 'l2');

      // The real sequence: the cashier taps into the field, the keyboard
      // comes up, and the body keeps the caret on screen — so the field sits
      // near the bottom of the now tiny viewport.
      await _reveal(tester, find.byKey(_noteKey));
      await tester.tap(find.byKey(_noteKey));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 460);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('modifier-sheet-scrolled-header')),
        findsOneWidget,
      );
      final bodyFinder = find
          .descendant(
            of: find.byType(ModifierSelectionSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      final viewport = tester.getRect(bodyFinder);
      // Where the caret reveal leaves it, made exact: the field's bottom edge
      // on the viewport's bottom edge, so the box rows under it are hidden.
      final body = tester.state<ScrollableState>(bodyFinder).position;
      body.jumpTo(
        body.pixels +
            tester.getRect(find.byKey(_noteKey)).bottom -
            viewport.bottom,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(_noteKey)).bottom,
        moreOrLessEquals(viewport.bottom),
      );

      // Precondition: the last box row is below the visible body, and a new
      // box is laid out on that row or a later one — so it starts out of
      // reach. (Measured before the tap: the reveal is applied within the
      // frame that builds the new box.)
      expect(
        tester.getCenter(_token('l2')).dy,
        greaterThan(viewport.bottom),
        reason: 'precondition: the box rows start below the visible body',
      );

      // The band chip above is in reach and is tapped where it is.
      expect(_bandChip('p1').hitTestable(), findsOneWidget);
      await tester.tap(_bandChip('p1'));
      await tester.pumpAndSettle();
      expect(_token('p1'), findsOneWidget);
      expect(_isAfterOrOn(tester, 'p1', 'l2'), isTrue);
      // Reachable: the X is hit-testable where it is drawn, without the test
      // scrolling for it...
      expect(_removeButton('p1').hitTestable(), findsOneWidget);
      // ...and the scroll went only as far as needed: the field the cashier
      // is typing into is still on screen (a reveal that put the box row at
      // the TOP of the viewport would hide it).
      expect(find.byKey(_noteKey).hitTestable(), findsOneWidget);
      expect(
        tester.state<EditableTextState>(_editable()).widget.focusNode.hasFocus,
        isTrue,
      );

      await tester.tap(_removeButton('p1'));
      await tester.pumpAndSettle();
      expect(_token('p1'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('T23. a screen reader hears each box as its phrase plus '
        'Delete, as one button — on every platform', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _openSheet(tester);
        await _tapChip(tester, 'p1');
        await _tapChip(tester, 'p2');
        final delete = MaterialLocalizations.of(
          tester.element(find.byType(ModifierSelectionSheet)),
        ).deleteButtonTooltip;
        // The word is in the LABEL (Android does not announce tooltips on
        // focus), after the phrase, and the node removes that phrase.
        expect(
          tester.getSemantics(_removeButton('p1')),
          isSemantics(
            label: '$_first\n$delete',
            isButton: true,
            hasTapAction: true,
          ),
        );
        expect(
          tester.getSemantics(_removeButton('p2')),
          isSemantics(
            label: '$_second\n$delete',
            isButton: true,
            hasTapAction: true,
          ),
        );
      } finally {
        // Disposed in the body: the end-of-test check runs before tear-downs.
        semantics.dispose();
      }
    });

    testWidgets('T25. two taps on one chip in the same frame add it once', (
      tester,
    ) async {
      final h = await _openSheet(tester);
      await _reveal(tester, _bandChip('p1'));
      // No pump in between: the second tap reaches the chip before the
      // rebuild that disables it.
      await tester.tap(_bandChip('p1'));
      await tester.tap(_bandChip('p1'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_allBoxes(), findsOneWidget);
      expect(await _confirm(tester, h), _first);
    });

    testWidgets('T26. a blank preset (bad data) adds nothing and warns of '
        'nothing', (tester) async {
      const blank = PosQuickNotePreset(
        id: 'blank',
        label: '   ',
        displayOrder: 9,
      );
      await _openSheet(
        tester,
        quickNotes: const <PosQuickNotePreset>[_p1, blank],
      );
      await _tapChip(tester, 'blank');
      expect(_allBoxes(), findsNothing);
      expect(find.byKey(_warningKey), findsNothing);
      expect(_noteField(tester).maxLength, 140);
      expect(_bandChipEnabled(tester, 'blank'), isTrue);
    });

    testWidgets('T24. if the presets disappear while boxes exist, the boxes '
        'stay visible and removable (nothing prints unseen)', (tester) async {
      _setView(tester, const Size(1000, 1400));
      final presets = ValueNotifier<List<PosQuickNotePreset>>(_pair);
      addTearDown(presets.dispose);
      String? confirmedNote;
      await tester.pumpWidget(
        _hostApp(
          locale: const Locale('en'),
          textScale: 1.0,
          home: Scaffold(
            body: ValueListenableBuilder<List<PosQuickNotePreset>>(
              valueListenable: presets,
              builder: (context, value, _) => ModifierSelectionSheet(
                key: const ValueKey('customization'),
                item: _burger,
                groups: _groups(),
                currencyCode: 'ILS',
                quickNotes: value,
                onConfirm: (selections, note, quantity) => confirmedNote = note,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapChip(tester, 'p1');

      presets.value = const <PosQuickNotePreset>[];
      await tester.pumpAndSettle();
      expect(find.byKey(_bandRowKey), findsNothing);
      expect(find.byKey(_tokensRowKey), findsOneWidget);
      expect(_token('p1'), findsOneWidget);

      await _removeToken(tester, 'p1');
      expect(find.byKey(_tokensRowKey), findsNothing);
      expect(_noteField(tester).maxLength, 140);
      await _reveal(tester, find.byKey(_confirmKey));
      await tester.tap(find.byKey(_confirmKey));
      await tester.pumpAndSettle();
      expect(confirmedNote, isNull);
    });
  });
}
