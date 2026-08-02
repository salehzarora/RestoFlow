import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/widgets/modifier_selection_sheet.dart';

/// POS-PRODUCT-NOTE-LANDSCAPE-KEYBOARD-002 — the product note lost focus the
/// instant the Android keyboard opened on a SHORT LANDSCAPE tablet (11" Redmi,
/// 1280x800): the keyboard appeared and vanished again, while the typed note
/// survived. It worked in portrait, and it worked on a taller landscape tablet.
///
/// The cause is structural, not device-specific. When the keyboard's viewInset
/// shrinks the sheet below [_compactHeightBelow] the header MOVES from a fixed
/// slot above the scroll body INTO the scroll body, prepending two entries and
/// shifting every body child's index by two. The sheet's scroll children were
/// unkeyed, so the reconciler matched them by index: the element that held the
/// focused note TextField was handed a different widget, the input connection
/// closed, and the keyboard dismissed itself. The note controller lives on the
/// State, which is exactly why the TEXT survived while the FOCUS did not.
///
/// These tests reproduce that transition through the REAL modal route, so the
/// viewInsets padding, the height cap and the route constraints are authentic.

/// Bottom inset (logical px) that genuinely crosses the sheet's real compact
/// breakpoint at 1280x800. The threshold is on the sheet's own available
/// height, not on the inset, so this is verified by asserting the compact
/// structure rather than by arithmetic — see [_compactEntered].
const double _kKeyboardInset = 460;

const Key _noteKey = Key('modifier-item-note');
const Key _closeKey = Key('modifier-close-button');
const Key _confirmKey = Key('modifier-add-button');

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

DemoMenuItem _item() => const DemoMenuItem(
  id: 'item-a',
  name: 'Burger',
  priceMinor: 4000,
  categoryId: 'burgers',
  categoryName: 'Burgers',
);

/// Optional groups only, so the confirm action is enabled without a selection
/// (the note, not the selection rules, is what these tests exercise). Enough
/// options that the body genuinely scrolls at this height.
List<PosModifierGroup> _groups() => <PosModifierGroup>[
  for (var g = 0; g < 4; g++)
    PosModifierGroup(
      id: 'g-$g',
      menuItemId: 'item-a',
      name: 'Group $g',
      options: [
        for (var o = 0; o < 4; o++)
          PosModifierOption(
            id: 'opt-$g-$o',
            name: 'Option $g$o',
            priceDeltaMinor: 100 * o,
          ),
      ],
    ),
];

/// The note's live [EditableText] — re-found on every call, so a REPLACED
/// element is observed as a fresh focus node with no focus (which is the
/// defect), never masked by a stale captured reference.
EditableText _noteEditable(WidgetTester tester) => tester.widget<EditableText>(
  find.descendant(
    of: find.byKey(_noteKey),
    matching: find.byType(EditableText),
  ),
);

bool _noteFocused(WidgetTester tester) =>
    _noteEditable(tester).focusNode.hasFocus;

/// True while the header sits in its FIXED slot ABOVE the scroll body — the
/// non-compact layout. In the compact layout the header is a CHILD of the
/// scroll body, so it is either a [Scrollable] descendant or, once the body is
/// scrolled down, not built at all; both are the compact branch. Typed against
/// [Scrollable] rather than a concrete scroll widget so it stays valid
/// whichever container the body uses.
bool _headerIsFixedAboveBody(WidgetTester tester) {
  final anywhere = find.byKey(_closeKey).evaluate().length;
  final inScrollBody = find
      .descendant(of: find.byType(Scrollable), matching: find.byKey(_closeKey))
      .evaluate()
      .length;
  return anywhere > inScrollBody;
}

/// Proof that the REAL compact branch was entered.
bool _compactEntered(WidgetTester tester) => !_headerIsFixedAboveBody(tester);

/// Brings the note into the lazy scroll viewport (it is the LAST child of the
/// body, so it is not built until scrolled to).
Future<void> _revealNote(WidgetTester tester) async {
  if (find.byKey(_noteKey).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.byKey(_noteKey),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.byKey(_noteKey));
  await tester.pumpAndSettle();
}

/// Opens the sheet through the real modal route.
Future<void> _openSheet(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  Locale locale = const Locale('en'),
  String? initialNote,
  bool isEdit = false,
  void Function(List<SelectedModifier> selections, String? note)? onConfirm,
}) async {
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
                initialNote: initialNote,
                isEdit: isEdit,
                onConfirm: onConfirm ?? (_, _) {},
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
}

