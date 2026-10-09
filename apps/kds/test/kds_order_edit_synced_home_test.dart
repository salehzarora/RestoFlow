import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/kds_synced_home.dart';
import 'package:restoflow_kds/src/print/kds_native_printer.dart';
import 'package:restoflow_kds/src/print/kds_print_bridge.dart';
import 'package:restoflow_kds/src/print/kds_ticket_document.dart';
import 'package:restoflow_kds/src/print/print_document.dart' as app;
import 'package:restoflow_kds/src/state/kds_edit_ack_controller.dart';
import 'package:restoflow_kds/src/state/kds_kitchen_print_controller.dart';
import 'package:restoflow_kds/src/state/kds_session.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show hasNativePrinterProvider;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:restoflow_sync/restoflow_sync.dart';

/// ORDER-EDIT-001D (design §7.2, API_CONTRACT §4.46) — "Got it" on the LIVE
/// board, end to end: real pulled rows -> the real mapper -> the card -> the
/// `order.edit_ack` op through the existing transport -> the honest pending /
/// failed state -> the authoritative pull clearing the change. And the change
/// chit: printed ONCE, only when the server applied the tap AND this tap
/// stamped an edit (`acknowledged_count > 0`), computed from the board the
/// cook confirmed — even when the ack's own refresh already cleared it.

// ---------------------------------------------------------------------------
// Server-shaped pull rows (money-free: the kitchen redaction strips every
// `*_minor` key).
// ---------------------------------------------------------------------------
const _o1 = '11111111-0000-4000-8000-0000000000a1';
const _e1 = '55555555-0000-4000-8000-0000000000e1';
const _card = '$_o1:unassigned';
const _t0 = '2026-10-08T10:00:00Z';
const _tEdit = '2026-10-08T10:20:00Z';
const _tAck = '2026-10-08T10:30:00Z';

Map<String, dynamic> _orderRow({String status = 'preparing'}) => {
  'id': _o1,
  'status': status,
  'order_type': 'takeaway',
  'notes': null,
  'dispatch_mode': 'kds',
  'kitchen_ack_required': false,
  'kitchen_ack_at': null,
  'edit_count': 1,
  'client_created_at': _t0,
  'created_at': _t0,
  'deleted_at': null,
};

Map<String, dynamic> _itemRow(
  String id, {
  required String name,
  required int qty,
  required int linePosition,
  String status = 'preparing',
  String? removedBy,
  String? removedStage,
}) => {
  'id': id,
  'order_id': _o1,
  'station_id': null,
  'status': status,
  'quantity': qty,
  'menu_item_name_snapshot': name,
  'notes': null,
  'service_round_id': null,
  'line_position': linePosition,
  'category_display_order_snapshot': 1,
  'item_display_order_snapshot': linePosition,
  'edit_id': null,
  'removed_by_edit_id': removedBy,
  'replaces_order_item_id': null,
  'removed_kitchen_stage': removedStage,
  'created_at': _t0,
  'deleted_at': null,
};

/// A preparing order whose Burger ×2 an unconfirmed edit 1 REMOVED; Fries
/// stays. With [ackAt] the edit is confirmed and the change is gone.
KdsSyncState _state({
  String? ackAt,
  String orderStatus = 'preparing',
  String? removedStage,
}) => KdsSyncState(
  status: KdsSyncStatus.data,
  entities: {
    'orders': [_orderRow(status: orderStatus)],
    'order_items': [
      _itemRow(
        'i1',
        name: 'Burger',
        qty: 2,
        linePosition: 1,
        status: 'voided',
        removedBy: _e1,
        removedStage: removedStage ?? orderStatus,
      ),
      _itemRow('i2', name: 'Fries', qty: 1, linePosition: 2),
    ],
    'order_edits': [
      {
        'id': _e1,
        'order_id': _o1,
        'edit_number': 1,
        'kitchen_channel': 'kds',
        'kitchen_ack_required': true,
        'kitchen_ack_at': ackAt,
        'reason_code': 'customer_changed_mind',
        'reason_text': null,
        'employee_profile_id': 'emp-cashier',
        'pin_session_id': 'pin-session-cashier',
        'client_created_at': _tEdit,
        'created_at': _tEdit,
        'updated_at': ackAt ?? _tEdit,
        'deleted_at': null,
      },
    ],
  },
);

