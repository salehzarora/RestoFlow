import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show BranchTax, DeviceBranchTaxReader;
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/demo_menu.dart' show DemoMenuItem;
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_edit_diff.dart';
import 'package:restoflow_pos/src/data/order_edit_journal_store.dart';
import 'package:restoflow_pos/src/data/order_edit_read_model.dart';
import 'package:restoflow_pos/src/data/order_edit_response.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosPersistenceException;
import 'package:restoflow_pos/src/state/addition_controller.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/discount_controller.dart'
    show staffCapabilitiesProvider;
import 'package:restoflow_pos/src/state/order_edit_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/parked_carts_controller.dart';
import 'package:restoflow_pos/src/state/pos_branch_tax.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_offline_state.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';

import 'support/order_edit_fixtures.dart';

/// ORDER-EDIT-001E — the [OrderEditController] (plan step 7, test 11), driven
/// through a ProviderContainer with a SCRIPTED `sync_push`, a recording
/// journal and a scripted authoritative detail:
///
///  * entry refuses up front, reserves the order, and its fence loses to a
///    cart line added during the load;
///  * the journal record is written strictly BEFORE the invoke, and a refused
///    write sends nothing;
///  * a retry re-sends the SAME identity with a byte-identical payload; a
///    double tap sends once; discard is refused once dispatched;
///  * an applied edit is cleaned up only after the detail PROVES it, and the
///    refresh retry never dispatches again;
///  * every refusal maps to its message and effect (API §4.45.6), a rebase
///    drops what no longer applies and resends under a NEW identity, and tax
///    drift gets ONE automatic rebase (decision D9);
///  * a restart blocks the order and replays the record verbatim;
///  * a worker change discards only an UNSENT edit (D12);
///  * an edit and an addition never share the cart.
///
/// Every amount is an independent literal (D-007).

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

typedef _Handler = Object? Function(Map<String, dynamic> op);

class _Transport implements SyncRpcTransport {
  _Transport(this.log, this.script);
  final List<String> log;
  final List<_Handler> script;
  final List<Map<String, dynamic>> ops = [];
  Completer<void>? gate;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function != 'sync_push') return {'ok': false};
    final op = ((params['p_operations'] as List).single as Map)
        .cast<String, dynamic>();
    expect(params['p_pin_session_id'], 'pin-1');
    expect(params['p_device_id'], 'dev-1');
    ops.add(op);
    log.add('invoke:${op['local_operation_id']}');
    if (gate case final g?) await g.future;
    final handler = script.length >= ops.length
        ? script[ops.length - 1]
        : script.last;
    return handler(op);
  }
}

class _Details implements OrderDetailRepository {
  final Map<String, PosOrderDetail> byId = {};
  Object? error;
  Completer<void>? gate;
  int fetches = 0;

  @override
  Future<PosOrderDetail> fetch(String orderId) async {
    fetches++;
    if (gate case final g?) await g.future;
    if (error case final e?) throw e;
    final d = byId[orderId];
    if (d == null) {
      throw const PosOrderDetailException(
        PosOrderDetailFailure.notFound,
        'order_not_found',
      );
    }
    return d;
  }
}

class _Tax implements DeviceBranchTaxReader {
  BranchTax tax = BranchTax.disabled;
  int loads = 0;

  @override
  Future<BranchTax?> load() async {
    loads++;
    return tax;
  }
}

class _Journal implements OrderEditJournalStore {
  List<String> log = [];
  final InMemoryOrderEditJournalStore inner = InMemoryOrderEditJournalStore();
  bool failWrites = false;
  bool failLoads = false;

  @override
  Future<Map<String, OrderEditJournalRecord>> load(String scopeKey) async {
    if (failLoads) throw StateError('unreadable');
    return inner.load(scopeKey);
  }

  @override
  Future<void> persist(
    String scopeKey,
    Map<String, OrderEditJournalRecord> records,
  ) async {
    log.add('persist:${records.values.map((r) => r.phase.name).join(',')}');
    if (failWrites) {
      throw const PosPersistenceException('the journal refused the write');
    }
    await inner.persist(scopeKey, records);
  }

  Future<Map<String, OrderEditJournalRecord>> stored() => inner.load('dev-1');
}

const _features = {
  'order_edit_enabled': true,
  'order_edit_finished_food_manager_only': false,
};

PosStaffCapabilities _caps({Object? voidOrder = true}) =>
    PosStaffCapabilities.fromJson(
      {
        'apply_discount': true,
        'apply_full_comp': true,
        if (voidOrder != null) 'void_order': voidOrder,
      },
      role: 'cashier',
      branchFeatures: _features,
    );

const _lemonade = DemoMenuItem(
  id: 'mi-lemonade',
  name: 'Lemonade',
  priceMinor: 900,
  categoryId: 'cat',
  categoryName: 'Cat',
);

final _menu = menuOf(
  [
    menuItem('mi-burger', name: 'Burger', price: 4000),
    menuItem('mi-fries', name: 'Fries', price: 1500),
    menuItem('mi-cola', name: 'Cola', price: 800),
    menuItem('mi-lemonade', name: 'Lemonade', price: 900),
  ],
  groups: [
    menuGroup('grp-top', 'mi-burger', const [
      PosModifierOption(id: 'opt-bacon', name: 'Bacon', priceDeltaMinor: 500),
    ]),
  ],
);

PosOrderDetailItem _burger({
  String id = 'oi-burger',
  int quantity = 2,
  String status = 'preparing',
  int lineDiscount = 0,
}) => detailItem(
  id,
  menuItemId: 'mi-burger',
  name: 'Burger',
  quantity: quantity,
  unit: 4000,
  lineDiscount: lineDiscount,
  unitStatus: status,
);

PosOrderDetailItem _fries({String id = 'oi-fries', String? notes}) =>
    detailItem(
      id,
      menuItemId: 'mi-fries',
      name: 'Fries',
      unit: 1500,
      notes: notes,
      unitStatus: 'preparing',
    );

