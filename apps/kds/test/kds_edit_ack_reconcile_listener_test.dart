import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/kds_synced_home.dart';
import 'package:restoflow_kds/src/state/kds_edit_ack_controller.dart';
import 'package:restoflow_kds/src/state/kds_session.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_sync/restoflow_sync.dart';

/// ORDER-EDIT-001D — the "Got it" RECONCILIATION in the REAL KdsSyncedHome,
/// driven through the actual kdsViewStateProvider stream seam (the PSC-001D
/// rule, keyed by change alert key): only an authoritative
/// `KdsSyncStatus.data` emission may clean pending / failed "Got it" state.
/// initial / loading (a temporary empty list), stale snapshots, errors and
/// reauth stops never clean anything.

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> p) _handler;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    return _handler(function, params);
  }
}

class _FakeSource implements KdsSyncSource {
  @override
  KdsSyncState get state => KdsSyncState.initial;
  @override
  Stream<KdsSyncState> get states => const Stream.empty();
  @override
  Future<void> start() async {}
  @override
  Future<void> refresh() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> dispose() async {}
}

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

String _opId(Map<String, dynamic> p) =>
    ((p['p_operations'] as List).single as Map)['local_operation_id'] as String;

/// The applied envelope — acknowledge() then leaves the key PENDING awaiting
/// the authoritative pull, exactly the state the listener must protect.
Object? _applied(String fn, Map<String, dynamic> p) => {
  'ok': true,
  'results': [
    {
      'local_operation_id': _opId(p),
      'status': 'applied',
      'ok': true,
      'acknowledged_count': 1,
    },
  ],
};

/// A terminal refusal — acknowledge() marks the key FAILED.
Object? _refused(String fn, Map<String, dynamic> p) => {
  'ok': true,
  'results': [
    {
      'local_operation_id': _opId(p),
      'status': 'rejected',
      'ok': false,
      'error': 'invalid_edit_number',
    },
  ],
};

KdsOrderEdit _edit(int n, {String orderId = 'o1'}) => KdsOrderEdit(
  id: '$orderId-e$n',
  orderId: orderId,
  editNumber: n,
  channel: KdsEditChannel.kds,
  ackRequired: true,
);

/// A card carrying an unconfirmed change with [edits]; null => no change.
KdsTicketView _card({String orderId = 'o1', List<int>? edits = const [1]}) =>
    KdsTicketView(
      kitchenTicketId: '$orderId:unassigned',
      stationId: 'unassigned',
      orderId: orderId,
      orderNumber: '#ABC123',
      orderType: 'takeaway',
      status: KitchenTicketStatus.inPreparation,
      submittedAt: DateTime.utc(2026, 10, 8, 10),
      items: const [KdsItemView(name: 'Burger', quantity: 2)],
      change: edits == null
          ? null
          : KdsTicketChange(
              pendingEdits: [for (final n in edits) _edit(n, orderId: orderId)],
              orderPendingEditNumbers: edits,
            ),
    );

class _Harness {
  _Harness({Object? Function(String, Map<String, dynamic>) handler = _applied})
    : states = StreamController<KdsViewState>.broadcast() {
    container = ProviderContainer(
      overrides: [
        kdsViewStateProvider.overrideWith((ref) => states.stream),
        kdsAuthTransportProvider.overrideWithValue(_FakeTransport(handler)),
        kdsSyncSessionProvider.overrideWithValue(_session),
        kdsSyncSourceProvider.overrideWithValue(_FakeSource()),
      ],
    );
  }

  final StreamController<KdsViewState> states;
  late final ProviderContainer container;

  KdsEditAckState get ack => container.read(kdsEditAckControllerProvider);
  Set<String> get pending => ack.pending.keys.toSet();
  Set<String> get failed => ack.failed.keys.toSet();

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
    // The pre-first-emission scaffold carries the loading spinner (an
    // infinite animation) — fixed pumps only, never pumpAndSettle.
    await tester.pump();
  }

  /// Emits a view state through the REAL provider stream and lets the
  /// listener + rebuild run.
  Future<void> emit(
    WidgetTester tester,
    KdsSyncStatus status, {
    List<KdsTicketView> tickets = const [],
  }) async {
    states.add(KdsViewState(status: status, tickets: tickets));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
  }

  Future<KdsEditAckResult> seed(KdsTicketView card) =>
      container.read(kdsEditAckControllerProvider.notifier).acknowledge(card);

  void dispose() {
    states.close();
    container.dispose();
  }
}

void main() {
  testWidgets('the full transition contract: initial / loading / stale / '
      'error / reauth never clean; data WITH the change retains; data '
      'WITHOUT it (confirmed) cleans', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.pumpHome(tester);
    await h.seed(_card());
    expect(h.pending, {'o1:unassigned|e1'});

    for (final status in [
      KdsSyncStatus.initial,
      KdsSyncStatus.loading,
      KdsSyncStatus.offlineStale,
      KdsSyncStatus.error,
      KdsSyncStatus.reauthRequired,
    ]) {
      await h.emit(tester, status);
      expect(h.pending, {'o1:unassigned|e1'}, reason: '$status');
    }

    // Authoritative data STILL showing the change: retained.
    await h.emit(tester, KdsSyncStatus.data, tickets: [_card()]);
    expect(h.pending, {'o1:unassigned|e1'});

    // Authoritative data with the card but NO change: confirmed, cleaned.
    await h.emit(tester, KdsSyncStatus.data, tickets: [_card(edits: null)]);
    expect(h.pending, isEmpty);
    expect(h.failed, isEmpty);
  });

  testWidgets('a FAILED "Got it" survives non-data emissions and is cleaned '
      'only by an authoritative pull without the change', (tester) async {
    final h = _Harness(handler: _refused);
    addTearDown(h.dispose);
    await h.pumpHome(tester);
    await h.seed(_card());
    expect(h.failed, {'o1:unassigned|e1'});
    await h.emit(tester, KdsSyncStatus.loading);
    await h.emit(tester, KdsSyncStatus.offlineStale);
    expect(h.failed, {'o1:unassigned|e1'});
    await h.emit(tester, KdsSyncStatus.data, tickets: [_card()]);
    expect(h.failed, {'o1:unassigned|e1'});
    await h.emit(tester, KdsSyncStatus.data);
    expect(h.failed, isEmpty);
  });

  testWidgets('e1 moving on to e2 drops the e1 entry, and the e2 card shows an '
      'ENABLED "Got it"', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.pumpHome(tester);
    await h.emit(tester, KdsSyncStatus.data, tickets: [_card()]);
    await h.seed(_card());
    await tester.pump();
    final button = find.byKey(const Key('kds-edit-ack-o1:unassigned'));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    // e1 confirmed on the server, a new edit e2 arrived meanwhile.
    await h.emit(
      tester,
      KdsSyncStatus.data,
      tickets: [
        _card(edits: [2]),
      ],
    );
    expect(h.pending, isEmpty);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  });

  testWidgets('one order confirming cleans only its key — another order\'s '
      'pending "Got it" is retained', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.pumpHome(tester);
    await h.seed(_card());
    await h.seed(_card(orderId: 'o2'));
    expect(h.pending, {'o1:unassigned|e1', 'o2:unassigned|e1'});
    await h.emit(
      tester,
      KdsSyncStatus.data,
      tickets: [
        _card(edits: null),
        _card(orderId: 'o2'),
      ],
    );
    expect(h.pending, {'o2:unassigned|e1'});
  });
}
