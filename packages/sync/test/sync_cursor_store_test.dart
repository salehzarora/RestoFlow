import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_sync/restoflow_sync.dart';
import 'package:test/test.dart';

/// RF-063: the in-memory cursor store behind the persistable interface (A3).
void main() {
  group('InMemorySyncCursorStore', () {
    test('stores, snapshots, and clears per-entity cursors', () {
      final store = InMemorySyncCursorStore();
      expect(store.cursorFor('orders'), isNull);
      expect(store.snapshot(), isEmpty);

      const c1 = SyncCursor(updatedAt: '2026-06-22T09:00:00+00:00', id: 'o1');
      store.setCursor('orders', c1);
      expect(store.cursorFor('orders'), c1);
      expect(store.snapshot(), {'orders': c1});

      const c2 = SyncCursor(updatedAt: '2026-06-22T10:00:00+00:00', id: 'o9');
      store.setCursor('orders', c2);
      expect(
        store.cursorFor('orders'),
        c2,
        reason: 'latest cursor replaces prior',
      );

      store.clear();
      expect(store.snapshot(), isEmpty);
    });
  });
}