/// Raises the on-screen keyboard by applying its bottom view inset.
Future<void> _showKeyboard(
  WidgetTester tester, {
  double inset = _kKeyboardInset,
}) async {
  tester.view.viewInsets = FakeViewPadding(bottom: inset);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _hideKeyboard(WidgetTester tester) async {
  tester.view.viewInsets = FakeViewPadding.zero;
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Scrolls the note into view, taps it, and asserts it really took focus
/// before the transition.
Future<void> _focusNote(WidgetTester tester) async {
  await _revealNote(tester);
  await tester.tap(find.byKey(_noteKey));
  await tester.pumpAndSettle();
  expect(
    _noteFocused(tester),
    isTrue,
    reason: 'precondition: the note must own focus before the keyboard opens',
  );
}

void main() {
  group('A. landscape breakpoint regression', () {
    testWidgets('002-A1. the note keeps focus when the keyboard shrinks the '
        'sheet past the compact breakpoint', (tester) async {
      await _openSheet(tester);

      // Before the keyboard: the sheet is roomy, the header sits OUTSIDE the
      // scroll body.
      expect(_compactEntered(tester), isFalse);

      await _focusNote(tester);
      await _showKeyboard(tester);

      // The structural transition really happened — otherwise this test would
      // pass without ever exercising the defect.
      expect(
        _compactEntered(tester),
        isTrue,
        reason: 'the compact branch must be entered for this to be a repro',
      );

      expect(find.byType(ModifierSelectionSheet), findsOneWidget);
      expect(
        _noteFocused(tester),
        isTrue,
        reason: 'the keyboard resize must not steal focus from the note',
      );
      // The user-visible symptom: the keyboard appeared and then vanished.
      expect(
        tester.testTextInput.isVisible,
        isTrue,
        reason: 'the input connection must stay open across the resize',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('002-A2. the note element SURVIVES the transition rather than '
        'being rebuilt', (tester) async {
      await _openSheet(tester);
      await _focusNote(tester);

      // Identity of the element behind the note, captured before the resize.
      final before = tester.element(find.byKey(_noteKey));
      await _showKeyboard(tester);
      expect(_compactEntered(tester), isTrue);
      final after = tester.element(find.byKey(_noteKey));

      expect(
        identical(before, after),
        isTrue,
        reason:
            'a replaced element is exactly what closes the input connection',
      );
    });
  });

  group('B. typing after the structural transition', () {
    testWidgets('002-B1. Arabic text typed after the keyboard arrives reaches '
        'the controller and the confirm payload', (tester) async {
      List<SelectedModifier>? gotSelections;
      String? gotNote;
      await _openSheet(
        tester,
        onConfirm: (s, n) {
          gotSelections = s;
          gotNote = n;
        },
      );
      await _focusNote(tester);
      await _showKeyboard(tester);
      expect(_compactEntered(tester), isTrue);

      await tester.enterText(find.byKey(_noteKey), 'بدون بصل');
      await tester.pump();

      expect(_noteEditable(tester).controller.text, 'بدون بصل');
      expect(find.text('بدون بصل'), findsOneWidget);

      await tester.ensureVisible(find.byKey(_confirmKey));
      await tester.tap(find.byKey(_confirmKey));
      await tester.pumpAndSettle();

      expect(gotNote, 'بدون بصل');
      expect(gotSelections, isNotNull);
      expect(find.byType(ModifierSelectionSheet), findsNothing);
    });
  });

  group('C. flipping back to non-compact', () {
    testWidgets('002-C1. dismissing the keyboard keeps the sheet open with a '
        'sane note state', (tester) async {
      await _openSheet(tester);
      await _focusNote(tester);
      await _showKeyboard(tester);
      await tester.enterText(find.byKey(_noteKey), 'بدون بصل');
      await tester.pump();

      await _hideKeyboard(tester);

      // Back to the roomy layout, and the sheet is still up.
      expect(_compactEntered(tester), isFalse);
      expect(find.byType(ModifierSelectionSheet), findsOneWidget);
      expect(_noteEditable(tester).controller.text, 'بدون بصل');
      expect(tester.takeException(), isNull);
    });
  });

  group('D. portrait guard', () {
    testWidgets('002-D1. the note keeps focus through a keyboard resize in '
        'portrait too', (tester) async {
      await _openSheet(tester, size: const Size(800, 1280));
      await _focusNote(tester);
      await _showKeyboard(tester);

      expect(find.byType(ModifierSelectionSheet), findsOneWidget);
      expect(_noteFocused(tester), isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('E. repeated lifecycle', () {
    testWidgets('002-E1. open/focus/type/close three times leaves no stale '
        'note and no disposal error', (tester) async {
      final notes = <String?>[];
      for (var round = 1; round <= 3; round++) {
        await _openSheet(tester, onConfirm: (_, n) => notes.add(n));
        // Every round starts from a clean note — no leakage from the last one.
        expect(
          _noteEditable(tester).controller.text,
          isEmpty,
          reason: 'round $round must not inherit the previous note',
        );

        await _focusNote(tester);
        await _showKeyboard(tester);
        await tester.enterText(find.byKey(_noteKey), 'note-$round');
        await tester.pump();
        expect(_noteFocused(tester), isTrue, reason: 'round $round focus');

        await tester.ensureVisible(find.byKey(_confirmKey));
        await tester.tap(find.byKey(_confirmKey));
        await tester.pumpAndSettle();
        expect(find.byType(ModifierSelectionSheet), findsNothing);

        await _hideKeyboard(tester);
      }

      expect(notes, <String?>['note-1', 'note-2', 'note-3']);
      expect(tester.takeException(), isNull);
    });
  });

  group('F. edit flow with a prefilled note', () {
    testWidgets('002-F1. a prefilled note survives the landscape keyboard '
        'transition and stays editable', (tester) async {
      String? saved;
      await _openSheet(
        tester,
        initialNote: 'بدون بصل',
        isEdit: true,
        onConfirm: (_, n) => saved = n,
      );
      expect(_noteEditable(tester).controller.text, 'بدون بصل');

      await _focusNote(tester);
      await _showKeyboard(tester);
      expect(_compactEntered(tester), isTrue);

      // Intact across the transition...
      expect(_noteEditable(tester).controller.text, 'بدون بصل');
      expect(_noteFocused(tester), isTrue);

      // ...and still editable.
      await tester.enterText(find.byKey(_noteKey), 'بدون بصل وبدون مخلل');
      await tester.pump();
      await tester.ensureVisible(find.byKey(_confirmKey));
      await tester.tap(find.byKey(_confirmKey));
      await tester.pumpAndSettle();

      expect(saved, 'بدون بصل وبدون مخلل');
    });
  });

  group('G. keyboard dismissal is not sheet dismissal', () {
    testWidgets('002-G1. hiding the keyboard leaves the sheet open; the close '
        'button still dismisses it', (tester) async {
      var confirmed = false;
      await _openSheet(tester, onConfirm: (_, _) => confirmed = true);
      await _focusNote(tester);
      await _showKeyboard(tester);
      expect(find.byType(ModifierSelectionSheet), findsOneWidget);

      await _hideKeyboard(tester);
      expect(
        find.byType(ModifierSelectionSheet),
        findsOneWidget,
        reason: 'the keyboard closing must never close the sheet',
      );

      // The existing dismissal path is untouched, and closing never confirms.
      await tester.tap(find.byKey(_closeKey));
      await tester.pumpAndSettle();
      expect(find.byType(ModifierSelectionSheet), findsNothing);
      expect(confirmed, isFalse);
    });

    testWidgets('002-G2. scrim and Escape still dismiss the sheet after a '
        'keyboard transition', (tester) async {
      await _openSheet(tester);
      await _focusNote(tester);
      await _showKeyboard(tester);
      await _hideKeyboard(tester);

      // Escape.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ModifierSelectionSheet), findsNothing);

      // Scrim.
      await tester.tap(find.byKey(const Key('open-sheet')));
      await tester.pumpAndSettle();
      await _focusNote(tester);
      await _showKeyboard(tester);
      await _hideKeyboard(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(ModifierSelectionSheet), findsNothing);
    });
  });

  group('H. the compact branch itself is unchanged', () {
    testWidgets('002-H1. compact keeps the header in the body and non-compact '
        'keeps it fixed above', (tester) async {
      final l10n = await _en();
      await _openSheet(tester);

      // Non-compact: header fixed above the scroll body, footer present.
      expect(_compactEntered(tester), isFalse);
      expect(find.byKey(_closeKey), findsOneWidget);
      expect(find.text(l10n.posReceiptTotal), findsOneWidget);

      await _showKeyboard(tester);
      // Compact: header inside the body, footer STILL outside it.
      expect(_compactEntered(tester), isTrue);
      expect(
        find
            .descendant(
              of: find.byType(Scrollable),
              matching: find.byKey(_confirmKey),
            )
            .evaluate(),
        isEmpty,
        reason: 'the footer must stay sticky in the compact layout',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
