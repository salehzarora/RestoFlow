import 'dart:convert' show json, utf8;
import 'dart:typed_data';

import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:test/test.dart';

/// KITCHEN-PREP-MODIFIER-SPLIT-CODEX-FIX-017 — Codex BLOCKER #1, spool half.
///
/// The durable spool is what the kitchen actually receives after a crash or a
/// retry. Before this fix the closed payload model had no field for the 016
/// classifier triple at all: the server projection dropped it, and had it not,
/// `finish()` would have rejected the WHOLE otherwise-valid ticket as carrying
/// an unknown key — losing the paper entirely.
///
/// The decode is now DEGRADING for exactly these three optional fields and
/// strict everywhere else: a malformed classifier costs the split and nothing
/// more.
void main() {
  Map<String, Object?> prepJson({
    Object? id = 'opt-cheese',
    Object? name = 'Cheese',
    Object? selected = true,
    bool includeId = true,
    bool includeName = true,
    bool includeSelected = true,
  }) => <String, Object?>{
    'name': 'Meat pieces',
    'quantity': 2,
    if (includeId) 'classifier_option_id': id,
    if (includeName) 'classifier_option_name': name,
    if (includeSelected) 'classifier_selected': selected,
  };

  Map<String, Object?> dispatchJson({
    required String kind,
    required List<Map<String, Object?>> prep,
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
        'qty': 2,
        'name': 'Burger 240g',
        'prep': prep,
        'modifiers': [
          <String, Object?>{'qty': 1, 'name': 'Cheese'},
        ],
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

  KitchenDispatchPrepComponent decodedPrep(Map<String, Object?> dispatch) =>
      KitchenSpoolLocalPayload.fromJson(
        payloadJson(dispatch),
      ).dispatch.items.single.prep.single;

  group('B1/B2. initial and Add-items durable tickets carry the split', () {
    test('an INITIAL durable ticket preserves the classifier triple', () {
      final prep = decodedPrep(
        dispatchJson(kind: 'initial_order', prep: [prepJson()]),
      );
      expect(prep.name, 'Meat pieces');
      expect(prep.quantity, 2);
      expect(prep.classifierOptionId, 'opt-cheese');
      expect(prep.classifierOptionName, 'Cheese');
      expect(prep.classifierSelected, isTrue);
      expect(prep.isClassified, isTrue);
    });

    test('an ADD-ITEMS round durable ticket preserves it too', () {
      final payload = KitchenSpoolLocalPayload.fromJson(
        payloadJson(
          dispatchJson(
            kind: 'service_round',
            roundNumber: 2,
            prep: [prepJson(selected: false)],
          ),
        ),
      );
      expect(payload.dispatch.roundNumber, 2);
      final prep = payload.dispatch.items.single.prep.single;
      expect(prep.isClassified, isTrue);
      expect(prep.classifierSelected, isFalse);
    });

    test('the without-bucket survives as FALSE, not as an absent field', () {
      final prep = decodedPrep(
        dispatchJson(kind: 'initial_order', prep: [prepJson(selected: false)]),
      );
      expect(prep.classifierSelected, isFalse);
      expect(prep.isClassified, isTrue);
    });
  });

  group('B3. encode/decode round-trip survives a restart', () {
    test('bytes -> payload -> bytes is stable and keeps the classifier', () {
      final original = KitchenSpoolLocalPayload.fromJson(
        payloadJson(dispatchJson(kind: 'initial_order', prep: [prepJson()])),
      );
      // What the encrypted blob holds; a reload decodes exactly this.
      final bytes = original.toBytes();
      final reloaded = KitchenSpoolLocalPayload.fromBytes(bytes);
      final prep = reloaded.dispatch.items.single.prep.single;
      expect(prep.classifierOptionId, 'opt-cheese');
      expect(prep.classifierOptionName, 'Cheese');
      expect(prep.classifierSelected, isTrue);
      // A second round-trip is byte-identical — a retry cannot drift.
      expect(reloaded.toBytes(), bytes);
    });

    test('a retry re-decodes the SAME classifier after several reloads', () {
      var bytes = KitchenSpoolLocalPayload.fromJson(
        payloadJson(dispatchJson(kind: 'initial_order', prep: [prepJson()])),
      ).toBytes();
      for (var attempt = 0; attempt < 3; attempt++) {
        final payload = KitchenSpoolLocalPayload.fromBytes(bytes);
        expect(payload.dispatch.items.single.prep.single.isClassified, isTrue);
        bytes = payload.toBytes();
      }
    });

    test('the encoded prep carries no money vocabulary', () {
      final encoded = utf8.decode(
        KitchenSpoolLocalPayload.fromJson(
          payloadJson(dispatchJson(kind: 'initial_order', prep: [prepJson()])),
        ).toBytes(),
      );
      final decoded = json.decode(encoded) as Map<String, Object?>;
      // The hostile-key validator must still accept the classifier keys.
      expect(
        () => rejectHostileKitchenKeys(decoded['dispatch'], path: 'dispatch'),
        returnsNormally,
      );
      expect(encoded.contains('minor'), isFalse);
    });
  });

  group('B4. legacy payloads decode unchanged', () {
    test('prep without any classifier field decodes as unsplit', () {
      final prep = decodedPrep(
        dispatchJson(
          kind: 'initial_order',
          prep: [
            <String, Object?>{'name': 'Meat pieces', 'quantity': 2},
          ],
        ),
      );
      expect(prep.isClassified, isFalse);
      expect(prep.classifierOptionId, isNull);
      expect(prep.name, 'Meat pieces');
      expect(prep.quantity, 2);
    });

    test('a legacy component re-encodes byte-identically', () {
      const legacy = <String, Object?>{'name': 'Meat pieces', 'quantity': 2};
      final prep = decodedPrep(
        dispatchJson(kind: 'initial_order', prep: [legacy]),
      );
      expect(prep.toJson(), legacy);
    });
  });

  group('B5. malformed classifier types fail safe, never reject', () {
    Uint8List _bytes(Map<String, Object?> dispatch) =>
        Uint8List.fromList(utf8.encode(json.encode(payloadJson(dispatch))));

    test('a non-string id degrades to unsplit and KEEPS the ticket', () {
      final payload = KitchenSpoolLocalPayload.fromBytes(
        _bytes(
          dispatchJson(
            kind: 'initial_order',
            prep: [
              prepJson(id: <String, Object?>{'nested': 'x'}),
            ],
          ),
        ),
      );
      final prep = payload.dispatch.items.single.prep.single;
      expect(prep.isClassified, isFalse);
      // The resource — and the whole ticket — survived.
      expect(prep.name, 'Meat pieces');
      expect(prep.quantity, 2);
      expect(payload.dispatch.items.single.name, 'Burger 240g');
    });

    test('a MONEY key smuggled into the classifier is rejected outright', () {
      // The pre-existing defence-in-depth validator runs BEFORE typed decoding
      // and is deliberately stronger than degradation: money vocabulary may not
      // appear anywhere in the server-derived subtree, at any nesting level.
      expect(
        () => KitchenSpoolLocalPayload.fromBytes(
          _bytes(
            dispatchJson(
              kind: 'initial_order',
              prep: [
                prepJson(id: <String, Object?>{'amount_minor': 5}),
              ],
            ),
          ),
        ),
        throwsA(isA<KitchenSpoolPayloadFormatException>()),
      );
    });

    test('a non-boolean answer degrades to unsplit', () {
      final prep = decodedPrep(
        dispatchJson(
          kind: 'initial_order',
          prep: [prepJson(selected: 'yes')],
        ),
      );
      expect(prep.isClassified, isFalse);
      expect(prep.name, 'Meat pieces');
    });

    test('a numeric name degrades to unsplit', () {
      final prep = decodedPrep(
        dispatchJson(kind: 'initial_order', prep: [prepJson(name: 7)]),
      );
      expect(prep.isClassified, isFalse);
    });

    test('an INCOMPLETE triple is not a classification', () {
      for (final partial in [
        prepJson(includeSelected: false),
        prepJson(includeName: false),
        prepJson(includeId: false),
      ]) {
        final prep = decodedPrep(
          dispatchJson(kind: 'initial_order', prep: [partial]),
        );
        expect(prep.isClassified, isFalse, reason: '$partial');
        expect(prep.name, 'Meat pieces');
      }
    });

    test('an empty-string id degrades to unsplit', () {
      final prep = decodedPrep(
        dispatchJson(
          kind: 'initial_order',
          prep: [prepJson(id: '   ')],
        ),
      );
      expect(prep.isClassified, isFalse);
    });

    test('a degraded component re-encodes WITHOUT the bad keys', () {
      final prep = decodedPrep(
        dispatchJson(kind: 'initial_order', prep: [prepJson(selected: 3)]),
      );
      expect(prep.toJson(), {'name': 'Meat pieces', 'quantity': 2});
    });

    test('a genuinely unknown key is still REJECTED (decode stays closed)', () {
      expect(
        () => decodedPrep(
          dispatchJson(
            kind: 'initial_order',
            prep: [
              <String, Object?>{
                'name': 'Meat pieces',
                'quantity': 2,
                'classifier_option_colour': 'red',
              },
            ],
          ),
        ),
        throwsA(isA<KitchenSpoolPayloadFormatException>()),
      );
    });

    test('a malformed QUANTITY is still strict (not degraded)', () {
      expect(
        () => decodedPrep(
          dispatchJson(
            kind: 'initial_order',
            prep: [
              <String, Object?>{'name': 'Meat pieces', 'quantity': 0},
            ],
          ),
        ),
        throwsA(isA<KitchenSpoolPayloadFormatException>()),
      );
    });
  });
}
