import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:test/test.dart';

/// RF-058: the invalidation-hint parser reads ONLY the allowed keys, ignores
/// everything else (money/raw/customer fields can never surface), and fails safe
/// on a malformed payload.
void main() {
  group('InvalidationHint.tryParse', () {
    test('parses a valid minimal hint', () {
      final hint = InvalidationHint.tryParse({
        'organization_id': 'org-1',
        'branch_id': 'branch-1',
        'entity': 'orders',
        'entity_id': 'o1',
        'revision': 3,
        'updated_at': '2026-06-22T10:00:00+00:00',
        'server_ts': '2026-06-22T10:00:01+00:00',
        'id': 'msg-uuid', // realtime.send adds this — harmless, ignored
      });
      expect(hint, isNotNull);
      expect(hint!.organizationId, 'org-1');
      expect(hint.branchId, 'branch-1');
      expect(hint.entity, 'orders');
      expect(hint.entityId, 'o1');
      expect(hint.revision, 3);
      expect(hint.updatedAt, '2026-06-22T10:00:00+00:00');
      expect(hint.serverTs, '2026-06-22T10:00:01+00:00');
    });

    test('order_items hint with null revision is fine', () {
      final hint = InvalidationHint.tryParse({
        'organization_id': 'org-1',
        'branch_id': 'branch-1',
        'entity': 'order_items',
        'entity_id': 'i1',
        'revision': null,
      });
      expect(hint, isNotNull);
      expect(hint!.entity, 'order_items');
      expect(hint.revision, isNull);
    });

    test(
      'money / raw-row / customer extra keys are NOT exposed on the model',
      () {
        // A (wrongly) money-laden payload still yields only the minimal model;
        // there is no field on InvalidationHint that could carry these.
        final hint = InvalidationHint.tryParse({
          'organization_id': 'org-1',
          'branch_id': 'branch-1',
          'entity': 'orders',
          'entity_id': 'o1',
          'grand_total_minor': 9999,
          'unit_price_minor_snapshot': 500,
          'receipt_number': 'R-123',
          'customer_name': 'Jane',
          'notes': 'secret',
        });
        expect(hint, isNotNull);
        // The toString and fields expose none of the forbidden values.
        final rendered =
            '${hint!} ${hint.organizationId} ${hint.branchId} '
            '${hint.entity} ${hint.entityId} ${hint.revision} '
            '${hint.updatedAt} ${hint.serverTs}';
        expect(rendered.contains('9999'), isFalse);
        expect(rendered.contains('500'), isFalse);
        expect(rendered.contains('R-123'), isFalse);
        expect(rendered.contains('Jane'), isFalse);
        expect(rendered.contains('secret'), isFalse);
      },
    );

    test('rejects a non-allow-listed entity (e.g. payments)', () {
      expect(
        InvalidationHint.tryParse({
          'organization_id': 'org-1',
          'branch_id': 'branch-1',
          'entity': 'payments',
          'entity_id': 'p1',
        }),
        isNull,
      );
    });

    test('rejects missing/mistyped required fields (ignored safely)', () {
      expect(InvalidationHint.tryParse({'organization_id': 'org-1'}), isNull);
      expect(
        InvalidationHint.tryParse({
          'organization_id': 'org-1',
          'branch_id': 'branch-1',
          'entity': 'orders',
          'entity_id': 123, // not a string
        }),
        isNull,
      );
    });
  });

  group('RealtimeScope', () {
    test('builds the per-branch topic (A2)', () {
      const scope = RealtimeScope(organizationId: 'org-1', branchId: 'b-9');
      expect(scope.branchTopic, 'kds:branch:b-9');
    });
  });

  group('DisabledInvalidationSource', () {
    test('emits nothing and is a safe no-op', () async {
      const source = DisabledInvalidationSource();
      await source.start();
      expect(await source.hints.isEmpty, isTrue);
      await source.dispose();
    });
  });
}
