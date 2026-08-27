import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/format/quick_note_insertion.dart';

/// POS-QUICK-NOTES-124 — the composition rules, exercised directly.
///
/// This helper is the whole feature's risk surface: it writes into the field
/// whose text becomes `order_items.notes`, and a programmatic write is not
/// bounded by the field's own `maxLength`. So the two properties that matter
/// are stated as tests rather than as comments — the composed text is exactly
/// what a careful person would have typed, and it is NEVER truncated.
void main() {
  String? apply(
    String current,
    String preset, {
    int max = kPosItemNoteMaxLength,
  }) => buildQuickNoteInsertion(current, preset, maxLength: max).text;

  group('A. an empty field', () {
    test('A1. empty becomes the preset', () {
      expect(apply('', 'No onions'), 'No onions');
    });

    test('A2. whitespace-only becomes the preset — spaces are not content', () {
      expect(apply('   ', 'No onions'), 'No onions');
      expect(apply('\n\n', 'No onions'), 'No onions');
      expect(apply(' \t \n ', 'No onions'), 'No onions');
    });
  });

  group('B. appending to real text', () {
    test('B1. the canonical separator is ", "', () {
      expect(apply('No onions', 'Extra crispy'), 'No onions, Extra crispy');
    });

    test('B2. an existing comma is honoured, never doubled', () {
      expect(apply('No onions,', 'Extra crispy'), 'No onions, Extra crispy');
      expect(apply('No onions, ', 'Extra crispy'), 'No onions, Extra crispy');
    });

    test('B3. an Arabic comma is a comma', () {
      // A cashier typing Arabic ends a clause with '،'. Appending ", " after it
      // would read as two marks in a row on the kitchen ticket.
      expect(apply('بدون بصل،', 'مقرمش'), 'بدون بصل، مقرمش');
      expect(apply('بدون بصل، ', 'مقرمش'), 'بدون بصل، مقرمش');
    });

    test('B4. semicolons, Latin and Arabic, behave the same way', () {
      expect(apply('No onions;', 'Extra crispy'), 'No onions; Extra crispy');
      expect(apply('بدون بصل؛', 'مقرمش'), 'بدون بصل؛ مقرمش');
    });

    test('B5. a deliberate line break is kept — no comma, no extra space', () {
      expect(apply('No onions\n', 'Extra crispy'), 'No onions\nExtra crispy');
      expect(apply('No onions,\n', 'Extra crispy'), 'No onions,\nExtra crispy');
    });

    test('B6. a trailing space before ordinary text still gets ", "', () {
      expect(apply('No onions ', 'Extra crispy'), 'No onions, Extra crispy');
    });

    test('B7. the cashier\'s own internal text is never reformatted', () {
      // Double spaces, casing and stray punctuation INSIDE what they typed are
      // theirs. Only the trailing run is inspected.
      expect(
        apply('no  ONIONS  please', 'Extra crispy'),
        'no  ONIONS  please, Extra crispy',
      );
    });

    test('B8. a preset with inner spacing keeps it exactly', () {
      expect(apply('', 'Sauce  on   the side'), 'Sauce  on   the side');
    });
  });

  group('C. the 140-character contract', () {
    test('C1. a candidate of exactly 140 is accepted', () {
      final current = 'x' * 127; // 127 + ', ' (2) + 11 = 140
      final result = buildQuickNoteInsertion(current, 'Extra crisp');
      expect(result.text, hasLength(140));
      expect(result.refusedForLength, isFalse);
    });

    test('C2. a candidate of 141 is REFUSED — nothing is written', () {
      final current = 'x' * 128; // 128 + 2 + 11 = 141
      final result = buildQuickNoteInsertion(current, 'Extra crisp');
      expect(result.text, isNull);
      expect(result.refusedForLength, isTrue);
      expect(result.isApplied, isFalse);
    });

    test('C3. a refusal NEVER truncates the preset or the note', () {
      final current = 'x' * 138;
      final result = buildQuickNoteInsertion(current, 'No onions');
      expect(result.text, isNull);
      // The caller keeps the field exactly as it was; half an instruction
      // ("no oni") reaching the kitchen is worse than no instruction.
      expect(result.refusedForLength, isTrue);
    });

    test(
      'C4. the limit is measured on the FINAL string, separator included',
      () {
        // 139 characters plus a 1-character preset is 140 on its own, but 142
        // once the ", " separator is counted — so it is refused.
        expect(buildQuickNoteInsertion('x' * 139, 'y').text, isNull);
        // 137 + 2 + 1 lands exactly on the limit and is accepted.
        expect(buildQuickNoteInsertion('x' * 137, 'y').text, hasLength(140));
      },
    );
  });

  group('D. repeated taps and edge inputs', () {
    test('D1. tapping the same chip twice appends twice, predictably', () {
      final once = apply('', 'No onions')!;
      final twice = apply(once, 'No onions');
      // Deliberately NOT deduplicated: preset text may itself contain commas,
      // so any "already there?" heuristic would misfire exactly when it counts.
      expect(twice, 'No onions, No onions');
    });

    test('D2. a blank preset changes nothing and is not an error', () {
      final result = buildQuickNoteInsertion('No onions', '   ');
      expect(result.text, 'No onions');
      expect(result.refusedForLength, isFalse);
    });

    test(
      'D3. preset outer whitespace is trimmed, so nothing stray is pasted',
      () {
        expect(
          apply('No onions', '  Extra crispy  '),
          'No onions, Extra crispy',
        );
      },
    );

    test('D4. no marker, token or id ever appears in the text', () {
      final text = apply('No onions', 'Extra crispy')!;
      expect(text, 'No onions, Extra crispy');
      expect(text.contains('#'), isFalse);
      expect(text.contains('{'), isFalse);
    });
  });
}