/// The order being edited: Burger ×2 at 4000 + Fries at 1500 = 9500.
PosOrderDetail _order({
  List<PosOrderDetailItem>? items,
  String orderId = 'order-1',
  int editCount = 0,
  List<PosOrderDetailEdit>? edits = const [],
  PosBranchFeatures? features = kFeaturesOn,
  PosKitchenChannel? channel = PosKitchenChannel.kds,
  bool paid = false,
  String status = 'preparing',
}) {
  final d = detail(
    items: items ?? [_burger(), _fries()],
    features: features,
    channel: channel,
    paid: paid,
    status: status,
  );
  return PosOrderDetail(
    orderId: orderId,
    orderCode: orderId == 'order-1' ? '#A1B2C3' : '#B00002',
    orderType: d.orderType,
    status: d.status,
    revision: d.revision,
    currencyCode: d.currencyCode,
    subtotalMinor: d.subtotalMinor,
    discountTotalMinor: d.discountTotalMinor,
    taxTotalMinor: d.taxTotalMinor,
    grandTotalMinor: d.grandTotalMinor,
    items: d.items,
    rounds: d.rounds,
    tableLabel: d.tableLabel,
    payment: d.payment,
    kitchenChannel: d.kitchenChannel,
    branchFeatures: d.branchFeatures,
    editCount: editCount,
    edits: edits,
  );
}

/// The order after the server applied `edit-1` ("Change 1").
PosOrderDetail _edited({List<PosOrderDetailItem>? items}) => _order(
  items: items ?? [_burger()],
  editCount: 1,
  edits: const [PosOrderDetailEdit(orderEditId: 'edit-1', editNumber: 1)],
);

Map<String, Object?> _envelope(
  Map<String, dynamic> op,
  Map<String, Object?> row,
) => {
  'ok': true,
  'results': [
    {
      'local_operation_id': op['local_operation_id'],
      'operation_type': 'order.edit',
      ...row,
    },
  ],
};

_Handler _applied({
  bool ackRequired = true,
  String channel = 'kds',
  List<Map<String, Object?>> changes = const [],
}) =>
    (op) => _envelope(op, {
      'status': 'applied',
      'ok': true,
      'order_id': 'order-1',
      'order_edit_id': 'edit-1',
      'edit_number': 1,
      'revision': 4,
      'kitchen_channel': channel,
      'kitchen_ack_required': ackRequired,
      'new_round_id': 'round-2',
      'new_round_number': 2,
      'changes': changes,
    });

_Handler _refused(String code, [Map<String, Object?> extra = const {}]) =>
    (op) => _envelope(op, {'status': 'rejected', 'error': code, ...extra});

_Handler _raised(String sqlstate, {String? detail}) =>
    (op) => _envelope(op, {
      'status': 'rejected',
      'error': 'rejected',
      'sqlstate': sqlstate,
      if (detail != null) 'detail': detail,
    });

Object? _conflict(Map<String, dynamic> op) =>
    _envelope(op, {'status': 'conflict', 'error': 'conflict'});

Object? _absent(Map<String, dynamic> op) => {
  'ok': true,
  'results': <Object?>[],
};

Object? _down(Map<String, dynamic> op) => throw const SyncTransportException(
  SyncTransportErrorKind.transient,
  code: 'offline',
);

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _H {
  _H({
    List<_Handler>? script,
    _Journal? journal,
    bool withJournal = true,
    PosStaffCapabilities? caps,
    List<String> ids = const ['op-1', 'op-2', 'op-3', 'op-4'],
  }) {
    transport = _Transport(log, script ?? [_applied()]);
    this.journal = journal ?? (withJournal ? _Journal() : null);
    this.journal?.log = log;
    details.byId['order-1'] = _order();
    final capabilities = caps ?? _caps();
    c = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posAuthTransportProvider.overrideWithValue(transport),
        posSyncSessionProvider.overrideWithValue(_session),
        orderDetailRepositoryProvider.overrideWithValue(details),
        orderSnapshotRepositoryProvider.overrideWithValue(
          DemoOrderSnapshotRepository(),
        ),
        posSyncPollIntervalProvider.overrideWithValue(null),
        posBranchTaxReaderProvider.overrideWithValue(tax),
        posMenuProvider.overrideWith((ref) async {
          menuLoads++;
          return _menu;
        }),
        staffCapabilitiesProvider.overrideWith((ref) async {
          capsLoads++;
          return capabilities;
        }),
        clientIdGeneratorProvider.overrideWithValue(
          FixedClientIdGenerator(ids),
        ),
        if (this.journal case final j?)
          orderEditJournalStoreProvider.overrideWithValue(j),
      ],
    );
    addTearDown(c.dispose);
  }

  final List<String> log = [];
  late final _Transport transport;
  late final _Journal? journal;
  final _Details details = _Details();
  final _Tax tax = _Tax();
  int menuLoads = 0;
  int capsLoads = 0;
  late final ProviderContainer c;

  OrderEditController get edit => c.read(orderEditControllerProvider.notifier);
  OrderEditState get state => c.read(orderEditControllerProvider);
  CartController get cart => c.read(cartControllerProvider.notifier);
  CartViewState get cartState => c.read(cartControllerProvider);
  AdditionController get addition =>
      c.read(additionControllerProvider.notifier);

  /// Builds the controller and lets the journal hydrate.
  Future<void> boot() async {
    c.read(orderEditControllerProvider);
    await _settle();
  }

  Future<void> enter([String orderId = 'order-1']) async {
    await boot();
    expect(await edit.enterForOrder(orderId), OrderEditEntryResult.entered);
  }

  void goOffline() => c
      .read(posOfflineModeProvider.notifier)
      .recordOfflineCacheServed(snapshotFetchedAt: DateTime.utc(2026, 10, 9));
}

