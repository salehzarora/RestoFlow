import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/kds_synced_home.dart';
import 'package:restoflow_kds/src/print/kds_acknowledge_print.dart';
import 'package:restoflow_kds/src/print/kds_native_printer.dart';
import 'package:restoflow_kds/src/print/kds_print_bridge.dart';
import 'package:restoflow_kds/src/print/print_document.dart' as app;
import 'package:restoflow_kds/src/state/kds_kitchen_print_controller.dart';
import 'package:restoflow_kds/src/state/kds_session.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show hasNativePrinterProvider;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:restoflow_sync/restoflow_sync.dart';

/// ORDER-EDIT-001D (design §7.2) — print-on-Acknowledge prints the ticket
/// RE-DERIVED after the post-push pull, never the card captured at tap time:
/// an edit that landed before the pull prints fresh. The match is the WORK
/// UNIT (the print job's key), and nothing prints when the unit left the
/// board, was voided, or exists only as a change card.

KdsTicketView _ticket({
  String orderId = 'o1',
  String station = 'grill',
  String? roundId,
  List<KdsItemView> items = const [
    KdsItemView(name: 'Burger', quantity: 2),
    KdsItemView(name: 'Fries', quantity: 1),
  ],
  KitchenTicketStatus status = KitchenTicketStatus.newTicket,
  String? voidedFromStatus,
  KdsTicketChange? change,
  bool withOrderId = true,
}) => KdsTicketView(
  kitchenTicketId: roundId == null
      ? '$orderId:$station'
      : '$orderId:$station:r$roundId',
  stationId: station,
  orderId: withOrderId ? orderId : null,
  orderNumber: '#ABC123',
  roundId: roundId,
  roundNumber: roundId == null ? null : 2,
  status: status,
  voidedFromStatus: voidedFromStatus,
  items: items,
  change: change,
);

KdsTicketChange _change({bool standalone = false, bool emptied = false}) =>
    KdsTicketChange(
      pendingEdits: const [
        KdsOrderEdit(
          id: 'e1',
          orderId: 'o1',
          editNumber: 1,
          channel: KdsEditChannel.kds,
          ackRequired: true,
        ),
      ],
      standalone: standalone,
      emptied: emptied,
      orderPendingEditNumbers: const [1],
    );

// ---------------------------------------------------------------------------
// Server-shaped pull rows for the end-to-end Acknowledge wiring (money-free:
// the kitchen redaction strips every `*_minor` key).
// ---------------------------------------------------------------------------
const _o1 = '11111111-0000-4000-8000-0000000000a1';
const _e1 = '55555555-0000-4000-8000-0000000000e1';
const _t0 = '2026-10-08T10:00:00Z';
const _tEdit = '2026-10-08T10:05:00Z';

Map<String, dynamic> _orderRow({required String status, int editCount = 0}) => {
  'id': _o1,
  'status': status,
  'order_type': 'takeaway',
  'notes': null,
  'dispatch_mode': 'kds',
  'kitchen_ack_required': false,
  'kitchen_ack_at': null,
  'edit_count': editCount,
  'client_created_at': _t0,
  'created_at': _t0,
  'deleted_at': null,
};

