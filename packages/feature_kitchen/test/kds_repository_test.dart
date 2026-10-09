import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_sync/restoflow_sync.dart';

/// A controllable fake sync source — lets the repository be tested with NO live
/// Supabase and NO coordinator (approved decision A1).
class _FakeKdsSyncSource implements KdsSyncSource {
  final StreamController<KdsSyncState> _controller =
      StreamController<KdsSyncState>.broadcast();
  KdsSyncState _state = KdsSyncState.initial;

  int startCalls = 0;
  int refreshCalls = 0;

  void emit(KdsSyncState s) {
    _state = s;
    _controller.add(s);
  }

  @override
  KdsSyncState get state => _state;

  @override
  Stream<KdsSyncState> get states => _controller.stream;

  @override
  Future<void> start() async => startCalls++;

  @override
  Future<void> refresh() async => refreshCalls++;

  @override
  Future<void> resume() async {}

  @override
  Future<void> dispose() async => _controller.close();
}

KdsSyncState _dataState(
  List<Map<String, dynamic>> orders,
  List<Map<String, dynamic>> items,
) => KdsSyncState(
  status: KdsSyncStatus.data,
  entities: {'orders': orders, 'order_items': items},
);

void main() {
  group('KdsRepository', () {
    test('projects sync state into a money-free KdsViewState', () {
      final source = _FakeKdsSyncSource();
      final repo = KdsRepository(source);
      addTearDown(repo.dispose);

      source.emit(
        _dataState(
          [
            {'id': 'o1', 'status': 'preparing'},
          ],
          [
            {
              'id': 'i1',
              'order_id': 'o1',
              'station_id': 'grill',
              'status': 'preparing',
              'quantity': 1,
              'menu_item_name_snapshot': 'Burger',
            },
          ],
        ),
      );

      final vs = repo.viewState;
      expect(vs.status, KdsSyncStatus.data);
      expect(vs.tickets.single.kitchenTicketId, 'o1:grill');
      expect(vs.tickets.single.items.single.name, 'Burger');
    });

    test('viewStates replays current state then forwards updates', () async {
      final source = _FakeKdsSyncSource();
      final repo = KdsRepository(source);
      addTearDown(repo.dispose);

      source.emit(
        _dataState(
          [
            {'id': 'o1', 'status': 'preparing'},
          ],
          [
            {
              'id': 'i1',
              'order_id': 'o1',
              'station_id': 'grill',
              'status': 'preparing',
              'quantity': 1,
              'menu_item_name_snapshot': 'Burger',
            },
          ],
        ),
      );

      final seen = <KdsViewState>[];
      final sub = repo.viewStates.listen(seen.add);
      await Future<void>.delayed(
        Duration.zero,
      ); // deliver the seeded current state

      expect(seen.single.tickets.single.kitchenTicketId, 'o1:grill');

      source.emit(
        _dataState(
          [
            {'id': 'o2', 'status': 'ready'},
          ],
          [
            {
              'id': 'i2',
              'order_id': 'o2',
              'station_id': 'bar',
              'status': 'ready',
              'quantity': 2,
              'menu_item_name_snapshot': 'Beer',
            },
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(seen.length, 2);
      expect(seen.last.tickets.single.kitchenTicketId, 'o2:bar');
      await sub.cancel();
    });

    test(
      'KITCHEN-PRINT-DUAL-001C backstop: a direct_print order in local state is '
      'never mapped to a ticket (defense-in-depth for a legacy/pre-migration '
      'feed), while the normal order still maps',
      () {
        final source = _FakeKdsSyncSource();
        final repo = KdsRepository(source);
        addTearDown(repo.dispose);

        // A malformed/pre-migration feed that still carried a direct_print order
        // (as an un-migrated server would) alongside a normal one + both items.
        // The authoritative fix omits this graph server-side; this proves the
        // client read-back is still contained if one ever slips through.
        source.emit(
          _dataState(
            [
              {
                'id': 'o-dp',
                'status': 'submitted',
                'dispatch_mode': 'direct_print',
              },
              {'id': 'o-kds', 'status': 'preparing', 'dispatch_mode': 'kds'},
            ],
            [
              {
                'id': 'i-dp',
                'order_id': 'o-dp',
                'station_id': 'grill',
                'status': 'submitted',
                'quantity': 1,
                'menu_item_name_snapshot': 'Burger',
              },
              {
                'id': 'i-kds',
                'order_id': 'o-kds',
                'station_id': 'grill',
                'status': 'preparing',
                'quantity': 1,
                'menu_item_name_snapshot': 'Fries',
              },
            ],
          ),
        );

        final vs = repo.viewState;
        expect(
          vs.tickets,
          hasLength(1),
          reason: 'only the normal order boards',
        );
        expect(vs.tickets.single.orderId, 'o-kds');
        expect(
          vs.tickets.any((t) => t.orderId == 'o-dp'),
          isFalse,
          reason: 'a direct_print order is never surfaced as a KDS ticket',
        );
      },
    );

    test('ORDER-EDIT-001C: order_edits rows flow through to the change '
        'overlay; without them the view state is unchanged', () {
      final source = _FakeKdsSyncSource();
      final repo = KdsRepository(source);
      addTearDown(repo.dispose);

      final orders = [
        {'id': 'o1', 'status': 'preparing', 'edit_count': 1},
      ];
      final items = [
        {
          'id': 'i1',
          'order_id': 'o1',
          'status': 'pending',
          'quantity': 1,
          'menu_item_name_snapshot': 'Burger',
          'line_position': 1,
        },
        {
          'id': 'i2',
          'order_id': 'o1',
          'status': 'voided',
          'quantity': 1,
          'menu_item_name_snapshot': 'Fries',
          'line_position': 2,
          'removed_by_edit_id': 'e1',
          'removed_kitchen_stage': 'preparing',
        },
      ];
      final edit = {
        'id': 'e1',
        'order_id': 'o1',
        'edit_number': 1,
        'kitchen_channel': 'kds',
        'kitchen_ack_required': true,
        'kitchen_ack_at': null,
        'reason_code': 'item_unavailable',
        'created_at': '2026-10-08T10:20:00Z',
      };

      source.emit(_dataState(orders, items));
      final before = repo.viewState.tickets.single;
      expect(before.change, isNull);
      expect(before.items.single.name, 'Burger');

      source.emit(
        KdsSyncState(
          status: KdsSyncStatus.data,
          entities: {
            'orders': orders,
            'order_items': items,
            'order_edits': [edit],
          },
        ),
      );
      final after = repo.viewState.tickets.single;
      expect(after.requiresChangeAck, isTrue);
      expect(after.change!.upToEditNumber, 1);
      expect(after.change!.latest.reasonCode, 'item_unavailable');
      expect(after.change!.removed.single.line.name, 'Fries');
      expect(after.changeAlertKey, 'o1:unassigned|e1');

      // The kitchen's "Got it" re-delivers the edit acknowledged.
      source.emit(
        KdsSyncState(
          status: KdsSyncStatus.data,
          entities: {
            'orders': orders,
            'order_items': items,
            'order_edits': [
              {...edit, 'kitchen_ack_at': '2026-10-08T10:30:00Z'},
            ],
          },
        ),
      );
      expect(repo.viewState.tickets.single.change, isNull);
    });

    test('exposes the reauthRequired state to the UI', () {
      final source = _FakeKdsSyncSource();
      final repo = KdsRepository(source);
      addTearDown(repo.dispose);

      source.emit(const KdsSyncState(status: KdsSyncStatus.reauthRequired));
      expect(repo.viewState.isReauthRequired, isTrue);
      expect(repo.viewState.status, KdsSyncStatus.reauthRequired);
    });

    test('start/refresh/dispose delegate to the source', () async {
      final source = _FakeKdsSyncSource();
      final repo = KdsRepository(source);
      await repo.start();
      await repo.refresh();
      expect(source.startCalls, 1);
      expect(source.refreshCalls, 1);
      await repo.dispose();
    });
  });
}
