import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_pos/src/spool/kitchen_ticket_renderer.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// KITCHEN-MODIFIER-PREP-CLASSIFIER-CODEX-FIX-020 — Codex HIGH #3, the CLIENT
/// half of the quantity gate.
///
/// The server projection now refuses to emit a contribution without a positive
/// quantity, but a durable spool row written by an older server can still carry
/// one. Against HEAD the renderer printed that row anyway, producing a bullet
/// that names a kitchen resource with no count — an instruction the line cannot
/// act on. These exercise the REAL renderer over REAL decoded payloads.
KitchenDispatchDocument _doc(KitchenDispatchModifierPrep? prep) =>
    KitchenDispatchDocument(
      serverPayloadVersion: 1,
      kind: KitchenSpoolDispatchType.initialOrder,
      orderCode: '#000042',
      orderType: 'dine_in',
      createdAt: '2026-07-20T10:00:00Z',
      items: [
        KitchenDispatchItem(
          qty: 1,
          name: 'Burger',
          modifiers: [
            KitchenDispatchModifier(qty: 1, name: '240g', prep: prep),
          ],
        ),
      ],
    );

String _texts(pp.PrintDocument doc) => [
  for (final line in doc.lines)
    if (line is pp.PrintTextLine) line.text,
].join('\n');

/// Decodes through the SAME strict reader the durable spool uses, so the test
/// pins what a stored payload actually becomes — not a hand-built model.
KitchenDispatchModifierPrep _decode(Map<String, Object?> raw) =>
    KitchenDispatchModifierPrep.fromJson(raw);

void main() {
  const renderer = KitchenTicketRenderer();

  test('020-R1. a unit-only contribution prints NO bullet', () {
    final prep = _decode(<String, Object?>{'unit': 'Meat pieces'});
    final texts = _texts(renderer.buildDocument(_doc(prep)));
    expect(texts, contains('+ 240g'));
    expect(
      texts,
      isNot(contains('Meat pieces')),
      reason: 'a resource named with no count is unactionable',
    );
  });

  test('020-R2. a unit-only CLASSIFIED contribution prints NO bullet', () {
    final prep = _decode(<String, Object?>{
      'unit': 'Meat pieces',
      'classifier_option_id': 'opt-cheese',
      'classifier_option_name': 'Cheese',
      'classifier_selected': true,
    });
    expect(prep.isClassified, isTrue);
    final texts = _texts(renderer.buildDocument(_doc(prep)));
    expect(texts, isNot(contains('Meat pieces')));
    expect(texts, isNot(contains('Cheese')));
  });

  test('020-R3. a quantity-less, unit-less contribution prints NO bullet', () {
    final prep = _decode(const <String, Object?>{});
    final before = _texts(renderer.buildDocument(_doc(null)));
    expect(_texts(renderer.buildDocument(_doc(prep))), before);
  });

  test('020-R4. a REAL contribution still prints, unchanged', () {
    final prep = _decode(<String, Object?>{
      'quantity': 2,
      'unit': 'Meat pieces',
    });
    expect(prep.isRenderable, isTrue);
    expect(
      _texts(renderer.buildDocument(_doc(prep))),
      contains('• 2 Meat pieces'),
    );
  });

  test('020-R5. a REAL classified contribution still splits, unchanged', () {
    final prep = _decode(<String, Object?>{
      'quantity': 2,
      'unit': 'Meat pieces',
      'classifier_option_id': 'opt-cheese',
      'classifier_option_name': 'Cheese',
      'classifier_selected': true,
    });
    final texts = _texts(renderer.buildDocument(_doc(prep)));
    expect(texts, contains('Meat pieces'));
    expect(texts, contains('Cheese'));
  });
}
