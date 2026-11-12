// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F: source pins of the card flow — the Edge
// still ships without a provider profile, the card UI holds no hard-coded
// words, and the card files stay out of the order action row, printing and
// receipt rendering (execution packet §2, §11, §12).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

const List<String> _cardFiles = <String>[
  'lib/src/data/provider_card_attempt.dart',
  'lib/src/data/provider_card_capability.dart',
  'lib/src/data/provider_card_edge.dart',
  'lib/src/data/provider_card_recording.dart',
  'lib/src/data/provider_card_store.dart',
  'lib/src/format/provider_card_presentation.dart',
  'lib/src/state/provider_card_controller.dart',
  'lib/src/widgets/provider_card_payment_view.dart',
];

/// The import lines of [source], joined with any continuation lines.
List<String> _imports(String source) {
  final out = <String>[];
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].startsWith('import ')) continue;
    final b = StringBuffer(lines[i]);
    while (!lines[i].trimRight().endsWith(';') && i + 1 < lines.length) {
      b.write(lines[++i]);
    }
    out.add(b.toString());
  }
  return out;
}

void main() {
  test('the Edge still ships with no provider profile', () {
    final index = _read('../../supabase/functions/pos-card-charge/index.ts');
    expect(RegExp(r'providerProfile\s*:').allMatches(index), hasLength(1));
    expect(index, contains('providerProfile: null,'));
  });

  test('the card UI words all come from the localizations', () {
    final literal = RegExp(
      r'''Text\(\s*['"]|\b(title|body|label|tooltip|semanticsLabel|message)\s*:\s*['"]''',
    );
    for (final path in <String>[
      'lib/src/widgets/provider_card_payment_view.dart',
      'lib/src/format/provider_card_presentation.dart',
    ]) {
      expect(literal.hasMatch(_read(path)), isFalse, reason: path);
    }
  });

  test('the card files import nothing of the order action row, printing or '
      'receipt rendering', () {
    var seen = 0;
    for (final path in _cardFiles) {
      for (final line in _imports(_read(path))) {
        seen++;
        expect(line, isNot(contains('order_action_row')), reason: path);
        expect(line, isNot(contains('restoflow_printing')), reason: path);
        expect(line, isNot(contains('/print/')), reason: path);
        expect(line, isNot(contains('receipt')), reason: path);
      }
    }
    expect(seen, greaterThan(_cardFiles.length), reason: 'imports were read');
  });
}
