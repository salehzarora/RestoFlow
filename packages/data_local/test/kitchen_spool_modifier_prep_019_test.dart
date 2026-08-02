import 'dart:convert' show json, utf8;
import 'dart:typed_data';

import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:test/test.dart';

/// KITCHEN-MODIFIER-PREP-CLASSIFIER-019 — the durable spool half.
///
/// Saleh's meat comes from the SIZE option, so it travels as a MODIFIER
/// contribution. Before this feature the server projected each modifier as
/// {qty, name} only, and the closed decoder had no field for anything else — so
/// the contribution never reached the encrypted local spool at all. The direct
/// print and the KDS showed it; the crash-recovery ticket did not.
void main() {
  Map<String, Object?> modifier({
    Object? quantity = 2,
    Object? unit = 'Meat pieces',
    Object? id = 'opt-cheese',
    Object? name = 'Cheese',
    Object? selected = true,
    bool includePrep = true,
    bool includeId = true,
    bool includeName = true,
    bool includeSelected = true,
  }) => <String, Object?>{
    'qty': 1,
    'name': '240g',
    if (includePrep)
      'prep': <String, Object?>{
        if (quantity != null) 'quantity': quantity,
        if (unit != null) 'unit': unit,
        if (includeId) 'classifier_option_id': id,
        if (includeName) 'classifier_option_name': name,
        if (includeSelected) 'classifier_selected': selected,
      },
  };

  Map<String, Object?> dispatchJson({
    required String kind,
    required List<Map<String, Object?>> modifiers,
    int? roundNumber,
  }) => <String, Object?>{
    'v': 1,
    'kind': kind,
    'order_code': '#000042',
    'order_type': 'dine_in',
    if (roundNumber != null) ...<String, Object?>{
      'round_id': 'round-2',
      'round_number': roundNumber,
    },
    'items': [
      <String, Object?>{
        'qty': 1,
        'name': 'Burger',
        'prep': [
          <String, Object?>{'name': 'Bread', 'quantity': 1, 'unit': 'Piece'},
        ],
        'modifiers': modifiers,
      },
    ],
  };

  Map<String, Object?> payloadJson(Map<String, Object?> dispatch) =>
      <String, Object?>{
        'v': 1,
        'purpose': kKitchenSpoolPurpose,
        'dispatch': dispatch,
        'destination': <String, Object?>{
          'kind': 'network',
          'host': '10.0.0.9',
          'port': 9100,
        },
        'paper_width': '80mm',
        'document_version': 1,
        'raster_version': 1,
      };

  KitchenSpoolLocalPayload decode(Map<String, Object?> dispatch) =>
      KitchenSpoolLocalPayload.fromJson(payloadJson(dispatch));

  KitchenDispatchModifier firstModifier(Map<String, Object?> dispatch) =>
      decode(dispatch).dispatch.items.single.modifiers.first;

  group('J. initial durable ticket carries the contribution', () {
    test('quantity, unit and the classifier triple all survive', () {
      final m = firstModifier(
        dispatchJson(kind: 'initial_order', modifiers: [modifier()]),
      );
      expect(m.name, '240g');
      expect(m.prep, isNotNull);
      expect(m.prep!.quantity, 2);
      expect(m.prep!.unit, 'Meat pieces');
      expect(m.prep!.classifierOptionId, 'opt-cheese');
      expect(m.prep!.classifierOptionName, 'Cheese');
      expect(m.prep!.classifierSelected, isTrue);
      expect(m.prep!.isClassified, isTrue);
    });

    test('the without-bucket survives as FALSE, not as an absent field', () {
      final m = firstModifier(
        dispatchJson(
          kind: 'initial_order',
          modifiers: [modifier(selected: false)],
        ),
      );
      expect(m.prep!.classifierSelected, isFalse);
      expect(m.prep!.isClassified, isTrue);
    });

    test('the item-level Bread prep is untouched alongside it', () {
      final item = decode(
        dispatchJson(kind: 'initial_order', modifiers: [modifier()]),
      ).dispatch.items.single;
      expect(item.prep.single.name, 'Bread');
      expect(item.prep.single.quantity, 1);
    });
  });

  group('K. Add-items round durable ticket', () {
    test('a round dispatch preserves the contribution too', () {
      final payload = decode(
        dispatchJson(
          kind: 'service_round',
          roundNumber: 2,
          modifiers: [modifier(selected: false)],
        ),
      );
      expect(payload.dispatch.roundNumber, 2);
      final m = payload.dispatch.items.single.modifiers.first;
      expect(m.prep!.isClassified, isTrue);
      expect(m.prep!.classifierSelected, isFalse);
    });
  });

  group('J. restart / reload / retry', () {
    test('bytes -> payload -> bytes is stable and keeps everything', () {
      final original = decode(
        dispatchJson(kind: 'initial_order', modifiers: [modifier()]),
      );
      final bytes = original.toBytes();
      final reloaded = KitchenSpoolLocalPayload.fromBytes(bytes);
      final m = reloaded.dispatch.items.single.modifiers.first;
      expect(m.prep!.classifierOptionName, 'Cheese');
      expect(m.prep!.quantity, 2);
      expect(reloaded.toBytes(), bytes, reason: 'a retry cannot drift');
    });

    test('several reload cycles keep the classification', () {
      var bytes = decode(
        dispatchJson(kind: 'initial_order', modifiers: [modifier()]),
      ).toBytes();
      for (var attempt = 0; attempt < 3; attempt++) {
        final p = KitchenSpoolLocalPayload.fromBytes(bytes);
        expect(
          p.dispatch.items.single.modifiers.first.prep!.isClassified,
          isTrue,
        );
        bytes = p.toBytes();
      }
    });

    test('the encoded payload carries no money vocabulary', () {
      final encoded = utf8.decode(
        decode(
          dispatchJson(kind: 'initial_order', modifiers: [modifier()]),
        ).toBytes(),
      );
      final decoded = json.decode(encoded) as Map<String, Object?>;
      expect(
        () => rejectHostileKitchenKeys(decoded['dispatch'], path: 'dispatch'),
        returnsNormally,
      );
      expect(encoded.contains('minor'), isFalse);
    });
  });

  group('M. legacy payloads decode unchanged', () {
    test('a modifier with no prep key decodes as before', () {
      final m = firstModifier(
        dispatchJson(
          kind: 'initial_order',
          modifiers: [modifier(includePrep: false)],
        ),
      );
      expect(m.prep, isNull);
      expect(m.qty, 1);
      expect(m.name, '240g');
    });

    test('and re-encodes byte-identically', () {
      final m = firstModifier(
        dispatchJson(
          kind: 'initial_order',
          modifiers: [modifier(includePrep: false)],
        ),
      );
      expect(m.toJson(), {'qty': 1, 'name': '240g'});
    });

    test('an UNCLASSIFIED contribution survives and re-encodes cleanly', () {
      final m = firstModifier(
        dispatchJson(
          kind: 'initial_order',
          modifiers: [
            modifier(
              includeId: false,
              includeName: false,
              includeSelected: false,
            ),
          ],
        ),
      );
      expect(m.prep!.isClassified, isFalse);
      expect(m.prep!.quantity, 2);
      expect(m.toJson(), {
        'qty': 1,
        'name': '240g',
        'prep': {'quantity': 2, 'unit': 'Meat pieces'},
      });
    });
  });

  group('malformed classifier metadata degrades, never rejects', () {
    Uint8List bytesOf(Map<String, Object?> dispatch) =>
        Uint8List.fromList(utf8.encode(json.encode(payloadJson(dispatch))));

    test('a non-string id degrades to unsplit and KEEPS the ticket', () {
      final payload = KitchenSpoolLocalPayload.fromBytes(
        bytesOf(
          dispatchJson(
            kind: 'initial_order',
            modifiers: [
              modifier(id: <String, Object?>{'nested': 'x'}),
            ],
          ),
        ),
      );
      final m = payload.dispatch.items.single.modifiers.first;
      expect(m.prep!.isClassified, isFalse);
      expect(m.prep!.quantity, 2, reason: 'the contribution survives');
      expect(m.name, '240g');
      expect(payload.dispatch.items.single.name, 'Burger');
    });

    test('a non-boolean answer degrades to unsplit', () {
      final m = firstModifier(
        dispatchJson(
          kind: 'initial_order',
          modifiers: [modifier(selected: 'yes')],
        ),
      );
      expect(m.prep!.isClassified, isFalse);
      expect(m.prep!.quantity, 2);
    });

    test('an INCOMPLETE triple is not a classification', () {
      for (final partial in [
        modifier(includeSelected: false),
        modifier(includeName: false),
        modifier(includeId: false),
      ]) {
        final m = firstModifier(
          dispatchJson(kind: 'initial_order', modifiers: [partial]),
        );
        expect(m.prep!.isClassified, isFalse, reason: '$partial');
        expect(m.prep!.quantity, 2);
      }
    });

    test('a degraded contribution re-encodes WITHOUT the bad keys', () {
      final m = firstModifier(
        dispatchJson(kind: 'initial_order', modifiers: [modifier(selected: 3)]),
      );
      expect(m.toJson(), {
        'qty': 1,
        'name': '240g',
        'prep': {'quantity': 2, 'unit': 'Meat pieces'},
      });
    });

    test('a genuinely unknown key is still REJECTED (decode stays closed)', () {
      expect(
        () => firstModifier(
          dispatchJson(
            kind: 'initial_order',
            modifiers: [
              <String, Object?>{
                'qty': 1,
                'name': '240g',
                'prep': <String, Object?>{'quantity': 2, 'colour': 'red'},
              },
            ],
          ),
        ),
        throwsA(isA<KitchenSpoolPayloadFormatException>()),
      );
    });

    test('a non-object prep is still corruption', () {
      expect(
        () => firstModifier(
          dispatchJson(
            kind: 'initial_order',
            modifiers: [
              <String, Object?>{'qty': 1, 'name': '240g', 'prep': 'nope'},
            ],
          ),
        ),
        throwsA(isA<KitchenSpoolPayloadFormatException>()),
      );
    });

    test('a non-positive contribution quantity is still strict', () {
      expect(
        () => firstModifier(
          dispatchJson(
            kind: 'initial_order',
            modifiers: [
              <String, Object?>{
                'qty': 1,
                'name': '240g',
                'prep': <String, Object?>{'quantity': 0},
              },
            ],
          ),
        ),
        throwsA(isA<KitchenSpoolPayloadFormatException>()),
      );
    });
  });
}
