import 'dart:convert' show jsonEncode;
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/format/quick_note_composition.dart';
import 'package:restoflow_pos/src/format/quick_note_insertion.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';

/// POS-QUICK-NOTE-CHIPS-001 — the pure composition rules behind the removable
/// quick-note chips, exercised directly (no widgets).
///
/// The sheet keeps tapped presets as chips and folds them onto the typed text
/// only when it confirms. Everything that can go wrong with that — the bytes of
/// the confirmed note, the typing budget, the add/refuse boundary and the
/// split-back on edit — lives in `quick_note_composition.dart`, so every rule
/// is pinned here:
///
///  * C1 — `composeQuickNote` is the identity without chips and is EXACTLY a
///    left fold of the unchanged `buildQuickNoteInsertion`.
///  * C2 — a hand-written golden corpus whose expected strings are literals,
///    never computed by the code under test.
///  * C3 — the typing budget and the add boundary, to the character.
///  * C4 — `splitTrailingQuickNotes` round-trips seeded random notes and
///    recovers the chips whenever the note is unambiguous.
///  * C5 — split exactness (case, position, longest label first) and every
///    verbatim fallback.
///  * C6 — removing any chip strictly shrinks the note and grows the budget.
void main() {
  /// The fold's own "never reached" cap, so the law is checked against the
  /// insertion rules alone.
  const int uncapped = 1 << 30;

  String fold(String acc, String label) =>
      buildQuickNoteInsertion(acc, label, maxLength: uncapped).text!;

  /// A readable, escaped rendering for failure reasons.
  String show(Object? value) => jsonEncode(value);

  String randomText(math.Random rng, List<String> alphabet, int maxTokens) {
    final count = rng.nextInt(maxTokens + 1);
    final buffer = StringBuffer();
    for (var i = 0; i < count; i++) {
      buffer.write(alphabet[rng.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  /// Latin, Arabic (with its comma and semicolon), Hebrew, ASCII clause
  /// enders, spaces, tabs and line breaks — every class of character the
  /// insertion rules branch on.
  const List<String> mixedAlphabet = <String>[
    'a',
    'b',
    'Z',
    'o',
    'n',
    ' ',
    '  ',
    ',',
    ';',
    '،', // Arabic comma
    '؛', // Arabic semicolon
    '\n',
    '\t',
    '.',
    '-',
    'ب',
    'ص',
    'ل',
    'ש',
    'ל',
    'ם',
  ];

  String trailingRun(String text) =>
      text.substring(text.replaceFirst(RegExp(r'\s+$'), '').length);

  String coreOf(String text) => text.replaceFirst(RegExp(r'\s+$'), '');

  group('C1. compose identity and fold law', () {
    const identityCorpus = <String>[
      '',
      '   ',
      '\n',
      '\t',
      ' \n ',
      'abc',
      'abc\n',
      ' abc ',
      'a\r\n',
      ',',
      'x,',
      'No onions, Extra crispy',
      'Line one\nLine two',
      'بدون بصل',
      'بدون بصل،',
      'בלי בצל',
      'בלי בצל; חריף',
    ];

    test('C1.1 no chips: the composed note IS the free text, verbatim', () {
      for (final freeText in identityCorpus) {
        expect(
          composeQuickNote(freeText, const <String>[]),
          freeText,
          reason: 'F=${show(freeText)}',
        );
      }
    });

    test('C1.2 blank chips add nothing: the free text survives verbatim', () {
      for (final freeText in identityCorpus) {
        expect(
          composeQuickNote(freeText, const <String>['', '   ', '\n', '\t ']),
          freeText,
          reason: 'F=${show(freeText)}',
        );
      }
    });

    test('C1.3 compose(F, L + [t]) == insertion(compose(F, L), t) — 5000 '
        'seeded cases', () {
      final rng = math.Random(124);
      for (var c = 0; c < 5000; c++) {
        final freeText = randomText(rng, mixedAlphabet, 24);
        final labels = <String>[
          for (var i = rng.nextInt(5); i > 0; i--)
            randomText(rng, mixedAlphabet, 10),
        ];
        final next = randomText(rng, mixedAlphabet, 10);

        final before = composeQuickNote(freeText, labels);
        final after = composeQuickNote(freeText, <String>[...labels, next]);
        expect(
          after,
          fold(before, next),
          reason:
              'case $c: F=${show(freeText)} L=${show(labels)} '
              't=${show(next)}',
        );
        // And the whole thing is the plain left fold from the free text.
        var acc = freeText;
        for (final label in <String>[...labels, next]) {
          acc = fold(acc, label);
        }
        expect(after, acc, reason: 'case $c: left fold');
      }
    });
  });

  group('C2. golden literal corpus', () {
    // (free text, chip labels in tap order, EXPECTED LITERAL). The expected
    // strings are written by hand — never produced by the code under test.
    final golden = <(String, List<String>, String)>[
      ('', <String>['No onions', 'Extra crispy'], 'No onions, Extra crispy'),
      ('No onions', <String>['Extra crispy'], 'No onions, Extra crispy'),
      ('بدون بصل،', <String>['زيادة صوص'], 'بدون بصل، زيادة صوص'),
      ('بدون بصل،  ', <String>['زيادة صوص'], 'بدون بصل، زيادة صوص'),
      ('بدون بصل', <String>['Extra crispy'], 'بدون بصل, Extra crispy'),
      ('   ', <String>['No onions'], 'No onions'),
      ('\n', <String>['No onions'], 'No onions'),
      (
        'well done',
        <String>['No onions', 'Extra crispy'],
        'well done, No onions, Extra crispy',
      ),
      ('  well done', <String>['No onions'], '  well done, No onions'),
      ('a\n', <String>['b'], 'a\nb'),
      ('a\n\n', <String>['b'], 'a\n\nb'),
      ('a \n ', <String>['b'], 'a \n b'),
      ('x;', <String>['y'], 'x; y'),
      ('x,', <String>['y'], 'x, y'),
      ('x, ', <String>['y'], 'x, y'),
      ('x  ', <String>['y'], 'x, y'),
      ('x؛', <String>['y'], 'x؛ y'),
      ('בלי בצל', <String>['חריף'], 'בלי בצל, חריף'),
      ('בלי בצל;', <String>['חריף'], 'בלי בצל; חריף'),
      (
        'בלי בצל',
        <String>['زيادة صوص،', 'No ice'],
        'בלי בצל, زيادة صوص، No ice',
      ),
      // A label with an inner comma is ordinary text.
      (
        'Burger',
        <String>['Sauce, on side', 'No ice'],
        'Burger, Sauce, on side, No ice',
      ),
      // A label ending in ',' is honoured as the next label's clause ender.
      ('', <String>['A,', 'B'], 'A, B'),
      ('', <String>['A,', 'B,', 'C'], 'A, B, C'),
      // Blank labels are a no-op, even on trailing whitespace.
      ('well done', <String>['   '], 'well done'),
      ('well done ', <String>[''], 'well done '),
      ('a', <String>['', 'b', '  ', 'c'], 'a, b, c'),
      // Labels are trimmed on the outside only.
      ('', <String>['  No onions  '], 'No onions'),
      ('Burger', <String>['\tExtra crispy \n'], 'Burger, Extra crispy'),
      ('', <String>['Line one\nLine two', 'x'], 'Line one\nLine two, x'),
      // No duplicate detection inside the fold (the sheet prevents it by id).
      ('', <String>['No onions', 'No onions'], 'No onions, No onions'),
      // No chips: verbatim.
      ('', <String>[], ''),
      ('  well done  ', <String>[], '  well done  '),
    ];

    test('C2.1 every golden triple composes to its literal', () {
      for (final (freeText, labels, expected) in golden) {
        expect(
          composeQuickNote(freeText, labels),
          expected,
          reason: 'F=${show(freeText)} L=${show(labels)}',
        );
      }
    });

    test('C2.2 the golden corpus is non-trivial', () {
      expect(golden.length, greaterThanOrEqualTo(25));
    });

    bool hasHiddenMarker(String text) {
      for (final unit in text.codeUnits) {
        final zeroWidth = unit >= 0x200B && unit <= 0x200F;
        final isolate = unit >= 0x2066 && unit <= 0x2069;
        final embedding = unit >= 0x202A && unit <= 0x202E;
        if (zeroWidth || isolate || embedding || unit == 0xFEFF) return true;
      }
      return false;
    }

    test('C2.3 no output carries a preset id, "#", "{" or an invisible '
        'marker', () {
      final outputs = <String>[
        for (final (freeText, labels, _) in golden)
          composeQuickNote(freeText, labels),
        composeQuickNote('', <String>[
          for (final preset in kDemoQuickNotePresets) preset.label,
        ]),
        composeQuickNote('well done\n', <String>[
          for (final preset in kDemoQuickNotePresets.reversed) preset.label,
        ]),
      ];
      expect(kDemoQuickNotePresets, isNotEmpty);
      for (final output in outputs) {
        for (final preset in kDemoQuickNotePresets) {
          expect(
            output.contains(preset.id),
            isFalse,
            reason: '${show(output)} contains id ${preset.id}',
          );
        }
        expect(output.contains('#'), isFalse, reason: show(output));
        expect(output.contains('{'), isFalse, reason: show(output));
        expect(hasHiddenMarker(output), isFalse, reason: show(output));
      }
    });
  });

  group('C3. budget and add boundaries', () {
    test('C3.1 the typing budget', () {
      expect(quickNoteFreeTextBudget(const <String>[]), 140);
      expect(quickNoteFreeTextBudget(const <String>['No onions']), 129);
      // 'No onions, Extra crispy' is 23 characters.
      expect(
        quickNoteFreeTextBudget(const <String>['No onions', 'Extra crispy']),
        115,
      );
      // Blank chips compose to nothing: no reserve is taken.
      expect(quickNoteFreeTextBudget(const <String>['  ', '']), 140);
      // Outer whitespace on a label does not count.
      expect(quickNoteFreeTextBudget(const <String>['  No onions  ']), 129);
      expect(
        quickNoteFreeTextBudget(const <String>['No onions'], maxLength: 20),
        9,
      );
    });

    test('C3.2 accepted exactly at a composed 140, refused at 141', () {
      final at140 = 'x' * 129;
      expect(composeQuickNote(at140, const <String>['No onions']).length, 140);
      expect(
        canAddQuickNote(
          freeText: at140,
          labels: const <String>[],
          newLabel: 'No onions',
        ),
        isTrue,
      );

      final at141 = 'x' * 130;
      expect(composeQuickNote(at141, const <String>['No onions']).length, 141);
      expect(
        canAddQuickNote(
          freeText: at141,
          labels: const <String>[],
          newLabel: 'No onions',
        ),
        isFalse,
      );

      // Same boundary with a chip already present: 'No salt, No onions' is 18.
      expect(
        quickNoteFreeTextBudget(const <String>['No salt', 'No onions']),
        120,
      );
      final withChip140 = 'x' * 120;
      expect(
        composeQuickNote(withChip140, const <String>[
          'No salt',
          'No onions',
        ]).length,
        140,
      );
      expect(
        canAddQuickNote(
          freeText: withChip140,
          labels: const <String>['No salt'],
          newLabel: 'No onions',
        ),
        isTrue,
      );
      expect(
        canAddQuickNote(
          freeText: 'x' * 121,
          labels: const <String>['No salt'],
          newLabel: 'No onions',
        ),
        isFalse,
      );
    });

    test('C3.3 free text that fits by composition but not the budget is '
        'refused (the 2-char reserve)', () {
      // Each composes to exactly 140 — within the note contract — but the
      // typed text is longer than the 129-character budget one chip leaves.
      final cases = <String>[
        '${'x' * 129},', // ',' -> one space, not ', '
        '${'x' * 129}،', // Arabic comma
        '${'x' * 129};',
        '${'x' * 130}\n', // a kept line break -> no separator at all
      ];
      for (final freeText in cases) {
        expect(
          composeQuickNote(freeText, const <String>['No onions']).length,
          140,
          reason: show(freeText),
        );
        expect(freeText.length, greaterThan(129));
        expect(
          canAddQuickNote(
            freeText: freeText,
            labels: const <String>[],
            newLabel: 'No onions',
          ),
          isFalse,
          reason: show(freeText),
        );
      }

      // Whitespace-only text composes to the chip alone, yet still occupies
      // the field: over budget, refused.
      final spaces = ' ' * 130;
      expect(
        composeQuickNote(spaces, const <String>['No onions']),
        'No onions',
      );
      expect(
        canAddQuickNote(
          freeText: spaces,
          labels: const <String>[],
          newLabel: 'No onions',
        ),
        isFalse,
      );
      expect(
        canAddQuickNote(
          freeText: ' ' * 129,
          labels: const <String>[],
          newLabel: 'No onions',
        ),
        isTrue,
      );
    });

    test('C3.4 chips only: composed 137 is accepted, 138 refused (no typing '
        'room left)', () {
      final first = 'A' * 60;
      final fits = 'B' * 75; // 60 + ', ' + 75 = 137
      final tooLong = 'B' * 76; // 138

      expect(composeQuickNote('', <String>[first, fits]).length, 137);
      expect(quickNoteFreeTextBudget(<String>[first, fits]), 1);
      expect(
        canAddQuickNote(freeText: '', labels: <String>[first], newLabel: fits),
        isTrue,
      );
      // The one character of room is real...
      expect(
        canAddQuickNote(freeText: 'x', labels: <String>[first], newLabel: fits),
        isTrue,
      );
      expect(composeQuickNote('x', <String>[first, fits]).length, 140);
      // ...and is all there is.
      expect(
        canAddQuickNote(
          freeText: 'xy',
          labels: <String>[first],
          newLabel: fits,
        ),
        isFalse,
      );

      expect(composeQuickNote('', <String>[first, tooLong]).length, 138);
      expect(quickNoteFreeTextBudget(<String>[first, tooLong]), 0);
      expect(
        canAddQuickNote(
          freeText: '',
          labels: <String>[first],
          newLabel: tooLong,
        ),
        isFalse,
      );

      // A single chip: 137 accepted, 138 refused.
      expect(
        canAddQuickNote(
          freeText: '',
          labels: const <String>[],
          newLabel: 'C' * 137,
        ),
        isTrue,
      );
      expect(
        canAddQuickNote(
          freeText: '',
          labels: const <String>[],
          newLabel: 'C' * 138,
        ),
        isFalse,
      );
    });

    test('C3.5 a custom maxLength is honoured', () {
      expect(
        canAddQuickNote(
          freeText: 'abcdefghi',
          labels: const <String>[],
          newLabel: 'No onions',
          maxLength: 20,
        ),
        isTrue,
      );
      expect(
        canAddQuickNote(
          freeText: 'abcdefghij',
          labels: const <String>[],
          newLabel: 'No onions',
          maxLength: 20,
        ),
        isFalse,
      );
    });

    test('C3.6 a blank new label changes neither the note nor the budget', () {
      const labelSets = <List<String>>[
        <String>[],
        <String>['No onions'],
        <String>['No onions', 'Extra crispy'],
      ];
      const freeTexts = <String>['', 'well done', 'a\n', 'x,', '   '];
      for (final labels in labelSets) {
        for (final freeText in freeTexts) {
          for (final blank in const <String>['', '   ', '\n']) {
            expect(
              composeQuickNote(freeText, <String>[...labels, blank]),
              composeQuickNote(freeText, labels),
              reason: 'F=${show(freeText)} L=${show(labels)}',
            );
          }
        }
        expect(
          quickNoteFreeTextBudget(<String>[...labels, '  ']),
          quickNoteFreeTextBudget(labels),
        );
      }
    });

    test('C3.7 canAdd is exactly the three documented conditions (seeded)', () {
      final rng = math.Random(124);
      var accepted = 0;
      var refused = 0;
      for (var c = 0; c < 3000; c++) {
        final freeText = randomText(rng, mixedAlphabet, 1 + rng.nextInt(140));
        final labels = <String>[
          for (var i = rng.nextInt(4); i > 0; i--)
            randomText(rng, mixedAlphabet, 40),
        ];
        final newLabel = '${randomText(rng, mixedAlphabet, 40)}N';
        final next = <String>[...labels, newLabel];
        final budget = quickNoteFreeTextBudget(next);
        final expected =
            composeQuickNote(freeText, next).length <= 140 &&
            budget >= 1 &&
            freeText.length <= budget;
        final actual = canAddQuickNote(
          freeText: freeText,
          labels: labels,
          newLabel: newLabel,
        );
        expect(
          actual,
          expected,
          reason:
              'case $c: F=${show(freeText)} L=${show(labels)} '
              'new=${show(newLabel)}',
        );
        if (actual) {
          accepted++;
          // An accepted add never puts the note over the contract.
          expect(
            composeQuickNote(freeText, next).length,
            lessThanOrEqualTo(140),
          );
        } else {
          refused++;
        }
      }
      expect(accepted, greaterThan(100));
      expect(refused, greaterThan(100));
    });

    test('C3.8 within the budget the composed note always fits (seeded)', () {
      final rng = math.Random(124);
      var checked = 0;
      for (var c = 0; c < 3000; c++) {
        final labels = <String>[
          for (var i = 1 + rng.nextInt(4); i > 0; i--)
            '${randomText(rng, mixedAlphabet, 30)}N',
        ];
        final budget = quickNoteFreeTextBudget(labels);
        if (budget < 1) continue;
        final buffer = StringBuffer();
        final length = rng.nextInt(budget + 1);
        while (buffer.length < length) {
          final token = mixedAlphabet[rng.nextInt(mixedAlphabet.length)];
          if (buffer.length + token.length > length) continue;
          buffer.write(token);
        }
        final freeText = buffer.toString();
        expect(freeText.length, lessThanOrEqualTo(budget));
        expect(
          composeQuickNote(freeText, labels).length,
          lessThanOrEqualTo(140),
          reason: 'case $c: F=${show(freeText)} L=${show(labels)}',
        );
        checked++;
      }
      expect(checked, greaterThan(1000));
    });

    test('C3.9 no helper mutates the label list it is given', () {
      final labels = <String>['No onions', '  Extra crispy ', 'Sauce, on side'];
      final snapshot = List<String>.of(labels);
      final frozen = List<String>.unmodifiable(labels);

      composeQuickNote('well done', labels);
      composeQuickNote('well done', frozen);
      quickNoteFreeTextBudget(labels);
      quickNoteFreeTextBudget(frozen);
      canAddQuickNote(freeText: 'x', labels: labels, newLabel: 'No ice');
      canAddQuickNote(freeText: 'x', labels: frozen, newLabel: 'No ice');
      splitTrailingQuickNotes('well done, Sauce, on side, No onions', labels);
      final split = splitTrailingQuickNotes(
        'well done, Sauce, on side, No onions',
        frozen,
      );

      expect(labels, snapshot);
      expect(split.labelIndexes, <int>[2, 0]);
      // The returned index list is read-only too.
      expect(() => split.labelIndexes.add(1), throwsUnsupportedError);
      expect(
        () => splitTrailingQuickNotes('typed', frozen).labelIndexes.add(1),
        throwsUnsupportedError,
      );
    });
  });

  group('C4. split round trip (seeded)', () {
    /// Labels whose chips can be read back unambiguously: no label is ', '/' '
    /// joined from another label's tail and a further label, and none ends in
    /// an ASCII ',' (after which "typed 'A' + chip 'B'" and "chip 'A,' + chip
    /// 'B'" are the same bytes — see C5.12). Suffix pairs, inner commas,
    /// Arabic/Hebrew, clause enders and an inner line break are all present.
    const recoverablePool = <String>[
      'No onions',
      'Extra crispy',
      'crispy',
      'Sauce, on side',
      'on side',
      'بدون بصل',
      'زيادة صوص،',
      'بدون ثلج؛',
      'בלי בצל',
      'חריף מאוד',
      'Well done;',
      'Allergy — check with kitchen',
      'Takeaway box',
      'Cut in half\nNo crust',
    ];

    /// Free-text characters that can never start a pool label, so no label can
    /// be read out of the typed text or straddle the typed text and the first
    /// chip. (A free text that merely "does not end with a label" is not
    /// enough: typed 'Sauce' + chip 'on side' IS the note 'Sauce, on side' —
    /// see C5.11.)
    const neutralAlphabet = <String>[
      'q',
      'j',
      'k',
      'Q',
      '7',
      '3',
      ' ',
      ',',
      ';',
      '،',
      '؛',
      '\n',
      '-',
      '.',
      'ك',
      'ש',
    ];

    /// Everything, including what makes the split ambiguous: duplicate texts,
    /// a label ending in ',', a label that joins two others, untrimmed text.
    const widePool = <String>[
      ...recoverablePool,
      'A,',
      'B',
      'Sauce',
      'No onions',
      '  Extra crispy  ',
      'n',
      'x',
    ];

    List<int> orderedSubset(math.Random rng, int poolSize, int maxCount) {
      final indexes = List<int>.generate(poolSize, (i) => i)..shuffle(rng);
      return indexes.take(rng.nextInt(maxCount + 1)).toList();
    }

    test('C4.0 the recoverable pool honours its own preconditions', () {
      expect(recoverablePool.toSet().length, recoverablePool.length);
      for (final label in recoverablePool) {
        expect(label, label.trim());
        expect(label.endsWith(','), isFalse);
        expect(neutralAlphabet.contains(label[0]), isFalse, reason: label);
        expect(label.startsWith(','), isFalse);
      }
    });

    void checkRoundTrip(
      String note,
      List<String> pool,
      ({String freeText, List<int> labelIndexes}) split,
      String reason,
    ) {
      final chosen = <String>[for (final i in split.labelIndexes) pool[i]];
      expect(
        composeQuickNote(split.freeText, chosen).codeUnits,
        note.codeUnits,
        reason: '$reason: recomposition is byte-identical',
      );
      expect(
        note.startsWith(split.freeText),
        isTrue,
        reason: '$reason: free text is a prefix',
      );
      expect(
        split.labelIndexes.toSet().length,
        split.labelIndexes.length,
        reason: '$reason: no duplicate indexes',
      );
      expect(
        chosen.map((l) => l.trim()).toSet().length,
        chosen.length,
        reason: '$reason: no label text twice',
      );
      for (final i in split.labelIndexes) {
        expect(i, inInclusiveRange(0, pool.length - 1), reason: reason);
        expect(pool[i].trim(), isNotEmpty, reason: reason);
      }
      if (split.labelIndexes.isNotEmpty) {
        final budget = quickNoteFreeTextBudget(chosen);
        expect(budget, greaterThanOrEqualTo(1), reason: reason);
        expect(
          split.freeText.length,
          lessThanOrEqualTo(budget),
          reason: '$reason: free text fits the budget',
        );
      } else {
        expect(split.freeText, note, reason: '$reason: no chips = verbatim');
      }
    }

    test('C4.1 any composed note round-trips byte for byte (wide pool, '
        'letter-rich free text)', () {
      final rng = math.Random(124);
      var split = 0;
      var withChips = 0;
      for (var c = 0; c < 4000; c++) {
        var freeText = rng.nextInt(4) == 0
            ? ''
            : randomText(rng, mixedAlphabet, 30);
        if (rng.nextInt(4) == 0) {
          // Sometimes the typed text itself ends with a preset phrase.
          freeText = fold(freeText, widePool[rng.nextInt(widePool.length)]);
        }
        final indexes = orderedSubset(rng, widePool.length, 5);
        final labels = <String>[for (final i in indexes) widePool[i]];
        final note = composeQuickNote(freeText, labels).trim();
        final reason =
            'case $c: F=${show(freeText)} T=${show(labels)} n=${show(note)}';
        final result = splitTrailingQuickNotes(note, widePool);
        if (note.length > 140) {
          expect(result.freeText, note, reason: reason);
          expect(result.labelIndexes, isEmpty, reason: reason);
          continue;
        }
        checkRoundTrip(note, widePool, result, reason);
        split++;
        if (result.labelIndexes.isNotEmpty) withChips++;
      }
      expect(split, greaterThan(2000));
      expect(withChips, greaterThan(1000));
    });

    test('C4.2 an unambiguous note gives back exactly the tapped chips, in '
        'tap order', () {
      final rng = math.Random(124);
      var recovered = 0;
      var withChips = 0;
      for (var c = 0; c < 5000; c++) {
        final freeText = rng.nextInt(3) == 0
            ? ''
            : randomText(rng, neutralAlphabet, 40);
        final indexes = orderedSubset(rng, recoverablePool.length, 5);
        final labels = <String>[for (final i in indexes) recoverablePool[i]];
        final composed = composeQuickNote(freeText, labels);
        final note = composed.trim();
        final reason =
            'case $c: F=${show(freeText)} T=${show(labels)} n=${show(note)}';
        if (note.length > 140) continue;

        final result = splitTrailingQuickNotes(note, recoverablePool);
        checkRoundTrip(note, recoverablePool, result, reason);

        // Only notes the sheet itself could have confirmed: no trim effect,
        // and typed text within the budget its chips leave.
        if (note != composed) continue;
        if (labels.isNotEmpty) {
          final budget = quickNoteFreeTextBudget(labels);
          if (budget < 1 || freeText.length > budget) continue;
        }

        expect(
          <String>[for (final i in result.labelIndexes) recoverablePool[i]],
          labels,
          reason: '$reason: chips recovered in tap order',
        );
        recovered++;
        if (labels.isNotEmpty) withChips++;

        // Where the fold kept the typed text whole, it comes back whole.
        final core = coreOf(freeText);
        final trailing = trailingRun(freeText);
        if (labels.isEmpty) {
          expect(result.freeText, freeText, reason: reason);
        } else if (core.isEmpty) {
          expect(result.freeText, '', reason: reason);
        } else if (trailing.contains('\n') ||
            (trailing.isEmpty && !freeText.endsWith(','))) {
          expect(result.freeText, freeText, reason: reason);
        }
      }
      expect(recovered, greaterThan(2000));
      expect(withChips, greaterThan(1500));
    });
  });

  group('C5. split exactness and fallbacks', () {
    const demoLabels = <String>[
      'No onions',
      'No salt',
      'Extra crispy',
      'Well done',
      'Extra spicy',
      'Not spicy',
      'Sauce on the side',
      'No ice',
      'Takeaway box',
      'Allergy — check with kitchen',
    ];

    void expectVerbatim(String note, List<String> labels) {
      final result = splitTrailingQuickNotes(note, labels);
      expect(result.freeText, note, reason: show(note));
      expect(result.labelIndexes, isEmpty, reason: show(note));
      expect(composeQuickNote(result.freeText, const <String>[]), note);
    }

    void expectSplit(
      String note,
      List<String> labels,
      String freeText,
      List<int> indexes,
    ) {
      final result = splitTrailingQuickNotes(note, labels);
      expect(result.freeText, freeText, reason: show(note));
      expect(result.labelIndexes, indexes, reason: show(note));
      expect(
        composeQuickNote(result.freeText, <String>[
          for (final i in result.labelIndexes) labels[i],
        ]),
        note,
        reason: show(note),
      );
    }

    test('C5.1 matching is exact and case-sensitive', () {
      expectVerbatim('no onions', const <String>['No onions']);
      expectVerbatim('Burger, no onions', const <String>['No onions']);
      expectVerbatim('Burger, No Onions', const <String>['No onions']);
      expectSplit(
        'Burger, No onions',
        const <String>['No onions'],
        'Burger',
        [0],
      );
    });

    test('C5.2 an unknown or renamed preset stays text', () {
      expectVerbatim('Burger, No onion', const <String>['No onions']);
      expectVerbatim('well done, Extra crispy', const <String>[
        'Extra crispy!',
      ]);
      expectVerbatim('Burger, No onions', const <String>['No onions please']);
      expectVerbatim('Burger, No onions', const <String>['Extra crispy']);
    });

    test('C5.3 a phrase in the middle, or not separated, stays text', () {
      expectVerbatim('No onions, well done', const <String>['No onions']);
      expectVerbatim('Burger No onions', const <String>['No onions']);
      expectVerbatim('Burger, No onions ', const <String>['No onions']);
    });

    test('C5.4 each label at most once; the rest stays text', () {
      expectSplit(
        'No onions, No onions',
        const <String>['No onions'],
        'No onions',
        [0],
      );
      // Duplicate texts in the preset list: one chip, the first index.
      expectSplit(
        'No onions',
        const <String>['No onions', 'No onions'],
        '',
        [0],
      );
    });

    test('C5.5 longest label first', () {
      expectSplit(
        'X, Sauce, on side',
        const <String>['on side', 'Sauce, on side'],
        'X',
        [1],
      );
      expectSplit(
        'X, on side, Sauce, on side',
        const <String>['on side', 'Sauce, on side'],
        'X',
        [0, 1],
      );
    });

    test('C5.6 chips come back in note order with their list indexes', () {
      expectSplit(
        'well done, No onions, Extra crispy',
        demoLabels,
        'well done', // typed lower-case: not the 'Well done' preset
        [0, 2],
      );
      expectSplit(
        'Burger, No onions, Extra crispy',
        const <String>['', 'Extra crispy', '  ', 'No onions'],
        'Burger',
        [3, 1],
      );
      // Outer whitespace on a stored label does not stop a match.
      expectSplit(
        'Burger, No onions',
        const <String>['  No onions  '],
        'Burger',
        [0],
      );
      // The whole note can be chips.
      expectSplit('No onions, Extra crispy', demoLabels, '', [0, 2]);
    });

    test('C5.7 separators other than ", " come back exactly', () {
      expectSplit(
        'abc، Extra crispy',
        const <String>['Extra crispy'],
        'abc،',
        [0],
      );
      expectSplit(
        'abc; Extra crispy',
        const <String>['Extra crispy'],
        'abc;',
        [0],
      );
      expectSplit(
        'Burger\nNo onions',
        const <String>['No onions'],
        'Burger\n',
        [0],
      );
      // Blank presets never come back as boxes, even where a blank label
      // would otherwise "match" (after a kept line break).
      expectSplit(
        'Burger\nNo onions',
        const <String>['No onions', '  ', ''],
        'Burger\n',
        [0],
      );
      expectSplit('בלי בצל, חריף', const <String>['חריף'], 'בלי בצל', [0]);
      expectSplit(
        'بدون بصل، زيادة صوص',
        const <String>['زيادة صوص'],
        'بدون بصل،',
        [0],
      );
    });

    test('C5.8 a whitespace-only prefix the fold could not have produced '
        'stays verbatim', () {
      // Folding 'No onions' onto whitespace gives 'No onions' alone, so these
      // notes are not a recomposition of anything: no chips.
      for (final note in const <String>[
        '   No onions',
        '\nNo onions',
        ' \n No onions',
      ]) {
        expect(
          composeQuickNote(note.substring(0, note.length - 9), const [
            'No onions',
          ]),
          'No onions',
        );
        expectVerbatim(note, const <String>['No onions']);
      }
    });

    test('C5.9 over the note limit or over the typing budget: verbatim', () {
      // 129 + ', No onions' = 140: splits (the typed text fits 129)...
      expectSplit(
        '${'x' * 129}, No onions',
        const <String>['No onions'],
        'x' * 129,
        [0],
      );
      // ...141 is over the note contract: verbatim.
      expectVerbatim('${'x' * 130}, No onions', const <String>['No onions']);

      // 140 by composition, but the typed text (131 / 130) would exceed the
      // 129-character budget the chip leaves: verbatim.
      expectVerbatim('${'x' * 130}\nNo onions', const <String>['No onions']);
      expectVerbatim('${'x' * 129}، No onions', const <String>['No onions']);
      // One character shorter fits: splits.
      expectSplit(
        '${'x' * 128}\nNo onions',
        const <String>['No onions'],
        '${'x' * 128}\n',
        [0],
      );

      // A note that is only chips needs at least one character of room.
      final chips137 = '${'A' * 60}, ${'B' * 75}';
      expectSplit(chips137, <String>['A' * 60, 'B' * 75], '', [0, 1]);
      final chips138 = '${'A' * 60}, ${'B' * 76}';
      expectVerbatim(chips138, <String>['A' * 60, 'B' * 76]);
    });

    test('C5.10 nothing to split: verbatim', () {
      expectVerbatim('No onions', const <String>[]);
      expectVerbatim('No onions', const <String>['', '   ']);
      final empty = splitTrailingQuickNotes('', const <String>['No onions']);
      expect(empty.freeText, '');
      expect(empty.labelIndexes, isEmpty);
    });

    test('C5.11 a longer label wins even across the typed text', () {
      // Typed 'Sauce' + chip 'on side' and a lone chip 'Sauce, on side' are
      // the same bytes; the documented longest-first rule decides.
      expect(
        composeQuickNote('Sauce', const <String>['on side']),
        'Sauce, on side',
      );
      expectSplit(
        'Sauce, on side',
        const <String>['on side', 'Sauce, on side'],
        '',
        [1],
      );
    });

    test('C5.12 a comma-ending label before another chip is ambiguous; any '
        'reading is byte-identical', () {
      expect(composeQuickNote('', const <String>['A,', 'B']), 'A, B');
      expect(composeQuickNote('A', const <String>['B']), 'A, B');
      final result = splitTrailingQuickNotes('A, B', const <String>['A,', 'B']);
      expect(result.labelIndexes, isNotEmpty);
      expect(result.labelIndexes.last, 1);
      expect(
        composeQuickNote(result.freeText, <String>[
          for (final i in result.labelIndexes) const <String>['A,', 'B'][i],
        ]),
        'A, B',
      );
      expect(const <String>['A', ''], contains(result.freeText));
    });
  });

  group('C6. removing a chip strictly shrinks the note (seeded)', () {
    test('C6.1 confirmed note shorter, budget larger, for every chip '
        'removed', () {
      final rng = math.Random(124);
      const pool = <String>[
        'No onions',
        'Extra crispy',
        'Sauce, on side',
        'on side',
        'A,',
        'B',
        'زيادة صوص،',
        'בלי בצל',
        'Well done;',
        '  Takeaway box ',
        'Cut in half\nNo crust',
      ];
      var checked = 0;
      var untrimmedChecked = 0;
      for (var c = 0; c < 2000; c++) {
        final freeText = rng.nextInt(4) == 0
            ? ''
            : randomText(rng, mixedAlphabet, 30);
        final labels = <String>[
          for (var i = 1 + rng.nextInt(5); i > 0; i--)
            rng.nextBool()
                ? pool[rng.nextInt(pool.length)]
                : '${randomText(rng, mixedAlphabet, 8)}${'xbص'[rng.nextInt(3)]}',
        ];
        final full = composeQuickNote(freeText, labels);
        final fullBudget = quickNoteFreeTextBudget(labels);
        for (var i = 0; i < labels.length; i++) {
          final without = <String>[...labels]..removeAt(i);
          final reduced = composeQuickNote(freeText, without);
          final reason =
              'case $c: F=${show(freeText)} T=${show(labels)} remove=$i';
          // The note the sheet confirms (trimmed) always shrinks.
          expect(
            reduced.trim().length,
            lessThan(full.trim().length),
            reason: reason,
          );
          // The raw fold shrinks too, except when the LAST chip goes and the
          // typed text ends in whitespace: with no chips the typed text is
          // returned verbatim, whitespace included (see C6.2).
          if (without.isNotEmpty || trailingRun(freeText).isEmpty) {
            expect(reduced.length, lessThan(full.length), reason: reason);
            untrimmedChecked++;
          }
          expect(
            quickNoteFreeTextBudget(without),
            greaterThan(fullBudget),
            reason: reason,
          );
          checked++;
        }
      }
      expect(checked, greaterThan(4000));
      expect(untrimmedChecked, greaterThan(3000));
    });

    test('C6.2 removing the last chip returns the typed text verbatim, '
        'trailing whitespace included', () {
      // The fold drops the typed text's trailing spaces in front of a chip,
      // so the raw lengths can tie or even grow; the trimmed note shrinks.
      expect(composeQuickNote('x;   ', const <String>['A,']), 'x; A,');
      expect(composeQuickNote('x;   ', const <String>[]), 'x;   ');
      expect(composeQuickNote('     ', const <String>['A']), 'A');
      expect(composeQuickNote('     ', const <String>[]), '     ');
      expect(composeQuickNote('     ', const <String>[]).trim(), '');
    });
  });
}