void main() {
  group('entry', () {
    test('reserves, re-reads tax, fetches the detail and loads the edit '
        'cart', () async {
      final h = _H();
      await h.enter();
      expect(h.state.phase, OrderEditPhase.active);
      expect(h.state.entryOrderId, 'order-1');
      expect(h.state.baseline!.orderCode, '#A1B2C3');
      expect(h.tax.loads, 1);
      expect(h.details.fetches, 1);
      expect(h.cartState.isEditing, isTrue);
      expect(h.cartState.lines.map((l) => l.lineId), [
        'sent-oi-burger',
        'sent-oi-fries',
      ]);
      // 2 × 4000 + 1500.
      expect(h.cartState.subtotalMinor, 9500);
      // Idempotent re-entry: no second fetch.
      expect(
        await h.edit.enterForOrder('order-1'),
        OrderEditEntryResult.entered,
      );
      expect(h.details.fetches, 1);
    });

    test('refuses up front without fetching: cart not empty, offline, '
        'another edit', () async {
      final h = _H();
      await h.boot();
      h.cart.addItem(_lemonade);
      expect(
        await h.edit.enterForOrder('order-1'),
        OrderEditEntryResult.cartNotEmpty,
      );
      h.cart.clear();
      h.goOffline();
      expect(
        await h.edit.enterForOrder('order-1'),
        OrderEditEntryResult.offline,
      );
      expect(h.details.fetches, 0);
      expect(h.state.phase, OrderEditPhase.idle);

      final g = _H();
      await g.enter();
      g.details.byId['order-2'] = _order(orderId: 'order-2');
      expect(await g.edit.enterForOrder('order-2'), OrderEditEntryResult.busy);
    });

    test('refuses while the edit journal is still being read', () async {
      final h = _H();
      expect(h.state.phase, OrderEditPhase.hydrating);
      expect(
        await h.edit.enterForOrder('order-1'),
        OrderEditEntryResult.hydrating,
      );
      expect(h.details.fetches, 0);
      await _settle();
      expect(h.state.phase, OrderEditPhase.idle);
    });

    test(
      'maps every ineligible detail and leaves the cart untouched',
      () async {
        final cases = <(PosOrderDetail?, Object?, OrderEditEntryResult)>[
          (null, null, OrderEditEntryResult.orderNotFound),
          (
            null,
            const PosOrderDetailException(PosOrderDetailFailure.transport),
            OrderEditEntryResult.detailUnavailable,
          ),
          (
            _order(
              features: const PosBranchFeatures(
                orderEditEnabled: false,
                finishedFoodManagerOnly: false,
              ),
            ),
            null,
            OrderEditEntryResult.featureDisabled,
          ),
          (_order(features: null), null, OrderEditEntryResult.featureDisabled),
          (_order(paid: true), null, OrderEditEntryResult.alreadyPaid),
          (
            _order(channel: null),
            null,
            OrderEditEntryResult.kitchenModeChanged,
          ),
          (_order(status: 'completed'), null, OrderEditEntryResult.notEditable),
          (
            _order(items: [detailItem('oi-x', identified: false)]),
            null,
            OrderEditEntryResult.detailUnavailable,
          ),
        ];
        for (final (d, error, expected) in cases) {
          final h = _H();
          await h.boot();
          h.details.byId.remove('order-1');
          if (d != null) h.details.byId['order-1'] = d;
          h.details.error = error;
          expect(await h.edit.enterForOrder('order-1'), expected);
          expect(h.state.phase, OrderEditPhase.idle);
          expect(h.state.generation, 2);
          expect(h.cartState.isEmpty, isTrue);
          expect(h.cartState.isEditing, isFalse);
        }
      },
    );

    test(
      'the fence: a line added during the load stays a NORMAL line',
      () async {
        final h = _H();
        await h.boot();
        h.details.gate = Completer<void>();
        final entry = h.edit.enterForOrder('order-1');
        await _settle();
        expect(h.state.phase, OrderEditPhase.entering);
        h.cart.addItem(_lemonade);
        h.details.gate!.complete();
        expect(await entry, OrderEditEntryResult.cartNotEmpty);
        expect(h.cartState.isEditing, isFalse);
        expect(h.cartState.lines.single.menuItemId, 'mi-lemonade');
        expect(h.state.phase, OrderEditPhase.idle);
      },
    );

    test('a discard while entering supersedes the late detail', () async {
      final h = _H();
      await h.boot();
      h.details.gate = Completer<void>();
      final entry = h.edit.enterForOrder('order-1');
      await _settle();
      expect(h.edit.discard(), isTrue);
      h.details.gate!.complete();
      expect(await entry, OrderEditEntryResult.superseded);
      expect(h.cartState.isEditing, isFalse);
      expect(h.state.phase, OrderEditPhase.idle);
    });
  });

  group('discard', () {
    test('before a send: the order stays as sent, the cart empties', () async {
      final h = _H();
      await h.enter();
      h.cart.removeLine('sent-oi-fries');
      expect(h.state.canDiscard, isTrue);
      expect(h.edit.discard(), isTrue);
      expect(h.cartState.isEditing, isFalse);
      expect(h.cartState.isEmpty, isTrue);
      expect(h.state.phase, OrderEditPhase.idle);
      expect(h.transport.ops, isEmpty);
    });
  });

  group('send', () {
    test('the journal is written strictly BEFORE the invoke, with the frozen '
        'op', () async {
      final h = _H(script: [_applied()]);
      await h.enter();
      h.details.byId['order-1'] = _edited();
      h.cart.removeLine('sent-oi-fries');
      final result = await h.edit.submit(reasonCode: 'entry_mistake');

      expect(h.log.take(2), ['persist:dispatching', 'invoke:op-1']);
      final op = h.transport.ops.single;
      expect(op['local_operation_id'], 'op-1');
      expect(op['operation_type'], 'order.edit');
      expect(op['target_entity'], 'order');
      expect(op['target_id'], 'order-1');
      expect(op['client_created_at'], endsWith('Z'));
      expect(op['payload'], {
        'order_id': 'order-1',
        'reason_code': 'entry_mistake',
        'expected': {
          'subtotal_minor': 8000,
          'tax_total_minor': 0,
          'grand_total_minor': 8000,
        },
        'changes': [
          {'op': 'remove', 'order_item_id': 'oi-fries'},
        ],
      });
      expect(result.status, OrderEditSubmitStatus.applied);
    });

    test('a refused journal write sends NOTHING and keeps the edit', () async {
      final h = _H();
      await h.enter();
      h.journal!.failWrites = true;
      h.cart.addItem(_lemonade);
      final result = await h.edit.submit();
      expect(result.status, OrderEditSubmitStatus.notSent);
      expect(result.error, 'storage');
      expect(result.notice, OrderEditNotice.retry);
      expect(h.transport.ops, isEmpty);
      expect(h.state.phase, OrderEditPhase.active);
      expect(h.state.attempt, isNull);
      expect(h.state.blockedOrderIds, isEmpty);
      expect(h.cartState.lockedByAddition, isFalse);
      expect(h.cartState.isEditing, isTrue);
    });

    test('a plan the footer blocks is never frozen', () async {
      final h = _H();
      await h.enter();
      var r = await h.edit.submit();
      expect(r.sendBlock, OrderEditSendBlock.noChanges);
      h.cart.removeLine('sent-oi-fries');
      r = await h.edit.submit();
      expect(r.status, OrderEditSubmitStatus.notSent);
      expect(r.sendBlock, OrderEditSendBlock.reasonRequired);
      r = await h.edit.submit(reasonCode: 'other', reasonText: '   ');
      expect(r.sendBlock, OrderEditSendBlock.reasonOtherRequired);
      expect(h.transport.ops, isEmpty);
      expect(h.log, isEmpty);
      expect(h.cartState.lockedByAddition, isFalse);
    });

    test('offline: nothing is frozen or sent', () async {
      final h = _H();
      await h.enter();
      h.cart.addItem(_lemonade);
      h.goOffline();
      final r = await h.edit.submit();
      expect(r.notice, OrderEditNotice.needsConnection);
      expect(h.transport.ops, isEmpty);
      expect(h.state.attempt, isNull);
    });

    test('a double tap invokes once; the cart is locked and discard refused '
        'while sending', () async {
      final h = _H(script: [_applied()]);
      await h.enter();
      h.details.byId['order-1'] = _edited(items: [_burger(), _fries()]);
      h.transport.gate = Completer<void>();
      h.cart.addItem(_lemonade);
      final a = h.edit.submit();
      final b = h.edit.submit();
      expect(identical(a, b), isTrue);
      await _settle();
      expect(h.state.phase, OrderEditPhase.sending);
      expect(h.state.dispatched, isTrue);
      expect(h.state.blockedOrderIds, {'order-1'});
      expect(h.cartState.lockedByAddition, isTrue);
      expect(h.cart.addItem(_lemonade), CartMutationResult.lockedByAddition);
      expect(h.edit.discard(), isFalse);
      h.transport.gate!.complete();
      await a;
      expect(h.transport.ops, hasLength(1));
    });
  });

  group('outcome unknown', () {
    for (final (name, handler) in <(String, _Handler)>[
      ('a dead transport', _down),
      ('an answer without our operation', _absent),
    ]) {
      test(
        '$name keeps the identity; retry re-sends it byte-identical',
        () async {
          final h = _H(script: [handler, _applied()]);
          await h.enter();
          h.cart.addItem(_lemonade);
          final first = await h.edit.submit();
          expect(first.status, OrderEditSubmitStatus.uncertain);
          expect(first.notice, OrderEditNotice.retry);
          expect(h.state.phase, OrderEditPhase.failed);
          expect(h.state.dispatched, isTrue);
          expect(h.state.blockedOrderIds, {'order-1'});
          expect(h.edit.discard(), isFalse);
          expect(h.cartState.lockedByAddition, isTrue);
          final stored = (await h.journal!.stored())['op-1']!;
          expect(stored.phase, OrderEditJournalPhase.transportUncertain);
          expect(
            h.state.retryableRecordFor('order-1')?.localOperationId,
            'op-1',
          );

          h.details.byId['order-1'] = _edited(items: [_burger(), _fries()]);
          final second = await h.edit.retry();
          final ops = h.transport.ops;
          expect(ops, hasLength(2));
          expect(ops[1]['local_operation_id'], 'op-1');
          expect(jsonEncode(ops[1]['payload']), jsonEncode(ops[0]['payload']));
          expect(ops[1]['client_created_at'], ops[0]['client_created_at']);
          expect(second.status, OrderEditSubmitStatus.applied);
          expect(second.refreshRequired, isFalse);
          expect(h.cartState.isEditing, isFalse);
          expect(await h.journal!.stored(), isEmpty);
        },
      );
    }
  });

  group('applied', () {
    test('verified by the detail: cart cleared, journal closed, edit ended; '
        'the toast facts', () async {
      final h = _H(
        script: [
          _applied(
            changes: [
              {'kind': 'modify', 'remake': true},
            ],
          ),
        ],
      );
      // The burger is READY on the KDS: a modify of both remakes 2 dishes.
      h.details.byId['order-1'] = _order(
        items: [
          _burger(status: 'ready'),
          _fries(),
        ],
      );
      await h.enter();
      final gen = h.state.generation;
      h.cart.updateLineModifiers('sent-oi-burger', [
        mod('opt-bacon', 'Bacon', price: 500),
      ]);
      h.details.byId['order-1'] = _edited(
        items: [
          _burger(status: 'ready'),
          _fries(),
        ],
      );
      final r = await h.edit.submit(
        reasonCode: 'kitchen_issue',
        billPresentedAt: DateTime.utc(2026, 10, 9, 11, 30),
      );
      final payload = h.transport.ops.single['payload'] as Map;
      expect(payload['bill_presented_at'], '2026-10-09T11:30:00.000Z');
      // 2 × (4000 + 500) + 1500.
      expect((payload['expected'] as Map)['grand_total_minor'], 10500);
      expect(r.status, OrderEditSubmitStatus.applied);
      expect(r.applied!.editNumber, 1);
      expect(r.applied!.kitchenAckRequired, isTrue);
      expect(r.applied!.newRoundId, 'round-2');
      expect(r.remakeCount, 2);
      expect(r.billPresented, isTrue);
      expect(r.refreshRequired, isFalse);
      expect(h.cartState.isEditing, isFalse);
      expect(h.cartState.isEmpty, isTrue);
      expect(h.cartState.lockedByAddition, isFalse);
      expect(await h.journal!.stored(), isEmpty);
      expect(h.state.phase, OrderEditPhase.idle);
      expect(h.state.generation, gen + 1);
      expect(h.state.blockedOrderIds, isEmpty);
    });

    test(
      'unproven: refresh required; the refresh retry NEVER dispatches',
      () async {
        final h = _H(script: [_applied()]);
        await h.enter();
        h.cart.addItem(_lemonade);
        final r = await h.edit.submit();
        expect(r.status, OrderEditSubmitStatus.applied);
        expect(r.refreshRequired, isTrue);
        expect(h.state.phase, OrderEditPhase.appliedAwaitingRefresh);
        expect(h.state.blockedOrderIds, {'order-1'});
        expect(h.cartState.lockedByAddition, isTrue);
        expect(h.edit.discard(), isFalse);
        final stored = (await h.journal!.stored())['op-1']!;
        expect(
          stored.phase,
          OrderEditJournalPhase.awaitingAuthoritativeRefresh,
        );
        expect(stored.applied!.orderEditId, 'edit-1');

        expect(await h.edit.retryRefresh(), isFalse);
        final again = await h.edit.submit();
        expect(again.refreshRequired, isTrue);
        expect(h.transport.ops, hasLength(1));

        h.details.byId['order-1'] = _edited(items: [_burger(), _fries()]);
        expect(await h.edit.retryRefresh(), isTrue);
        expect(h.transport.ops, hasLength(1));
        expect(h.cartState.isEditing, isFalse);
        expect(await h.journal!.stored(), isEmpty);
        expect(h.state.phase, OrderEditPhase.idle);
      },
    );
  });

  group('refusal policy (API §4.45.6)', () {
    OrderEditOutcome classify(_Handler h) => classifyOrderEditResponse(
      h({'local_operation_id': 'op-1'}),
      localOperationId: 'op-1',
      orderId: 'order-1',
    );

    const stay = OrderEditRefusalEffect.stay;
    const exit = OrderEditRefusalEffect.exit;
    final cases =
        <
          (
            String,
            _Handler,
            OrderEditNotice,
            OrderEditRefusalEffect,
            bool,
            bool,
          )
        >[
          (
            'line_changed',
            _refused('line_changed'),
            OrderEditNotice.rebased,
            OrderEditRefusalEffect.rebase,
            false,
            false,
          ),
          (
            'totals_mismatch',
            _refused('totals_mismatch'),
            OrderEditNotice.rebased,
            OrderEditRefusalEffect.rebase,
            false,
            false,
          ),
          (
            'reason_required',
            _refused('reason_required'),
            OrderEditNotice.reasonRequired,
            stay,
            false,
            false,
          ),
          (
            'edit_would_empty_order',
            _refused('edit_would_empty_order'),
            OrderEditNotice.allRemovedUseCancel,
            stay,
            false,
            false,
          ),
          (
            'invalid_discount',
            _refused('invalid_discount', {
              'detail': 'discount_exceeds_order_total',
            }),
            OrderEditNotice.discountExceedsOrderTotal,
            stay,
            false,
            false,
          ),
          (
            'full comp',
            _refused('permission_denied', {
              'detail': 'full_comp_permission_required',
            }),
            OrderEditNotice.fullCompDenied,
            stay,
            false,
            false,
          ),
          (
            'removal',
            _refused('permission_denied', {'detail': 'removal_not_permitted'}),
            OrderEditNotice.removalNotPermitted,
            stay,
            true,
            false,
          ),
          (
            'finished food',
            _refused('permission_denied', {
              'detail': 'finished_food_needs_manager',
            }),
            OrderEditNotice.finishedFoodNeedsManager,
            stay,
            true,
            false,
          ),
          (
            'permission_denied',
            _refused('permission_denied'),
            OrderEditNotice.notAllowed,
            exit,
            false,
            false,
          ),
          (
            'invalid_device_type',
            _refused('invalid_device_type'),
            OrderEditNotice.notAllowed,
            exit,
            false,
            false,
          ),
          (
            'revoked',
            _raised('42501', detail: 'revoked_employee'),
            OrderEditNotice.notAllowed,
            exit,
            false,
            false,
          ),
          (
            'feature_disabled',
            _refused('feature_disabled'),
            OrderEditNotice.featureDisabled,
            exit,
            true,
            false,
          ),
          (
            'order_not_editable',
            _refused('order_not_editable', {'order_status': 'completed'}),
            OrderEditNotice.notEditable,
            exit,
            false,
            false,
          ),
          (
            'order_already_settled',
            _refused('order_already_settled'),
            OrderEditNotice.alreadyPaid,
            exit,
            false,
            false,
          ),
          (
            'kitchen_mode_changed',
            _refused('kitchen_mode_changed'),
            OrderEditNotice.kitchenModeChanged,
            exit,
            false,
            false,
          ),
          (
            'tax_mode_unsupported',
            _refused('tax_mode_unsupported'),
            OrderEditNotice.taxModeUnsupported,
            exit,
            false,
            false,
          ),
          (
            'line_has_discount',
            _refused('line_has_discount'),
            OrderEditNotice.lineHasDiscount,
            OrderEditRefusalEffect.rebaseline,
            false,
            false,
          ),
          (
            'legacy_line_not_editable',
            _refused('legacy_line_not_editable'),
            OrderEditNotice.legacyLine,
            OrderEditRefusalEffect.rebaseline,
            false,
            false,
          ),
          (
            'item_unavailable',
            _refused('item_unavailable'),
            OrderEditNotice.itemUnavailable,
            stay,
            false,
            true,
          ),
          (
            'modifier_option_not_in_scope',
            _refused('modifier_option_not_in_scope'),
            OrderEditNotice.optionNotInScope,
            stay,
            false,
            true,
          ),
          (
            'modifier_prep_snapshot_stale',
            _refused('modifier_prep_snapshot_stale'),
            OrderEditNotice.prepSnapshotStale,
            stay,
            false,
            true,
          ),
          (
            'invalid_payload',
            _refused('invalid_payload'),
            OrderEditNotice.invalid,
            stay,
            false,
            false,
          ),
          (
            'no_changes',
            _refused('no_changes'),
            OrderEditNotice.invalid,
            stay,
            false,
            false,
          ),
          (
            'duplicate_line_reference',
            _refused('duplicate_line_reference'),
            OrderEditNotice.invalid,
            stay,
            false,
            false,
          ),
          (
            'expected_totals_required',
            _refused('expected_totals_required'),
            OrderEditNotice.invalid,
            stay,
            false,
            false,
          ),
          (
            'invalid_item_payload',
            _refused('invalid_item_payload'),
            OrderEditNotice.invalid,
            stay,
            false,
            false,
          ),
          (
            'too_many_changes',
            _refused('too_many_changes'),
            OrderEditNotice.tooManyChanges,
            stay,
            false,
            false,
          ),
          (
            '42501',
            _raised('42501'),
            OrderEditNotice.blockedUnacknowledged,
            exit,
            false,
            false,
          ),
          (
            '23514',
            _raised('23514'),
            OrderEditNotice.slipTooLarge,
            stay,
            false,
            false,
          ),
          (
            'another RAISE',
            _raised('P0001'),
            OrderEditNotice.invalid,
            stay,
            false,
            false,
          ),
          ('unknown', _absent, OrderEditNotice.retry, stay, false, false),
          (
            'conflict',
            _conflict,
            OrderEditNotice.conflictBlocked,
            stay,
            false,
            false,
          ),
        ];
    for (final (name, handler, notice, effect, caps, menu) in cases) {
      test(name, () {
        final policy = orderEditRefusalPolicy(classify(handler))!;
        expect(policy.notice, notice);
        expect(policy.effect, effect);
        expect(policy.invalidateCapabilities, caps);
        expect(policy.invalidateMenu, menu);
      });
    }

    test('an applied outcome is not a refusal', () {
      expect(orderEditRefusalPolicy(classify(_applied())), isNull);
    });
  });

  group('refusals in the controller', () {
    Future<_H> sendRefused(
      _Handler handler, {
      List<_Handler> then = const [],
    }) async {
      final h = _H(script: [handler, ...then]);
      await h.enter();
      h.cart.addItem(_lemonade);
      return h;
    }

    test('stay: the identity is released, the edit stays open, the next send '
        'is a NEW identity', () async {
      final h = await sendRefused(
        _refused('modifier_option_not_in_scope'),
        then: [_absent],
      );
      final menuBefore = h.menuLoads;
      final r = await h.edit.submit();
      expect(r.status, OrderEditSubmitStatus.refused);
      expect(r.notice, OrderEditNotice.optionNotInScope);
      expect(r.effect, OrderEditRefusalEffect.stay);
      expect(await h.journal!.stored(), isEmpty);
      expect(h.state.blockedOrderIds, isEmpty);
      expect(h.state.phase, OrderEditPhase.active);
      expect(h.state.dispatched, isFalse);
      expect(h.cartState.lockedByAddition, isFalse);
      expect(h.cartState.isEditing, isTrue);
      // The menu was staled; the next read re-fetches it.
      await h.c.read(posMenuProvider.future);
      expect(h.menuLoads, menuBefore + 1);
      await h.edit.submit();
      expect(h.transport.ops.map((o) => o['local_operation_id']), [
        'op-1',
        'op-2',
      ]);
    });

    test('item_unavailable names the refused items', () async {
      final h = await sendRefused(
        _refused('item_unavailable', {
          'items': [
            {'menu_item_id': 'mi-lemonade', 'name': 'Lemonade'},
          ],
        }),
      );
      final r = await h.edit.submit();
      expect(r.unavailableItems, ['Lemonade']);
    });

    test('removal_not_permitted stales the capability probe', () async {
      final h = await sendRefused(
        _refused('permission_denied', {'detail': 'removal_not_permitted'}),
      );
      await h.c.read(staffCapabilitiesProvider.future);
      final before = h.capsLoads;
      final r = await h.edit.submit();
      expect(r.notice, OrderEditNotice.removalNotPermitted);
      await h.c.read(staffCapabilitiesProvider.future);
      expect(h.capsLoads, before + 1);
      expect(h.cartState.isEditing, isTrue);
    });

    for (final (name, handler, notice) in <(String, _Handler, OrderEditNotice)>[
      (
        'order_already_settled',
        _refused('order_already_settled'),
        OrderEditNotice.alreadyPaid,
      ),
      ('42501', _raised('42501'), OrderEditNotice.blockedUnacknowledged),
    ]) {
      test('exit on $name: the edit ends and the cart empties', () async {
        final h = await sendRefused(handler);
        final gen = h.state.generation;
        final r = await h.edit.submit();
        expect(r.notice, notice);
        expect(r.effect, OrderEditRefusalEffect.exit);
        expect(h.cartState.isEditing, isFalse);
        expect(h.cartState.isEmpty, isTrue);
        expect(h.state.phase, OrderEditPhase.idle);
        expect(h.state.generation, gen + 1);
        expect(await h.journal!.stored(), isEmpty);
      });
    }

    test('23514 keeps the edit open', () async {
      final h = await sendRefused(_raised('23514'));
      final r = await h.edit.submit();
      expect(r.notice, OrderEditNotice.slipTooLarge);
      expect(h.cartState.isEditing, isTrue);
      expect(h.state.phase, OrderEditPhase.active);
    });

    test('conflict: blocked, never re-sent, never discarded', () async {
      final h = await sendRefused(_conflict);
      final r = await h.edit.submit();
      expect(r.status, OrderEditSubmitStatus.conflict);
      expect(r.notice, OrderEditNotice.conflictBlocked);
      expect(
        (await h.journal!.stored())['op-1']!.phase,
        OrderEditJournalPhase.conflict,
      );
      expect(h.state.phase, OrderEditPhase.failed);
      expect(h.state.blockedOrderIds, {'order-1'});
      expect(h.state.conflictingOrderIds, {'order-1'});
      expect(h.edit.discard(), isFalse);
      final again = await h.edit.submit();
      expect(again.status, OrderEditSubmitStatus.conflict);
      expect(
        (await h.edit.retryOrder('order-1')).status,
        OrderEditSubmitStatus.conflict,
      );
      expect(h.transport.ops, hasLength(1));
    });
  });

  group('rebase (design §7.1 point 9, D9)', () {
    test('line_changed: stale intents are dropped and named, live ones kept, '
        'adds kept; the resend is a NEW identity', () async {
      final h = _H(
        script: [
          _refused('line_changed', {
            'stale_ids': ['oi-fries'],
          }),
          _absent,
        ],
      );
      await h.enter();
      h.cart.decreaseQuantity('sent-oi-burger'); // Burger 2 → 1
      h.cart.updateLineNote('sent-oi-fries', 'extra salt'); // Fries note
      h.cart.addItem(_lemonade);
      // Another till replaced the fries line meanwhile.
      h.details.byId['order-1'] = _order(
        items: [
          _burger(),
          _fries(id: 'oi-fries-2', notes: 'no salt'),
        ],
      );
      final r = await h.edit.submit(reasonCode: 'entry_mistake');
      expect(r.status, OrderEditSubmitStatus.refused);
      expect(r.notice, OrderEditNotice.rebased);
      expect(r.effect, OrderEditRefusalEffect.rebase);
      expect(r.droppedItems, ['Fries']);
      expect(h.state.phase, OrderEditPhase.active);
      expect(h.state.baseline!.lineFor('oi-fries-2'), isNotNull);
      final lines = h.cartState.lines;
      expect(lines.map((l) => l.lineId), [
        'sent-oi-burger',
        'sent-oi-fries-2',
        lines.last.lineId,
      ]);
      expect(lines[0].quantity, 1);
      expect(lines[1].note, 'no salt');
      expect(lines.last.editAdded, isTrue);
      expect(lines.last.menuItemId, 'mi-lemonade');

      await h.edit.submit(reasonCode: 'entry_mistake');
      final resend = h.transport.ops[1];
      expect(resend['local_operation_id'], 'op-2');
      final changes = (resend['payload'] as Map)['changes'] as List;
      expect(changes.map((c) => (c as Map)['op']), ['set_quantity', 'add']);
    });

    test('totals_mismatch: tax re-read and ONE automatic rebase; a second in '
        'a row stops', () async {
      final h = _H(
        script: [
          _refused('totals_mismatch'),
          _refused('totals_mismatch'),
          _absent,
        ],
      );
      await h.enter();
      h.cart.addItem(_lemonade);
      final taxBefore = h.tax.loads;
      final fetchesBefore = h.details.fetches;
      final first = await h.edit.submit();
      expect(first.notice, OrderEditNotice.rebased);
      expect(h.tax.loads, greaterThan(taxBefore));
      expect(h.details.fetches, fetchesBefore + 1);
      expect(h.state.consecutiveTotalsMismatches, 1);

      final fetchesAfterRebase = h.details.fetches;
      final second = await h.edit.submit();
      expect(second.status, OrderEditSubmitStatus.refused);
      expect(second.notice, OrderEditNotice.invalid);
      expect(second.effect, OrderEditRefusalEffect.stay);
      expect(h.details.fetches, fetchesAfterRebase);
      expect(h.state.consecutiveTotalsMismatches, 2);
      expect(h.state.phase, OrderEditPhase.active);
      expect(h.cartState.isEditing, isTrue);
      expect(h.transport.ops.map((o) => o['local_operation_id']), [
        'op-1',
        'op-2',
      ]);
    });

    test('line_has_discount re-baselines: the now remove-only line drops its '
        'quantity intent', () async {
      final h = _H(script: [_refused('line_has_discount')]);
      await h.enter();
      h.cart.decreaseQuantity('sent-oi-burger');
      h.details.byId['order-1'] = _order(
        items: [_burger(lineDiscount: 500), _fries()],
      );
      final r = await h.edit.submit(reasonCode: 'entry_mistake');
      expect(r.notice, OrderEditNotice.lineHasDiscount);
      expect(r.effect, OrderEditRefusalEffect.rebaseline);
      expect(r.droppedItems, ['Burger']);
      final burger = h.cartState.lines.first;
      expect(burger.quantity, 2);
      expect(burger.editSource!.removeOnly, isTrue);
    });

    test('a rebase onto an order that is now paid ends the edit', () async {
      final h = _H(script: [_refused('line_changed')]);
      await h.enter();
      h.cart.addItem(_lemonade);
      h.details.byId['order-1'] = _order(paid: true);
      final r = await h.edit.submit();
      expect(r.notice, OrderEditNotice.alreadyPaid);
      expect(r.effect, OrderEditRefusalEffect.exit);
      expect(h.cartState.isEditing, isFalse);
      expect(h.state.phase, OrderEditPhase.idle);
    });
  });

  group('restart', () {
    test('an uncertain edit blocks its order after a restart and the retry '
        'replays it VERBATIM', () async {
      final journal = _Journal();
      final before = _H(script: [_down], journal: journal);
      await before.enter();
      before.cart.addItem(_lemonade);
      expect(
        (await before.edit.submit()).status,
        OrderEditSubmitStatus.uncertain,
      );
      final sent = before.transport.ops.single;

      final after = _H(script: [_applied()], journal: journal);
      expect(after.state.phase, OrderEditPhase.hydrating);
      await after.boot();
      expect(after.state.blockedOrderIds, {'order-1'});
      expect(after.cartState.isEmpty, isTrue);
      expect(after.cartState.isEditing, isFalse);
      expect(
        await after.edit.enterForOrder('order-1'),
        OrderEditEntryResult.pendingAttempt,
      );
      expect(after.state.retryableRecordFor('order-1'), isNotNull);

      after.details.byId['order-1'] = _edited(items: [_burger(), _fries()]);
      final r = await after.edit.retryOrder('order-1');
      final replay = after.transport.ops.single;
      expect(replay['local_operation_id'], sent['local_operation_id']);
      expect(jsonEncode(replay['payload']), jsonEncode(sent['payload']));
      expect(replay['client_created_at'], sent['client_created_at']);
      expect(r.status, OrderEditSubmitStatus.applied);
      expect(r.refreshRequired, isFalse);
      expect(after.state.blockedOrderIds, isEmpty);
      expect(await journal.stored(), isEmpty);
    });

    test('a replay refused after a restart closes the record', () async {
      final journal = _Journal();
      final before = _H(script: [_down], journal: journal);
      await before.enter();
      before.cart.addItem(_lemonade);
      await before.edit.submit();

      final after = _H(
        script: [_refused('order_already_settled')],
        journal: journal,
      );
      await after.boot();
      final r = await after.edit.retryOrder('order-1');
      expect(r.status, OrderEditSubmitStatus.refused);
      expect(r.notice, OrderEditNotice.alreadyPaid);
      expect(after.state.blockedOrderIds, isEmpty);
      expect(await journal.stored(), isEmpty);
    });

    test(
      'an applied record is reconciled on restore without dispatching',
      () async {
        final journal = _Journal();
        final before = _H(script: [_applied()], journal: journal);
        await before.enter();
        before.cart.addItem(_lemonade);
        final r = await before.edit.submit();
        expect(r.refreshRequired, isTrue);

        final after = _H(journal: journal);
        after.details.byId['order-1'] = _edited(items: [_burger(), _fries()]);
        await after.boot();
        await _settle();
        expect(after.transport.ops, isEmpty);
        expect(await journal.stored(), isEmpty);
        expect(after.state.blockedOrderIds, isEmpty);
      },
    );

    test(
      'two live records on one order are a conflict: nothing is replayed',
      () async {
        final journal = _Journal();
        final first = _H(script: [_down], journal: journal);
        await first.enter();
        first.cart.addItem(_lemonade);
        await first.edit.submit();
        final record = (await journal.stored())['op-1']!;
        await journal.inner.persist('dev-1', {
          'op-1': record,
          'op-9': OrderEditJournalRecord(
            localOperationId: 'op-9',
            orderId: 'order-1',
            orderCode: '#A1B2C3',
            clientCreatedAt: DateTime.utc(2026, 10, 9, 12),
            generation: 4,
            payload: record.payload,
            summary: record.summary,
          ),
        });

        final after = _H(journal: journal);
        await after.boot();
        expect(after.state.conflictingOrderIds, {'order-1'});
        expect(after.state.retryableRecordFor('order-1'), isNull);
        final r = await after.edit.retryOrder('order-1');
        expect(r.status, OrderEditSubmitStatus.conflict);
        expect(after.transport.ops, isEmpty);
      },
    );

    test('an unreadable journal keeps the gate SHUT', () async {
      final journal = _Journal()..failLoads = true;
      final h = _H(journal: journal);
      await h.boot();
      expect(h.state.phase, OrderEditPhase.hydrationFailed);
      expect(h.state.startupBlocked, isTrue);
      expect(
        await h.edit.enterForOrder('order-1'),
        OrderEditEntryResult.hydrating,
      );
      expect((await h.edit.submit()).notice, OrderEditNotice.hydrating);
    });
  });

  group('worker change (D12)', () {
    test('discards an UNSENT edit', () async {
      final h = _H();
      h.c.read(posSignedInEmployeeProfileIdProvider.notifier).set('emp-a');
      await h.enter();
      h.cart.removeLine('sent-oi-fries');
      h.c.read(posSignedInEmployeeProfileIdProvider.notifier).set('emp-b');
      expect(h.state.phase, OrderEditPhase.idle);
      expect(h.cartState.isEditing, isFalse);
      expect(h.cartState.isEmpty, isTrue);
    });

    test('keeps a DISPATCHED one, which any operator may resolve', () async {
      final h = _H(script: [_down]);
      h.c.read(posSignedInEmployeeProfileIdProvider.notifier).set('emp-a');
      await h.enter();
      h.cart.addItem(_lemonade);
      await h.edit.submit();
      expect((await h.journal!.stored())['op-1']!.employeeProfileId, 'emp-a');
      h.c.read(posSignedInEmployeeProfileIdProvider.notifier).set('emp-b');
      expect(h.state.phase, OrderEditPhase.failed);
      expect(h.cartState.isEditing, isTrue);
      expect(h.cartState.lockedByAddition, isTrue);
    });
  });

  group('an edit and an addition never share the cart', () {
    test('Add items is refused while an edit is open, while the edit journal '
        'is unread, and for an order with an unresolved edit', () async {
      final h = _H();
      expect(
        await h.addition.enterForOrder('order-1'),
        AdditionEntryResult.blockedHydrating,
      );
      await h.enter();
      expect(
        await h.addition.enterForOrder('order-1'),
        AdditionEntryResult.blockedPendingAttempt,
      );

      final journal = _Journal();
      final before = _H(script: [_down], journal: journal);
      await before.enter();
      before.cart.addItem(_lemonade);
      await before.edit.submit();
      final after = _H(journal: journal);
      await after.boot();
      expect(
        await after.addition.enterForOrder('order-1'),
        AdditionEntryResult.blockedPendingAttempt,
      );
    });

    test('Edit is refused while an addition is open', () async {
      final h = _H();
      await h.boot();
      h.details.byId['order-2'] = _order(orderId: 'order-2');
      expect(
        await h.addition.enterForOrder('order-2'),
        AdditionEntryResult.entered,
      );
      expect(
        await h.edit.enterForOrder('order-1'),
        OrderEditEntryResult.additionActive,
      );
      expect(h.details.fetches, 1);
    });

    test(
      'the edit cart cannot be parked or replaced by a parked cart',
      () async {
        final h = _H();
        await h.enter();
        final parked = h.c.read(parkedCartsControllerProvider.notifier);
        expect(parked.canPark, isFalse);
        expect(await parked.park(), ParkResult.blockedByAddition);
        expect(h.cartState.isEditing, isTrue);
      },
    );
  });

  group('the live plan', () {
    test('follows the edit cart with the current tax', () async {
      final h = _H();
      h.tax.tax = const BranchTax(enabled: true, rateBp: 1700);
      await h.enter();
      expect(h.c.read(orderEditPlanProvider)!.noChanges, isTrue);
      h.cart.addItem(_lemonade);
      final plan = h.c.read(orderEditPlanProvider)!;
      // 9500 + 900 = 10400; 17% → 1768; 10400 + 1768.
      expect(plan.subtotalMinor, 10400);
      expect(plan.taxMinor, 1768);
      expect(plan.grandMinor, 12168);
      expect(plan.beforeGrandMinor, 9500);
      h.edit.discard();
      expect(h.c.read(orderEditPlanProvider), isNull);
    });
  });
}