/// The same preparing order BEFORE the edit: Burger ×2 and Fries, no edit.
KdsSyncState _preEditState() => KdsSyncState(
  status: KdsSyncStatus.data,
  entities: {
    'orders': [
      {..._orderRow(), 'edit_count': 0},
    ],
    'order_items': [
      _itemRow('i1', name: 'Burger', qty: 2, linePosition: 1),
      _itemRow('i2', name: 'Fries', qty: 1, linePosition: 2),
    ],
    'order_edits': const <Map<String, dynamic>>[],
  },
);

/// A synchronous source: [emit] updates `state` at once (so the repository's
/// re-derive sees it), and [refresh] publishes [onRefresh] when set — the
/// canonical immediate pull after a push.
class _Source implements KdsSyncSource {
  _Source(this._state);

  final StreamController<KdsSyncState> _controller =
      StreamController<KdsSyncState>.broadcast();
  KdsSyncState _state;
  KdsSyncState? onRefresh;

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
  Future<void> refresh() async {
    final next = onRefresh;
    if (next != null) emit(next);
  }

  @override
  Future<void> resume() async {}
  @override
  Future<void> dispose() async => _controller.close();
}

/// Captures every pushed op; answers `order.edit_ack` with [editAck] (or
/// throws when [throwOnEditAck]).
class _Transport implements SyncRpcTransport {
  _Transport({this.editAck = const {}, this.throwOnEditAck = false});

  Map<String, dynamic> editAck;
  bool throwOnEditAck;
  final List<Map<String, dynamic>> ops = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    final results = <Object?>[];
    for (final raw in params['p_operations'] as List) {
      final op = (raw as Map).cast<String, dynamic>();
      ops.add(op);
      final isEditAck = op['operation_type'] == 'order.edit_ack';
      if (isEditAck && throwOnEditAck) throw StateError('network down');
      results.add({
        'local_operation_id': op['local_operation_id'],
        ...(isEditAck ? editAck : {'status': 'applied', 'ok': true}),
      });
    }
    return {'ok': true, 'results': results};
  }
}

class _CapturingBridge implements KdsPrintBridge {
  final List<app.PrintDocument> submitted = [];
  @override
  Future<pp.BridgeSubmitResult> submit(app.PrintDocument document) async {
    submitted.add(document);
    return const pp.BridgeSubmitResult.sentToPrinter();
  }

  @override
  Future<pp.BridgeHealth> health() async => pp.BridgeHealth.connected;
}

Map<String, dynamic> _applied(int count) => {
  'status': 'applied',
  'ok': true,
  'acknowledged_count': count,
};

Map<String, dynamic> _rejected(String error) => {
  'status': 'rejected',
  'ok': false,
  'error': error,
};