Map<String, dynamic> _itemRow(
  String id, {
  required String name,
  required int qty,
  required int linePosition,
  String status = 'pending',
  String? editId,
  String? replaces,
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
  'edit_id': editId,
  'removed_by_edit_id': removedBy,
  'replaces_order_item_id': replaces,
  'removed_kitchen_stage': removedStage,
  'created_at': _t0,
  'deleted_at': null,
};

/// Before the tap: a Waiting order, Burger ×2 + Fries ×1.
KdsSyncState _beforeEdit() => KdsSyncState(
  status: KdsSyncStatus.data,
  entities: {
    'orders': [_orderRow(status: 'submitted')],
    'order_items': [
      _itemRow('i1', name: 'Burger', qty: 2, linePosition: 1),
      _itemRow('i2', name: 'Fries', qty: 1, linePosition: 2),
    ],
  },
);

/// The post-push pull: the order is accepted AND an unconfirmed edit that
/// landed while it was Waiting reduced Burger to 1 and removed Fries.
KdsSyncState _afterEdit() => KdsSyncState(
  status: KdsSyncStatus.data,
  entities: {
    'orders': [_orderRow(status: 'accepted', editCount: 1)],
    'order_items': [
      _itemRow(
        'i1',
        name: 'Burger',
        qty: 2,
        linePosition: 1,
        status: 'cancelled',
        removedBy: _e1,
        removedStage: 'submitted',
      ),
      _itemRow(
        'i2',
        name: 'Fries',
        qty: 1,
        linePosition: 2,
        status: 'cancelled',
        removedBy: _e1,
        removedStage: 'submitted',
      ),
      _itemRow(
        'i3',
        name: 'Burger',
        qty: 1,
        linePosition: 1,
        editId: _e1,
        replaces: 'i1',
      ),
    ],
    'order_edits': [
      {
        'id': _e1,
        'order_id': _o1,
        'edit_number': 1,
        'kitchen_channel': 'kds',
        'kitchen_ack_required': true,
        'kitchen_ack_at': null,
        'reason_code': 'customer_changed_mind',
        'reason_text': null,
        'client_created_at': _tEdit,
        'created_at': _tEdit,
        'deleted_at': null,
      },
    ],
  },
);

/// A source whose immediate pull (the post-push refresh) returns the edited
/// rows — the board the print must be re-derived from.
class _EditingSource implements KdsSyncSource {
  _EditingSource(this._state, this._afterRefresh);

  final StreamController<KdsSyncState> _controller =
      StreamController<KdsSyncState>.broadcast();
  KdsSyncState _state;
  final KdsSyncState _afterRefresh;

  @override
  KdsSyncState get state => _state;
  @override
  Stream<KdsSyncState> get states => _controller.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> refresh() async {
    _state = _afterRefresh;
    _controller.add(_state);
  }

  @override
  Future<void> resume() async {}
  @override
  Future<void> dispose() async => _controller.close();
}

class _OkTransport implements SyncRpcTransport {
  final List<String> operationTypes = [];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    for (final op in params['p_operations'] as List) {
      operationTypes.add((op as Map)['operation_type'] as String);
    }
    return {'ok': true, 'results': <Object?>[]};
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

void main() {
  group('kdsTicketForAcknowledgePrint', () {
    test('the FRESH ticket wins: a removed line is absent and a reduced '
        'quantity is the new value', () {
      final tapped = _ticket();
      final fresh = _ticket(
        status: KitchenTicketStatus.acknowledged,
        items: const [KdsItemView(name: 'Burger', quantity: 1)],
      );
      final printable = kdsTicketForAcknowledgePrint(tapped, [
        _ticket(orderId: 'o2'),
        fresh,
      ]);
      expect(printable, same(fresh));
      expect(
        [for (final i in printable!.items) '${i.quantity} ${i.name}'],
        ['1 Burger'],
      );
    });

    test('a fresh ticket carrying a (non-standalone) change still prints', () {
      final fresh = _ticket(change: _change());
      expect(kdsTicketForAcknowledgePrint(_ticket(), [fresh]), same(fresh));
    });

    test('null when the unit left the board', () {
      expect(kdsTicketForAcknowledgePrint(_ticket(), const []), isNull);
      expect(
        kdsTicketForAcknowledgePrint(_ticket(), [
          _ticket(orderId: 'o2'),
          _ticket(station: 'bar'),
        ]),
        isNull,
      );
    });

    test('null for the red cancellation card that shares the unit key', () {
      final red = _ticket(
        status: KitchenTicketStatus.cancelled,
        voidedFromStatus: 'submitted',
      );
      expect(red.requiresAck, isTrue);
      expect(kdsTicketForAcknowledgePrint(_ticket(), [red]), isNull);
    });

    test('null for a standalone or an emptied change card', () {
      expect(
        kdsTicketForAcknowledgePrint(_ticket(), [
          _ticket(change: _change(standalone: true)),
        ]),
        isNull,
      );
      expect(
        kdsTicketForAcknowledgePrint(_ticket(), [
          _ticket(change: _change(emptied: true)),
        ]),
        isNull,
      );
    });

    test('null when no live line is left', () {
      expect(
        kdsTicketForAcknowledgePrint(_ticket(), [_ticket(items: const [])]),
        isNull,
      );
    });

    test('a round and its order\'s original unit never cross-match', () {
      final original = _ticket();
      final round = _ticket(roundId: 'r2');
      expect(kdsTicketForAcknowledgePrint(original, [round]), isNull);
      expect(kdsTicketForAcknowledgePrint(round, [original]), isNull);
      expect(
        kdsTicketForAcknowledgePrint(round, [original, round]),
        same(round),
      );
      expect(
        kdsTicketForAcknowledgePrint(original, [round, original]),
        same(original),
      );
    });

    test('a demo ticket (no order id) matches on its ticket id', () {
      final demo = _ticket(withOrderId: false);
      expect(kdsTicketForAcknowledgePrint(demo, [demo]), same(demo));
    });
  });

  testWidgets('Acknowledge prints EXACTLY ONE document holding the post-pull '
      'lines (removed line gone, reduced quantity new) and records the '
      'edit watermark', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final source = _EditingSource(_beforeEdit(), _afterEdit());
    final transport = _OkTransport();
    final bridge = _CapturingBridge();
    final container = ProviderContainer(
      overrides: [
        kdsSyncSourceProvider.overrideWithValue(source),
        kdsAuthTransportProvider.overrideWithValue(transport),
        kdsSyncSessionProvider.overrideWithValue(
          const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
        ),
        kdsActivePrintBridgeReadyProvider.overrideWith((ref) async => bridge),
        hasNativePrinterProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(source.dispose);

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
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Burger ×2'), findsOneWidget);
    expect(find.text('Fries ×1'), findsOneWidget);

    await tester.tap(find.text(l10n.kdsAcknowledgeAction));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 5));

    expect(transport.operationTypes, ['order.status']);
    expect(bridge.submitted, hasLength(1));
    final texts = [for (final l in bridge.submitted.single.lines) l.left ?? ''];
    expect(texts, contains('1 × Burger'));
    expect(texts.where((t) => t.contains('2 × Burger')), isEmpty);
    expect(texts.where((t) => t.contains('Fries')), isEmpty);

    final jobs = container.read(kdsKitchenPrintControllerProvider);
    expect(jobs.keys, ['$_o1|station:unassigned']);
    final job = jobs.values.single;
    expect(job.status, KdsPrintJobStatus.sentToPrinter);
    expect(job.printedThroughEdit, 1);
  });
}
