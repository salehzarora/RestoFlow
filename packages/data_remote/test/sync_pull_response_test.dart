import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:test/test.dart';

/// RF-063: parsing the `app.sync_pull` envelope into typed models — entity
/// pages, per-entity cursors, inline tombstones, the operation-status feed, and
/// safe failure on a malformed envelope.
void main() {
  group('SyncPullResponse.fromJson', () {
    test(
      'parses changes, per-entity cursors, has_more and operation_statuses',
      () {
        final decoded = {
          'ok': true,
          'server_ts': '2026-06-22T10:00:00+00:00',
          'changes': {
            'orders': {
              'rows': [
                {'id': 'o1', 'status': 'preparing', 'deleted_at': null},
              ],
              'next_cursor': {
                'updated_at': '2026-06-22T09:59:00+00:00',
                'id': 'o1',
              },
              'has_more': true,
            },
            'order_items': {
              'rows': <Map<String, dynamic>>[],
              'next_cursor': null,
              'has_more': false,
            },
          },
          'operation_statuses': {
            'rows': [
              {
                'id': 's1',
                'local_operation_id': 'op-1',
                'operation_type': 'order.submit',
                'status': 'applied',
                'retry_count': 0,
                'updated_at': '2026-06-22T09:58:00+00:00',
              },
            ],
            'next_cursor': {
              'updated_at': '2026-06-22T09:58:00+00:00',
              'id': 's1',
            },
            'has_more': false,
          },
        };

        final res = SyncPullResponse.fromJson(decoded);

        expect(res.serverTs, '2026-06-22T10:00:00+00:00');
        final orders = res.changes['orders']!;
        expect(orders.rows.single['id'], 'o1');
        expect(orders.hasMore, isTrue);
        expect(
          orders.nextCursor,
          const SyncCursor(updatedAt: '2026-06-22T09:59:00+00:00', id: 'o1'),
        );

        final items = res.changes['order_items']!;
        expect(items.rows, isEmpty);
        expect(items.nextCursor, isNull);
        expect(items.hasMore, isFalse);

        expect(res.operationStatuses.statuses.single.localOperationId, 'op-1');
        expect(res.operationStatuses.statuses.single.status, 'applied');
        expect(res.operationStatuses.statuses.single.retryCount, 0);
      },
    );

    test(
      'passes inline tombstones (deleted_at non-null) through untouched',
      () {
        final decoded = {
          'ok': true,
          'server_ts': '2026-06-22T10:00:00+00:00',
          'changes': {
            'orders': {
              'rows': [
                {
                  'id': 'o-dead',
                  'status': 'voided',
                  'deleted_at': '2026-06-22T09:00:00+00:00',
                },
              ],
              'next_cursor': {
                'updated_at': '2026-06-22T09:00:00+00:00',
                'id': 'o-dead',
              },
              'has_more': false,
            },
          },
          'operation_statuses': {
            'rows': <Map<String, dynamic>>[],
            'next_cursor': null,
            'has_more': false,
          },
        };

        final res = SyncPullResponse.fromJson(decoded);
        final row = res.changes['orders']!.rows.single;
        expect(row['deleted_at'], '2026-06-22T09:00:00+00:00');
      },
    );

    test('tolerates a missing operation_statuses key (empty feed)', () {
      final decoded = {
        'ok': true,
        'server_ts': '2026-06-22T10:00:00+00:00',
        'changes': <String, dynamic>{},
      };
      final res = SyncPullResponse.fromJson(decoded);
      expect(res.operationStatuses.statuses, isEmpty);
      expect(res.changes.entities, isEmpty);
    });

    test('throws FormatException when ok != true', () {
      expect(
        () => SyncPullResponse.fromJson({'ok': false, 'changes': {}}),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when the envelope is not an object', () {
      expect(
        () => SyncPullResponse.fromJson('nope'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SyncPullResponse.fromJson(null),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'throws FormatException when has_more is true but next_cursor is null',
      () {
        // The honest RF-057 server never sends this; rejecting it makes a
        // malformed page an InvalidResponseFailure instead of an unadvanceable
        // cursor the coordinator would re-pull.
        final decoded = {
          'ok': true,
          'changes': {
            'orders': {
              'rows': [
                {'id': 'o1', 'status': 'preparing'},
              ],
              'next_cursor': null,
              'has_more': true,
            },
          },
        };
        expect(
          () => SyncPullResponse.fromJson(decoded),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('throws FormatException when rows is not an array', () {
      final decoded = {
        'ok': true,
        'changes': {
          'orders': {
            'rows': 'not-a-list',
            'next_cursor': null,
            'has_more': false,
          },
        },
      };
      expect(
        () => SyncPullResponse.fromJson(decoded),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