class _Harness {
  _Harness(WidgetTester tester, {KdsSyncState? initial, _Transport? transport})
    : source = _Source(initial ?? _state()),
      transport = transport ?? _Transport(editAck: _applied(1)) {
    container = ProviderContainer(
      overrides: [
        kdsSyncSourceProvider.overrideWithValue(source),
        kdsAuthTransportProvider.overrideWithValue(this.transport),
        kdsSyncSessionProvider.overrideWithValue(
          const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
        ),
        kdsActivePrintBridgeReadyProvider.overrideWith((ref) async => bridge),
        hasNativePrinterProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(source.dispose);
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  final _Source source;
  final _Transport transport;
  final _CapturingBridge bridge = _CapturingBridge();
  late final ProviderContainer container;

  KdsEditAckState get ack => container.read(kdsEditAckControllerProvider);

  List<String> get submittedTexts => [
    for (final doc in bridge.submitted)
      for (final l in doc.lines) l.left ?? '',
  ];

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
    // The loading spinner is an infinite animation: fixed pumps only.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  /// Lets the async "Got it" chain (push, pull, bridge, print) run.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> gotIt(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('kds-edit-ack-$_card')));
    await settle(tester);
  }

  Future<void> emit(WidgetTester tester, KdsSyncState s) async {
    source.emit(s);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<AppLocalizations> _l10n() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  testWidgets('"Got it" sends ONE canonical order.edit_ack op, the card shows '
      'pending; the confirmed pull returns the normal action and empties the '
      'controller', (tester) async {
    final l10n = await _l10n();
    final h = _Harness(tester);
    await h.pumpHome(tester);
    expect(find.text(l10n.kitchenEditRemovedLabel), findsOneWidget);
    expect(find.text(l10n.kdsReadyAction), findsNothing);

    await h.gotIt(tester);
    final op = h.transport.ops.single;
    expect(op['operation_type'], 'order.edit_ack');
    expect(op['target_entity'], 'order');
    expect(op['target_id'], _o1);
    expect(op['payload'], {'order_id': _o1, 'up_to_edit_number': 1});
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('kds-edit-ack-$_card')))
          .onPressed,
      isNull,
    );
    expect(find.text(l10n.kdsAckPending), findsOneWidget);
    expect(h.ack.pending.keys, ['$_card|e1']);

    // The authoritative pull carries kitchen_ack_at: the change is gone.
    await h.emit(tester, _state(ackAt: _tAck));
    expect(find.byKey(const Key('kds-edit-ack-$_card')), findsNothing);
    expect(find.text(l10n.kitchenEditRemovedLabel), findsNothing);
    expect(find.text(l10n.kdsReadyAction), findsOneWidget);
    expect(h.ack.pending, isEmpty);
    expect(h.ack.failed, isEmpty);
  });

