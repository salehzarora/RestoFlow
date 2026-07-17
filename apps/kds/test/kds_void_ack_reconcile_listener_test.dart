import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/kds_synced_home.dart';
import 'package:restoflow_kds/src/state/kds_session.dart';
import 'package:restoflow_kds/src/state/kds_void_ack_controller.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_sync/restoflow_sync.dart';

/// PSC-001D final correction — the acknowledgement RECONCILIATION LISTENER in
/// the REAL KdsSyncedHome, driven through the actual kdsViewStateProvider
/// stream seam: only an authoritative `KdsSyncStatus.data` emission may clean
/// pending/failed acknowledgement state. initial/loading (which legitimately
/// carry an empty temporary ticket list), stale snapshots, errors and reauth
/// stops must never clean anything.

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> p) _handler;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    return _handler(function, params);
  }
}

class _FakeSource implements KdsSyncSource {
  _FakeSource({this.throwOnRefresh = false});
  final bool throwOnRefresh;
  @override
  KdsSyncState get state => KdsSyncState.initial;
  @override
  Stream<KdsSyncState> get states => const Stream.empty();
  @override
  Future<void> start() async {}
  @override
  Future<void> refresh() async {
    if (throwOnRefresh) throw StateError('refresh down');
  }

  @override
  Future<void> resume() async {}
  @override
  Future<void> dispose() async {}
}

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

/// The applied envelope echoing the pushed op — acknowledge() then leaves the
/// order PENDING awaiting the authoritative pull, which is exactly the state
/// the listener must protect.
Object? _applied(String fn, Map<String, dynamic> p) {
  final ops = p['p_operations'] as List;
  final localOp = (ops.single as Map)['local_operation_id'] as String;
  return {
    'ok': true,
    'results': [
      {'local_operation_id': localOp, 'status': 'applied', 'ok': true},
    ],
  };
}

KdsTicketView _cancelled(String orderId) => KdsTicketView(
  kitchenTicketId: '$orderId:unassigned',
  stationId: 'unassigned',
  orderId: orderId,
  orderNumber: '#ABC123',
  orderType: 'takeaway',
  status: KitchenTicketStatus.cancelled,
  submittedAt: DateTime.utc(2026, 7, 21, 10),
  voidedAt: DateTime.utc(2026, 7, 21, 10, 5),
  voidedFromStatus: 'preparing',
  items: [const KdsItemView(name: 'Burger', quantity: 2)],
);

class _Harness {
  _Harness({bool throwOnRefresh = false})
    : states = StreamController<KdsViewState>.broadcast() {
    container = ProviderContainer(
      overrides: [
        kdsViewStateProvider.overrideWith((ref) => states.stream),
        kdsAuthTransportProvider.overrideWithValue(_FakeTransport(_applied)),
        kdsSyncSessionProvider.overrideWithValue(_session),
        kdsSyncSourceProvider.overrideWithValue(
          _FakeSource(throwOnRefresh: throwOnRefresh),
        ),
      ],
    );
  }

  final StreamController<KdsViewState> states;
  late final ProviderContainer container;

  Set<String> get pending =>
      container.read(kdsVoidAckControllerProvider).pending;
  Set<String> get failed => container.read(kdsVoidAckControllerProvider).failed;

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: KdsSyncedHome(),
        ),
      ),
    );
    // The pre-first-emission scaffold carries the loading spinner (an infinite
    // animation) — fixed pumps only; never pumpAndSettle before a stream event.
    await tester.pump();
  }

  /// Emits a view state through the REAL provider stream and lets the
  /// listener + rebuild run. Finite arrival pulses settle within the window.
  Future<void> emit(
    WidgetTester tester,
    KdsSyncStatus status, {
    List<KdsTicketView> tickets = const [],
  }) async {
    states.add(KdsViewState(status: status, tickets: tickets));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
  }

  Future<void> seedPending(String orderId) => container
      .read(kdsVoidAckControllerProvider.notifier)
      .acknowledge(orderId);

  void dispose() {
    states.close();
    container.dispose();
  }
}

void main() {
  testWidgets(
    'the full transition contract: initial/loading/stale/error/reauth never '
    'clean; data WITH the card retains; data WITHOUT the card cleans',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.pumpHome(tester);
      await h.seedPending('vo1');
      expect(h.pending, {'vo1'});

      // (2) initial with no tickets — a temporary empty list, not authority.
      await h.emit(tester, KdsSyncStatus.initial);
      expect(h.pending, {'vo1'});

      // (3) loading with no tickets.
      await h.emit(tester, KdsSyncStatus.loading);
      expect(h.pending, {'vo1'});

      // (4) stale / error / reauth with no tickets.
      await h.emit(tester, KdsSyncStatus.offlineStale);
      expect(h.pending, {'vo1'});
      await h.emit(tester, KdsSyncStatus.error);
      expect(h.pending, {'vo1'});
      await h.emit(tester, KdsSyncStatus.reauthRequired);
      expect(h.pending, {'vo1'});

      // (5) authoritative data STILL containing the pending cancellation.
      await h.emit(tester, KdsSyncStatus.data, tickets: [_cancelled('vo1')]);
      expect(h.pending, {'vo1'});

      // (6) authoritative data WITHOUT it — acknowledged server-side.
      await h.emit(tester, KdsSyncStatus.data);
      expect(h.pending, isEmpty);
      expect(h.failed, isEmpty);
    },
  );

  testWidgets(
    'an authoritative EMPTY board legitimately cleans all stale entries',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.pumpHome(tester);
      await h.seedPending('vo1');
      await h.seedPending('vo2');
      expect(h.pending, {'vo1', 'vo2'});
      await h.emit(tester, KdsSyncStatus.data);
      expect(h.pending, isEmpty);
    },
  );

  testWidgets(
    'one order disappearing cleans only it — the still-visible pending '
    'cancellation is retained',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.pumpHome(tester);
      await h.seedPending('gone');
      await h.seedPending('kept');
      await h.emit(tester, KdsSyncStatus.data, tickets: [_cancelled('kept')]);
      expect(h.pending, {'kept'});
    },
  );

  testWidgets('repeated initial/loading emissions never clean', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.pumpHome(tester);
    await h.seedPending('vo1');
    for (var i = 0; i < 3; i++) {
      await h.emit(tester, KdsSyncStatus.initial);
      await h.emit(tester, KdsSyncStatus.loading);
    }
    expect(h.pending, {'vo1'});
  });

  testWidgets(
    'a failed immediate refresh never cleans (loading follows), while a later '
    'authoritative data emission still cleans correctly',
    (tester) async {
      final h = _Harness(throwOnRefresh: true);
      addTearDown(h.dispose);
      await h.pumpHome(tester);
      // The applied ack survives its own failed immediate refresh…
      await h.seedPending('vo1');
      expect(h.pending, {'vo1'});
      expect(h.failed, isEmpty);
      // …and the loading that follows a failed refresh cleans nothing.
      await h.emit(tester, KdsSyncStatus.loading);
      expect(h.pending, {'vo1'});
      // The next successful authoritative pull performs the cleanup.
      await h.emit(tester, KdsSyncStatus.data);
      expect(h.pending, isEmpty);
    },
  );
}
