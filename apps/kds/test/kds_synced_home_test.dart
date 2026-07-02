import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_kds/main.dart';
import 'package:restoflow_sync/restoflow_sync.dart';

/// A controllable fake sync source — drives the provider-backed KDS home with
/// NO live Supabase and NO real session (approved decision A1).
class _FakeKdsSyncSource implements KdsSyncSource {
  final StreamController<KdsSyncState> _controller =
      StreamController<KdsSyncState>.broadcast();
  KdsSyncState _state = KdsSyncState.initial;

  void emit(KdsSyncState s) {
    _state = s;
    _controller.add(s);
  }

  @override
  KdsSyncState get state => _state;

  @override
  Stream<KdsSyncState> get states => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> dispose() async => _controller.close();
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
        'quantity': 2,
        'menu_item_name_snapshot': 'Burger',
      },
    ],
  },
);

void main() {
  testWidgets(
    'fixture fallback renders demo tickets when no session is injected',
    (tester) async {
      // Tall, narrow surface so all RF-103 lifecycle-seeded fixture tickets
      // are laid out (stacked layout; below the wide-columns breakpoint).
      tester.view.physicalSize = const Size(880, 1700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const KdsApp()); // no source -> fixture
      await tester.pumpAndSettle();

      // RF-105: the aligned demo fixture uses POS menu item names.
      expect(find.text('Classic Burger ×2'), findsOneWidget);
      expect(find.text('French Fries ×2'), findsOneWidget);
    },
  );

  testWidgets('provider-backed home renders tickets mapped from pulled rows', (
    tester,
  ) async {
    final source = _FakeKdsSyncSource();
    addTearDown(source.dispose);

    await tester.pumpWidget(KdsApp(source: source));
    await tester.pump(); // seed current (initial) state

    source.emit(_data());
    await tester.pump(); // deliver the data state

    expect(find.text('Burger ×2'), findsOneWidget);
    // Demo-readiness sprint: the card title is the HUMAN display code derived
    // from the order id — the same code the POS shows — never the raw
    // order:station key (and no money anywhere on screen).
    expect(find.text(displayOrderCode('o1')), findsOneWidget);
    expect(find.textContaining('o1:grill'), findsNothing);
  });

  testWidgets(
    'reauthRequired state shows a lock indicator and does not crash',
    (tester) async {
      final source = _FakeKdsSyncSource();
      addTearDown(source.dispose);

      await tester.pumpWidget(KdsApp(source: source));
      await tester.pump();

      source.emit(const KdsSyncState(status: KdsSyncStatus.reauthRequired));
      await tester.pump();

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('offlineStale keeps showing the last good tickets', (
    tester,
  ) async {
    final source = _FakeKdsSyncSource();
    addTearDown(source.dispose);

    await tester.pumpWidget(KdsApp(source: source));
    await tester.pump();

    source.emit(_data());
    await tester.pump();
    expect(find.text('Burger ×2'), findsOneWidget);

    // A transient failure marks the same data stale — it must remain visible.
    source.emit(
      const KdsSyncState(
        status: KdsSyncStatus.offlineStale,
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
              'quantity': 2,
              'menu_item_name_snapshot': 'Burger',
            },
          ],
        },
      ),
    );
    await tester.pump();
    expect(find.text('Burger ×2'), findsOneWidget);
  });
}