  testWidgets('an invalid_edit_number refusal shows the failure line and '
      'keeps "Got it" retryable', (tester) async {
    final l10n = await _l10n();
    final h = _Harness(
      tester,
      transport: _Transport(editAck: _rejected('invalid_edit_number')),
    );
    await h.pumpHome(tester);
    await h.gotIt(tester);
    expect(find.byKey(const Key('kds-edit-ack-failed-$_card')), findsOneWidget);
    expect(find.text(l10n.kdsAckFailed), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('kds-edit-ack-$_card')))
          .onPressed,
      isNotNull,
    );
    expect(h.bridge.submitted, isEmpty);
  });

  group('the change chit', () {
    testWidgets('applied with acknowledged_count 2: exactly ONE chit — '
        'REMOVED 2 × Burger, under the change title', (tester) async {
      final h = _Harness(tester, transport: _Transport(editAck: _applied(2)));
      await h.pumpHome(tester);
      await h.gotIt(tester);
      expect(h.bridge.submitted, hasLength(1));
      final texts = h.submittedTexts;
      expect(texts, contains('*** ORDER CHANGED · Change 1 ***'));
      expect(texts, containsAllInOrder(['REMOVED', '2 × Burger']));
      expect(texts.where((t) => t.contains('Fries')), isEmpty);
      final jobs = h.container.read(kdsKitchenPrintControllerProvider);
      expect(
        jobs[KdsKitchenPrintController.chitKeyFor(_o1, 1)]?.status,
        KdsPrintJobStatus.sentToPrinter,
      );
      // A second tap on the still-pending card never prints again.
      await tester.tap(
        find.byKey(const Key('kds-edit-ack-$_card')),
        warnIfMissed: false,
      );
      await h.settle(tester);
      expect(h.bridge.submitted, hasLength(1));
      expect(h.transport.ops, hasLength(1));
    });

    final noChit = <(String, _Transport)>[
      (
        'count 0 (another KDS confirmed first)',
        _Transport(editAck: _applied(0)),
      ),
      (
        'order_voided (superseded by the void)',
        _Transport(editAck: _rejected('order_voided')),
      ),
      (
        'another refusal (permission_denied)',
        _Transport(editAck: _rejected('permission_denied')),
      ),
      ('a transport throw', _Transport(throwOnEditAck: true)),
    ];
    for (final (name, transport) in noChit) {
      testWidgets('no chit on $name', (tester) async {
        final h = _Harness(tester, transport: transport);
        await h.pumpHome(tester);
        await h.gotIt(tester);
        expect(h.transport.ops.single['operation_type'], 'order.edit_ack');
        expect(h.bridge.submitted, isEmpty);
        expect(h.container.read(kdsKitchenPrintControllerProvider), isEmpty);
      });
    }

    testWidgets('the chit uses the board the cook CONFIRMED: the ack\'s own '
        'refresh clearing the change still prints it', (tester) async {
      final l10n = await _l10n();
      final h = _Harness(tester, transport: _Transport(editAck: _applied(1)));
      h.source.onRefresh = _state(ackAt: _tAck);
      await h.pumpHome(tester);
      await h.gotIt(tester);
      // The refresh already landed: the board no longer shows the change…
      expect(find.text(l10n.kitchenEditRemovedLabel), findsNothing);
      expect(find.text(l10n.kdsReadyAction), findsOneWidget);
      // …yet the chit printed what the cook confirmed.
      expect(h.bridge.submitted, hasLength(1));
      expect(h.submittedTexts, containsAllInOrder(['REMOVED', '2 × Burger']));
    });

    testWidgets('a unit never printed (still New, no local job) gets no chit', (
      tester,
    ) async {
      final h = _Harness(
        tester,
        initial: _state(orderStatus: 'submitted'),
        transport: _Transport(editAck: _applied(1)),
      );
      await h.pumpHome(tester);
      await h.gotIt(tester);
      expect(h.transport.ops.single['operation_type'], 'order.edit_ack');
      expect(h.bridge.submitted, isEmpty);
    });
  });

  group('the change pulse seeds only from an authoritative board', () {
    const pulse = Key('kds-change-arrival-$_card|e1');

    testWidgets('a change already pending when the board LOADS never pulses, '
        'even after the empty initial / loading boards of an app start or '
        'sign-in', (tester) async {
      final h = _Harness(tester, initial: KdsSyncState.initial);
      await h.pumpHome(tester);
      await h.emit(tester, const KdsSyncState(status: KdsSyncStatus.loading));
      await h.emit(tester, _state());
      expect(find.byKey(const Key('kds-change-header-$_card')), findsOneWidget);
      expect(find.byKey(pulse), findsNothing);
    });

    testWidgets('a change that ARRIVES after the first authoritative pull '
        'still pulses', (tester) async {
      final h = _Harness(tester, initial: KdsSyncState.initial);
      await h.pumpHome(tester);
      await h.emit(tester, const KdsSyncState(status: KdsSyncStatus.loading));
      await h.emit(tester, _preEditState());
      expect(find.byKey(pulse), findsNothing);
      await h.emit(tester, _state());
      expect(find.byKey(pulse), findsOneWidget);
    });
  });

  group('a "Got it" whose outcome is UNKNOWN still owes its chit', () {
    testWidgets('applied on the server but the reply was LOST: the next '
        'authoritative pull without the change replays the SAME operation '
        'id and prints the chit ONCE from the confirmed board', (tester) async {
      final h = _Harness(tester, transport: _Transport(throwOnEditAck: true));
      await h.pumpHome(tester);
      await h.gotIt(tester);
      expect(h.bridge.submitted, isEmpty);
      final firstId = h.transport.ops.single['local_operation_id'];

      // The server HAD applied it: a replay returns the stored result.
      h.transport
        ..throwOnEditAck = false
        ..editAck = _applied(1);
      // The next poll carries kitchen_ack_at: the card is back to normal and
      // there is nothing left to re-tap.
      await h.emit(tester, _state(ackAt: _tAck));
      await h.settle(tester);
      expect(find.byKey(const Key('kds-edit-ack-$_card')), findsNothing);
      expect(h.transport.ops, hasLength(2));
      expect(h.transport.ops.last['local_operation_id'], firstId);
      expect(h.transport.ops.last['payload'], {
        'order_id': _o1,
        'up_to_edit_number': 1,
      });
      expect(h.bridge.submitted, hasLength(1));
      expect(h.submittedTexts, contains('*** ORDER CHANGED · Change 1 ***'));
      expect(h.submittedTexts, containsAllInOrder(['REMOVED', '2 × Burger']));

      // Later pulls never replay or print again.
      await h.emit(tester, _state(ackAt: _tAck));
      await h.settle(tester);
      expect(h.transport.ops, hasLength(2));
      expect(h.bridge.submitted, hasLength(1));
    });

    testWidgets('while the change still shows nothing replays (the failed '
        'card keeps its retry); a replay answered with count 0 prints '
        'nothing and is never sent again', (tester) async {
      final h = _Harness(tester, transport: _Transport(throwOnEditAck: true));
      await h.pumpHome(tester);
      await h.gotIt(tester);
      h.transport
        ..throwOnEditAck = false
        ..editAck = _applied(0);
      await h.emit(tester, _state());
      await h.settle(tester);
      expect(h.transport.ops, hasLength(1));
      expect(
        find.byKey(const Key('kds-edit-ack-failed-$_card')),
        findsOneWidget,
      );

      // Another KDS confirmed it: the replay stamps nothing, no chit.
      await h.emit(tester, _state(ackAt: _tAck));
      await h.settle(tester);
      expect(h.transport.ops, hasLength(2));
      expect(h.bridge.submitted, isEmpty);
      await h.emit(tester, _state(ackAt: _tAck));
      await h.settle(tester);
      expect(h.transport.ops, hasLength(2));
    });

    testWidgets('a re-tap that settles the same operation prints through the '
        'normal path, and the later pull replays nothing', (tester) async {
      final h = _Harness(tester, transport: _Transport(throwOnEditAck: true));
      await h.pumpHome(tester);
      await h.gotIt(tester);
      h.transport
        ..throwOnEditAck = false
        ..editAck = _applied(1);
      await h.gotIt(tester);
      expect(h.transport.ops, hasLength(2));
      expect(
        h.transport.ops.last['local_operation_id'],
        h.transport.ops.first['local_operation_id'],
      );
      expect(h.bridge.submitted, hasLength(1));

      await h.emit(tester, _state(ackAt: _tAck));
      await h.settle(tester);
      expect(h.transport.ops, hasLength(2));
      expect(h.bridge.submitted, hasLength(1));
    });
  });

  testWidgets('a STANDALONE change card never shows its old unit\'s print '
      'status or Reprint, even when a job exists under that key', (
    tester,
  ) async {
    final l10n = await _l10n();
    // A completed order whose removal is unconfirmed: a standalone card that
    // shares the original unit's print key.
    final h = _Harness(
      tester,
      initial: _state(orderStatus: 'completed', removedStage: 'ready'),
    );
    final unit = KdsTicketView(
      kitchenTicketId: _card,
      stationId: 'unassigned',
      orderId: _o1,
      items: const [KdsItemView(name: 'Burger', quantity: 2)],
    );
    h.container
        .read(kdsKitchenPrintControllerProvider.notifier)
        .prepareForTicket(
          unit,
          hasEnabledPrinter: true,
          buildDocument: () => buildKdsTicketDocument(l10n, unit),
        );
    h.container
        .read(kdsKitchenPrintControllerProvider.notifier)
        .markSentToPrinter(KdsKitchenPrintController.keyFor(unit));
    await h.pumpHome(tester);
    expect(find.byKey(const Key('kds-change-header-$_card')), findsOneWidget);
    expect(find.text(l10n.kdsEditGotIt), findsOneWidget);
    expect(find.byKey(const Key('ticket-print-status')), findsNothing);
    expect(find.byKey(const Key('kds-reprint-$_card')), findsNothing);
    expect(find.text(l10n.printStatusSentToPrinter), findsNothing);
  });
}
