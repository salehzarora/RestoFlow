import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/main.dart';
import 'package:restoflow_sync/restoflow_sync.dart';

/// A sync source that counts refreshes and lets the test drive state — no live
/// Supabase (A1/A5).
class _RefreshCountingSource implements KdsSyncSource {
  final StreamController<KdsSyncState> _c =
      StreamController<KdsSyncState>.broadcast();
  KdsSyncState _state = KdsSyncState.initial;
  int refreshCalls = 0;

  void emit(KdsSyncState s) {
    _state = s;
    _c.add(s);
  }

  @override
  KdsSyncState get state => _state;
  @override
  Stream<KdsSyncState> get states => _c.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> refresh() async => refreshCalls++;

  @override
  Future<void> resume() async {}
  @override
  Future<void> dispose() async => _c.close();
}

/// A controllable fake realtime source.
class _FakeInvalidationSource implements InvalidationSource {
  final StreamController<InvalidationHint> _c =
      StreamController<InvalidationHint>.broadcast();
  void emit(InvalidationHint h) {
    if (!_c.isClosed) _c.add(h);
  }

  @override
  Stream<InvalidationHint> get hints => _c.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> dispose() async {
    if (!_c.isClosed) await _c.close();
  }
}

KdsSyncState _data() => const KdsSyncState(
  status: KdsSyncStatus.data,
  entities: {
    'orders': [
      {'id': 'o1', 'status': 'preparing'},
    ],
    'order_items': [
      {
        'id': 'i1',
        'order_id': 'o1',
        'station_id': 'grill',
        'status': 'preparing',
        'quantity': 1,
        'menu_item_name_snapshot': 'Burger',
      },
    ],
  },
);

InvalidationHint _hint() => const InvalidationHint(
  organizationId: 'org-1',
  branchId: 'b-1',
  entity: 'orders',
  entityId: 'o1',
);

void main() {
  testWidgets(
    'realtime is optional: app renders provider-backed tickets with no source',
    (tester) async {
      final source = _RefreshCountingSource();
      addTearDown(source.dispose);

      await tester.pumpWidget(KdsApp(source: source)); // no invalidationSource
      await tester.pump();
      source.emit(_data());
      await tester.pump();

      expect(find.text('Burger ×1'), findsOneWidget);
    },
  );

  testWidgets('an injected realtime hint triggers a coordinator refresh', (
    tester,
  ) async {
    final source = _RefreshCountingSource();
    final inv = _FakeInvalidationSource();
    addTearDown(source.dispose);
    addTearDown(inv.dispose);

    await tester.pumpWidget(KdsApp(source: source, invalidationSource: inv));
    await tester.pump(); // build providers + bridge
    source.emit(_data());
    await tester.pump();
    expect(find.text('Burger ×1'), findsOneWidget); // realtime is additive

    expect(source.refreshCalls, 0);
    inv.emit(_hint());
    await tester.pump(const Duration(milliseconds: 300)); // fire the debounce
    expect(source.refreshCalls, greaterThanOrEqualTo(1));
  });
}
