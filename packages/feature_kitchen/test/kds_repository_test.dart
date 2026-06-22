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
