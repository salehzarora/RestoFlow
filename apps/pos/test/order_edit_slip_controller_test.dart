@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceSessionCredential, InMemoryDeviceSessionSecretStore;
import 'package:restoflow_core/restoflow_core.dart' show SecretValue;
import 'package:restoflow_data_local/kitchen_dispatch_document.dart'
    show KitchenDispatchDocument;
import 'package:restoflow_data_local/restoflow_data_local.dart'
    show
        AesGcmKitchenSpoolCipher,
        DriftKitchenSpoolStore,
        KitchenSpoolAad,
        KitchenSpoolCipher,
        KitchenSpoolDatabase,
        KitchenSpoolDatabaseFactory,
        NetworkKitchenDestination;
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show PulledKitchenDispatch, SupabaseKitchenDispatchAckRepository;
import 'package:restoflow_feature_kitchen/kitchen_print.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsItemView;
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_edit_baseline.dart';
import 'package:restoflow_pos/src/data/order_edit_diff.dart'
    show OrderEditAttemptSummary;
import 'package:restoflow_pos/src/data/order_edit_journal_store.dart';
import 'package:restoflow_pos/src/data/order_edit_read_model.dart';
import 'package:restoflow_pos/src/data/order_edit_response.dart';
import 'package:restoflow_pos/src/data/order_edit_slip.dart';
import 'package:restoflow_pos/src/data/order_edit_slip_store.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/round_print_claim_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosPersistenceException;
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/spool/kitchen_destination_resolver.dart'
    show ResolvedKitchenDestination;
import 'package:restoflow_pos/src/spool/kitchen_dispatch_import_coordinator.dart';
import 'package:restoflow_pos/src/state/order_edit_controller.dart';
import 'package:restoflow_pos/src/state/order_edit_slip_controller.dart';
import 'package:restoflow_pos/src/state/pos_kitchen_dispatch_ack.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';

import 'support/pos_package_root.dart';

/// ORDER-EDIT-001F — the AWAITED, EXACTLY-ONCE paper change slip
/// ([OrderEditSlipController]), driven with REAL captured paper edits
/// (`test/fixtures/order_edit_slip`), a recording claim store, a recording
/// slip store, a scripted printer seam and the REAL typed acknowledgement
/// client over a scripted transport:
///
///  * the record is persisted, then the spool mirror and the guard key are
///    claimed, strictly BEFORE the send; a refused claim sends nothing;
///  * duplicate calls print ONCE; the printed slip is the server's slip;
///  * every outcome maps to its acknowledgement (safe codes), and no answer
///    of the acknowledgement changes anything;
///  * no proven detail -> UNBUILT and handed to the spool; a crash mid-print
///    -> never automatic; a newer edit or a void -> nothing printed;
///  * Print again: blocked, fetch failure, void, newer edit (local unsent /
///    local sent / foreign), an unbuilt record built on demand, and the
///    STORED document re-sent through `runPreclaimed`.

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');
final _now = DateTime.utc(2026, 10, 9, 6);

Map<String, Object?> _map(Object? raw) => (raw as Map).cast<String, Object?>();

/// One captured paper edit.
class _Edit {
  _Edit(String name) : raw = _load(name);

  static Map<String, Object?> _load(String name) {
    final file = File(
      p.join(
        locatePosPackageRoot().path,
        'test',
        'fixtures',
        'order_edit_slip',
        '$name.json',
      ),
    );
    return _map(jsonDecode(file.readAsStringSync()));
  }

  final Map<String, Object?> raw;

  Map<String, Object?> get payload => _map(raw['payload']);
  PosOrderDetail get before => PosOrderDetail.fromJson(raw['before'])!;
  PosOrderDetail get after => PosOrderDetail.fromJson(raw['after'])!;
  String get orderId => payload['order_id']! as String;
  String get staff => raw['staff_display_name']! as String;

  OrderEditApplied applied({bool withDispatch = true}) {
    final envelope = _map(jsonDecode(jsonEncode(raw['envelope'])));
    if (!withDispatch) {
      _map((envelope['results'] as List).single).remove('kitchen_dispatch');
    }
    return classifyOrderEditResponse(
      envelope,
      localOperationId: raw['local_operation_id']! as String,
      orderId: orderId,
    ).applied!;
  }

  String get editId => applied().orderEditId;
  String get dispatchId => applied().kitchenDispatch!.id;
  String get guardKey =>
      posOrderEditKitchenPrintGuardKey(orderId: orderId, orderEditId: editId);
  String get mirrorKey => posOrderEditDispatchClaimKey(dispatchId);

  OrderEditAttempt attempt({bool withWas = true}) => OrderEditAttempt(
    localOperationId: raw['local_operation_id']! as String,
    orderId: orderId,
    orderCode: before.orderCode,
    generation: 1,
    payload: payload,
    summary: const OrderEditAttemptSummary(),
    clientCreatedAt: DateTime.utc(2026, 10, 9, 5, 31),
    slipWas: withWas
        ? orderEditSlipWasLines(
            OrderEditBaseline.fromDetail(before).baseline!,
            payload,
          )
        : null,
  );

  /// The SERVER's slip, as the spool decodes the stored payload.
  OrderChangeSlipView get server => orderChangeSlipViewFromKitchenDispatch(
    KitchenDispatchDocument.fromJson(_map(raw['dispatch'])),
  );
}

Future<List<int>> _bytes(OrderChangeSlipView slip) =>
    renderOrderChangeSlipBytes(
      slip: slip,
      labels: kitchenTicketPrintLabelsForLanguageCode('en'),
      changeLabels: kitchenChangeSlipLabelsForLanguageCode('en'),
      restaurantName: 'Slip Parity',
    );

class _Claims implements PosRoundPrintClaimStore {
  _Claims(this.log);
  final List<String> log;
  final Map<String, PosRoundPrintClaimState> claims = {};
  final Set<String> refuse = {};

  @override
  PosRoundPrintClaimState? claimOf(String key) => claims[key];

  @override
  Future<void> record(String key, PosRoundPrintClaimState state) async {
    if (refuse.contains(key)) {
      log.add('refused:$key=${state.name}');
      throw const PosPersistenceException('the claim was refused');
    }
    log.add('claim:$key=${state.name}');
    claims[key] = state;
  }
}

class _Store implements OrderEditSlipStore {
  _Store(this.log);
  final List<String> log;
  final InMemoryOrderEditSlipStore inner = InMemoryOrderEditSlipStore();
  bool failWrites = false;

  @override
  Future<Map<String, OrderEditSlipRecord>> load(String scopeKey) =>
      inner.load(scopeKey);

  @override
  Future<void> persist(
    String scopeKey,
    Map<String, OrderEditSlipRecord> records,
  ) async {
    log.add('persist:${(records.keys.toList()..sort()).join(',')}');
    if (failWrites) {
      throw const PosPersistenceException('the slip store refused the write');
    }
    await inner.persist(scopeKey, records);
  }

  @override
  Future<List<OrderEditSlipEvidence>> loadEvidence(
    String scopeKey, {
    required DateTime now,
  }) => inner.loadEvidence(scopeKey, now: now);

  @override
  Future<void> appendEvidence(
    String scopeKey,
    OrderEditSlipEvidence entry, {
    required DateTime now,
  }) async {
    log.add('evidence:${entry.orderId}');
    await inner.appendEvidence(scopeKey, entry, now: now);
  }

  Future<Map<String, OrderEditSlipRecord>> stored() => inner.load('dev-1');
}

class _Printer {
  _Printer(this.log);
  final List<String> log;
  final List<OrderChangeSlipView> slips = [];
  List<PosKitchenPrintOutcome> script = const [PosKitchenPrintOutcome.printed];
  Completer<void>? gate;

  Future<PosKitchenPrintOutcome> call({
    required PosProviderReader read,
    required OrderChangeSlipView slip,
    required KitchenTicketPrintLabels labels,
    required KitchenChangeSlipLabels changeLabels,
  }) async {
    slips.add(slip);
    log.add('print:${slip.orderCode}#${slip.editNumber}');
    if (gate case final g?) await g.future;
    return script.length >= slips.length
        ? script[slips.length - 1]
        : script.last;
  }
}

class _AckTransport implements SyncRpcTransport {
  _AckTransport(this.log);
  final List<String> log;
  final List<Map<String, dynamic>> calls = [];
  Object? Function()? answer;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add(params);
    final code = params['p_error_code'];
    log.add('ack:${params['p_client_status']}${code == null ? '' : ':$code'}');
    final a = answer;
    if (a != null) return a();
    return {'ok': true, 'idempotency_replay': false, 'completed': true};
  }
}

class _Details implements OrderDetailRepository {
  final Map<String, PosOrderDetail> byId = {};
  Object? error;
  int fetches = 0;

  @override
  Future<PosOrderDetail> fetch(String orderId) async {
    fetches++;
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

class _Recent extends PosRecentOrdersController {
  @override
  List<PosRecentOrder> build() => const <PosRecentOrder>[];
  void setOrders(List<PosRecentOrder> orders) => state = orders;
}

class _Journal implements OrderEditJournalStore {
  final InMemoryOrderEditJournalStore inner = InMemoryOrderEditJournalStore();

  @override
  Future<Map<String, OrderEditJournalRecord>> load(String scopeKey) =>
      inner.load(scopeKey);

  @override
  Future<void> persist(
    String scopeKey,
    Map<String, OrderEditJournalRecord> records,
  ) => inner.persist(scopeKey, records);
}

/// The REAL spool cipher, whose `encrypt` waits on [gate]: the import's
/// window between the consult and the hand-over, held open.
class _GatedCipher implements KitchenSpoolCipher {
  final AesGcmKitchenSpoolCipher inner = AesGcmKitchenSpoolCipher();
  final Completer<void> entered = Completer<void>();
  final Completer<void> gate = Completer<void>();
  Object? failWith;

  @override
  int get encryptionVersion => inner.encryptionVersion;

  @override
  Future<Uint8List> encrypt({
    required Uint8List plaintext,
    required KitchenSpoolAad aad,
    required SecretValue key,
  }) async {
    if (!entered.isCompleted) entered.complete();
    await gate.future;
    if (failWith case final e?) throw e;
    return inner.encrypt(plaintext: plaintext, aad: aad, key: key);
  }

  @override
  Future<Uint8List> decrypt({
    required Uint8List envelope,
    required KitchenSpoolAad aad,
    required SecretValue key,
  }) => inner.decrypt(envelope: envelope, aad: aad, key: key);
}

Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A detail whose JSON was changed by [edit] (a newer edit, a void).
PosOrderDetail _detailWith(
  Map<String, Object?> raw,
  void Function(Map<String, Object?> copy, Map<String, Object?> order) edit,
) {
  final copy = _map(jsonDecode(jsonEncode(raw)));
  edit(copy, _map(copy['order']));
  return PosOrderDetail.fromJson(copy)!;
}

PosOrderDetail _voided(_Edit e) =>
    _detailWith(_map(e.raw['after']), (_, order) => order['status'] = 'voided');

/// [e]'s post-apply detail after ANOTHER till's newer edit (`edit_count` 2).
PosOrderDetail _newer(_Edit e) =>
    _detailWith(_map(e.raw['after']), (copy, order) {
      final edits = (copy['edits']! as List).toList();
      edits.add({
        ..._map(edits.single),
        'order_edit_id': 'edit-from-another-till',
        'edit_number': 2,
      });
      copy['edits'] = edits;
      order['edit_count'] = 2;
    });

class _H {
  _H({_Claims? claims, _Store? store, _Journal? journal, this.withAck = true}) {
    this.claims = claims ?? _Claims(log);
    this.store = store ?? _Store(log);
    printer = _Printer(log);
    ackTransport = _AckTransport(log);
    final secrets = InMemoryDeviceSessionSecretStore();
    unawaited(
      secrets.write(
        const DeviceSessionCredential(deviceId: 'dev-1', sessionToken: 'tok'),
      ),
    );
    ack = SupabaseKitchenDispatchAckRepository(
      transport: ackTransport,
      secretStore: secrets,
    );
    c = ProviderContainer(
      overrides: [
        posSyncSessionProvider.overrideWithValue(_session),
        orderEditSlipStoreProvider.overrideWithValue(this.store),
        posRoundPrintClaimStoreProvider.overrideWithValue(this.claims),
        posOrderEditSlipPrintProvider.overrideWithValue(printer.call),
        if (withAck) posKitchenDispatchAckProvider.overrideWithValue(ack),
        orderDetailRepositoryProvider.overrideWithValue(details),
        orderEditSlipClockProvider.overrideWithValue(() => _now),
        posRecentOrdersControllerProvider.overrideWith(() => recent),
        if (journal != null)
          orderEditJournalStoreProvider.overrideWithValue(journal),
      ],
    );
    addTearDown(c.dispose);
    // The worker who froze the attempts below is the signed-in one.
    c.read(posSignedInStaffNameProvider.notifier).set('Dana Cashier');
  }

  final bool withAck;
  final List<String> log = [];
  late final _Claims claims;
  late final _Store store;
  late final _Printer printer;
  late final _AckTransport ackTransport;
  late final SupabaseKitchenDispatchAckRepository ack;
  final _Details details = _Details();
  final _Recent recent = _Recent();
  late final ProviderContainer c;

  OrderEditSlipController get slips =>
      c.read(orderEditSlipControllerProvider.notifier);
  OrderEditSlipsState get state => c.read(orderEditSlipControllerProvider);
  List<OrderEditSlipRecord> get pending =>
      c.read(orderEditPendingSlipsProvider);

  Future<void> boot() async {
    c.read(orderEditSlipControllerProvider);
    await _settle();
  }

  /// The edit flow's two calls, as 001E makes them.
  Future<OrderEditSlipOutcome> apply(
    _Edit e, {
    PosOrderDetail? fresh,
    bool proven = true,
    bool withDispatch = true,
    bool withWas = true,
  }) async {
    final applied = e.applied(withDispatch: withDispatch);
    await slips.recordApplied(
      attempt: e.attempt(withWas: withWas),
      applied: applied,
      fresh: proven ? (fresh ?? e.after) : null,
    );
    return slips.printRecorded(applied.orderEditId);
  }
}

void main() {
  final a1 = _Edit('a_every_op');
  final a2 = _Edit('a_second_edit');
  final b1 = _Edit('b_legacy_ranks_add');

  group('the automatic path', () {
    test('records, then claims the mirror and the guard key, BEFORE the one '
        'send; settles sent, removes the record, keeps evidence and '
        'acknowledges transport_accepted', () async {
      final h = _H();
      await h.boot();
      final outcome = await h.apply(a1);
      await _settle();

      expect(outcome, OrderEditSlipOutcome.printed);
      expect(h.log, [
        'persist:${a1.editId}',
        'claim:${a1.mirrorKey}=claimed',
        'claim:${a1.guardKey}=claimed',
        'print:#00A001#1',
        'claim:${a1.guardKey}=sent',
        'claim:${a1.mirrorKey}=sent',
        'persist:',
        'evidence:${a1.orderId}',
        'ack:transport_accepted',
      ]);
      expect(h.ackTransport.calls.single['p_dispatch_id'], a1.dispatchId);
      expect(await h.store.stored(), isEmpty);
      expect(h.state.records, isEmpty);
      expect(h.state.inFlight, isEmpty);
      final evidence = await h.slips.evidence();
      expect(evidence.single.orderId, a1.orderId);
      expect(evidence.single.dispatchId, a1.dispatchId);
      expect(evidence.single.editCreatedAt, a1.after.edits!.single.createdAt);
    });

    test('the printed slip IS the server slip (the hand-built parity, with '
        "the signed-in worker's first name)", () async {
      for (final e in [a1, b1]) {
        final h = _H();
        h.c.read(posSignedInStaffNameProvider.notifier).set(e.staff);
        await h.boot();
        expect(await h.apply(e), OrderEditSlipOutcome.printed);
        final printed = h.printer.slips.single;
        expect(printed.staffFirstName, e.staff.split(' ').first);
        expect(await _bytes(printed), await _bytes(e.server));
      }
    });

    test('duplicate calls print exactly ONCE and every caller hears '
        '"printed"', () async {
      final h = _H();
      await h.boot();
      h.printer.gate = Completer<void>();
      final applied = a1.applied();
      final attempt = a1.attempt();
      await Future.wait([
        h.slips.recordApplied(
          attempt: attempt,
          applied: applied,
          fresh: a1.after,
        ),
        h.slips.recordApplied(
          attempt: attempt,
          applied: applied,
          fresh: a1.after,
        ),
      ]);
      final first = h.slips.printRecorded(a1.editId);
      final second = h.slips.printRecorded(a1.editId);
      await _settle();
      expect(h.state.inFlight, {a1.editId});
      expect(h.slips.isDispatchInFlight(a1.dispatchId), isTrue);
      h.printer.gate!.complete();
      expect(await first, OrderEditSlipOutcome.printed);
      expect(await second, OrderEditSlipOutcome.printed);
      // A later repeat (a reconcile that ran twice) still sends nothing.
      await h.slips.recordApplied(
        attempt: attempt,
        applied: applied,
        fresh: a1.after,
      );
      expect(
        await h.slips.printRecorded(a1.editId),
        OrderEditSlipOutcome.printed,
      );
      expect(h.printer.slips, hasLength(1));
      expect(h.slips.isDispatchInFlight(a1.dispatchId), isFalse);
    });

    test('in flight from the record to the settle (D11): the spool consult '
        'is told to skip it, and the banner never flashes', () async {
      final h = _H();
      await h.boot();
      h.printer.gate = Completer<void>();
      await h.slips.recordApplied(
        attempt: a1.attempt(),
        applied: a1.applied(),
        fresh: a1.after,
      );
      // Between the record and the print (the journal closes meanwhile).
      expect(h.slips.isDispatchInFlight(a1.dispatchId), isTrue);
      expect(h.pending, isEmpty);
      final run = h.slips.printRecorded(a1.editId);
      await _settle();
      expect(h.slips.isDispatchInFlight(a1.dispatchId), isTrue);
      expect(h.pending, isEmpty);
      h.printer.gate!.complete();
      await run;
      expect(h.slips.isDispatchInFlight(a1.dispatchId), isFalse);
    });

    test('a refused GUARD claim sends nothing: the record stays failed, the '
        'mirror reads failed and the dispatch is reported', () async {
      final h = _H();
      h.claims.refuse.add(a1.guardKey);
      await h.boot();
      expect(await h.apply(a1), OrderEditSlipOutcome.notPrinted);
      await _settle();
      expect(h.printer.slips, isEmpty);
      expect(h.claims.claims[a1.mirrorKey], PosRoundPrintClaimState.failed);
      final record = (await h.store.stored())[a1.editId]!;
      expect(record.state, OrderEditSlipState.failed);
      expect(record.attempts, 1);
      expect(record.isBuilt, isTrue);
      expect(h.log.last, 'ack:failed_retryable:pos_slip_send_failed');
      expect(h.pending.single.orderEditId, a1.editId);
    });

    test('a refused MIRROR claim withholds the automatic print (the spool may '
        'import the dispatch); nothing is acknowledged', () async {
      final h = _H();
      h.claims.refuse.add(a1.mirrorKey);
      await h.boot();
      expect(await h.apply(a1), OrderEditSlipOutcome.notPrinted);
      await _settle();
      expect(h.printer.slips, isEmpty);
      expect(h.ackTransport.calls, isEmpty);
      expect(h.claims.claims[a1.guardKey], isNull);
      expect((await h.store.stored())[a1.editId]!.isBuilt, isTrue);
      expect(h.pending.single.orderEditId, a1.editId);
    });

    for (final (outcome, code) in [
      (PosKitchenPrintOutcome.noPrinterConfigured, 'pos_slip_no_printer'),
      (PosKitchenPrintOutcome.unavailable, 'pos_slip_unavailable'),
      (PosKitchenPrintOutcome.failed, 'pos_slip_send_failed'),
    ]) {
      test('${outcome.name}: failed_retryable "$code", the mirror and the '
          'record read failed, the banner shows (D10)', () async {
        final h = _H();
        h.printer.script = [outcome];
        await h.boot();
        expect(await h.apply(a1), OrderEditSlipOutcome.notPrinted);
        await _settle();
        expect(
          h.ackTransport.calls.single['p_client_status'],
          'failed_retryable',
        );
        expect(h.ackTransport.calls.single['p_error_code'], code);
        expect(RegExp(r'^[a-z0-9_.\-]{1,64}$').hasMatch(code), isTrue);
        expect(h.claims.claims[a1.guardKey], PosRoundPrintClaimState.failed);
        expect(h.claims.claims[a1.mirrorKey], PosRoundPrintClaimState.failed);
        expect(
          (await h.store.stored())[a1.editId]!.state,
          OrderEditSlipState.failed,
        );
        expect(h.pending.single.orderEditId, a1.editId);
        // A failed record is never re-sent AUTOMATICALLY.
        expect(
          await h.slips.printRecorded(a1.editId),
          OrderEditSlipOutcome.notPrinted,
        );
        expect(h.printer.slips, hasLength(1));
      });
    }

    for (final (name, answer) in <(String, Object? Function())>[
      ('not_claim_owner', () => {'ok': false, 'error': 'not_claim_owner'}),
      (
        'ambiguous_print_hold',
        () => {'ok': false, 'error': 'ambiguous_print_hold'},
      ),
      ('conflict', () => {'ok': false, 'error': 'conflict'}),
      (
        'a dead transport',
        () => throw const SyncTransportException(
          SyncTransportErrorKind.transient,
          code: 'offline',
        ),
      ),
    ]) {
      test('the acknowledgement answer ($name) changes nothing', () async {
        final h = _H();
        h.ackTransport.answer = answer;
        await h.boot();
        expect(await h.apply(a1), OrderEditSlipOutcome.printed);
        await _settle();
        expect(h.ackTransport.calls, hasLength(1));
        expect(await h.store.stored(), isEmpty);
        expect(h.claims.claims[a1.mirrorKey], PosRoundPrintClaimState.sent);
      });
    }

    test('a paper envelope with no dispatch prints with no mirror and no '
        'acknowledgement', () async {
      final h = _H();
      await h.boot();
      expect(
        await h.apply(a1, withDispatch: false),
        OrderEditSlipOutcome.printed,
      );
      await _settle();
      expect(h.printer.slips, hasLength(1));
      expect(h.ackTransport.calls, isEmpty);
      expect(h.claims.claims.keys, [a1.guardKey]);
    });

    test('no acknowledgement client (demo): prints, reports nothing', () async {
      final h = _H(withAck: false);
      await h.boot();
      expect(await h.apply(a1), OrderEditSlipOutcome.printed);
      expect(h.ackTransport.calls, isEmpty);
    });

    test('no proven detail: recorded UNBUILT with its frozen inputs, the '
        'mirror reads failed (the spool may print it, D3), nothing is '
        'printed', () async {
      final h = _H();
      await h.boot();
      expect(await h.apply(a1, proven: false), OrderEditSlipOutcome.notPrinted);
      await _settle();
      expect(h.printer.slips, isEmpty);
      expect(h.ackTransport.calls, isEmpty);
      expect(h.claims.claims[a1.mirrorKey], PosRoundPrintClaimState.failed);
      expect(h.slips.isDispatchInFlight(a1.dispatchId), isFalse);
      final record = (await h.store.stored())[a1.editId]!;
      expect(record.isBuilt, isFalse);
      expect(record.lines, hasLength((a1.payload['changes']! as List).length));
      expect(record.was, isNotEmpty);
      expect(record.staffFirstName, 'Dana');
      expect(record.dispatchId, a1.dispatchId);
      expect(h.pending.single.orderEditId, a1.editId);
    });

    test('a refused slip-store write keeps the record for the session and '
        'still prints', () async {
      final h = _H();
      h.store.failWrites = true;
      await h.boot();
      h.printer.script = [PosKitchenPrintOutcome.failed];
      expect(await h.apply(a1), OrderEditSlipOutcome.notPrinted);
      expect(h.printer.slips, hasLength(1));
      expect(h.state.records.keys, [a1.editId]);
      expect(await h.store.stored(), isEmpty);
    });

    test('a KDS edit never reaches the paper path', () async {
      final h = _H();
      await h.boot();
      final kds = OrderEditApplied(
        orderEditId: 'edit-kds',
        editNumber: 1,
        revision: 2,
        kitchenChannel: PosKitchenChannel.kds,
        kitchenAckRequired: true,
      );
      await h.slips.recordApplied(
        attempt: a1.attempt(),
        applied: kds,
        fresh: a1.after,
      );
      expect(
        await h.slips.printRecorded('edit-kds'),
        OrderEditSlipOutcome.notApplicable,
      );
      expect(h.log, isEmpty);
    });

    test('superseded on the server — a newer edit, or a void — prints '
        'nothing and reports nothing', () async {
      final newer = _newer(a1);
      expect(newer.editCount, 2);
      final voided = _voided(a1);
      expect(voided.status, 'voided');
      for (final fresh in [newer, voided]) {
        final h = _H();
        await h.boot();
        expect(
          await h.apply(a1, fresh: fresh),
          OrderEditSlipOutcome.superseded,
        );
        await _settle();
        expect(h.printer.slips, isEmpty);
        expect(h.ackTransport.calls, isEmpty);
        expect(await h.store.stored(), isEmpty);
        expect(h.claims.claims, isEmpty);
      }
    });

    test('a newer edit retires the older unsent slip of the order', () async {
      final h = _H();
      await h.boot();
      await h.apply(a1, proven: false); // edit 1: unbuilt, banner
      expect(h.pending.single.editNumber, 1);
      expect(await h.apply(a2), OrderEditSlipOutcome.printed);
      expect(h.state.records, isEmpty);
      expect(await h.store.stored(), isEmpty);
      expect(h.printer.slips.single.editNumber, 2);
    });
  });

  group('restart', () {
    test('a crash MID-PRINT (guard key claimed) prints nothing automatically; '
        'Print again re-enters deliberately', () async {
      final log = <String>[];
      final claims = _Claims(log);
      final store = _Store(log);
      final first = _H(claims: claims, store: store);
      await first.boot();
      await first.slips.recordApplied(
        attempt: a1.attempt(),
        applied: a1.applied(),
        fresh: a1.after,
      );
      // The process died after claiming, before the transport answered.
      claims.claims[a1.guardKey] = PosRoundPrintClaimState.claimed;

      final next = _H(claims: claims, store: store);
      next.details.byId[a1.orderId] = a1.after;
      await next.boot();
      expect(next.state.records.keys, [a1.editId]);
      expect(
        await next.slips.printRecorded(a1.editId),
        OrderEditSlipOutcome.notPrinted,
      );
      expect(next.printer.slips, isEmpty);
      expect(next.pending.single.orderEditId, a1.editId);

      final again = await next.slips.printAgain(a1.editId);
      expect(again.status, OrderEditPrintAgainStatus.printed);
      expect(next.printer.slips, hasLength(1));
      expect(claims.claims[a1.guardKey], PosRoundPrintClaimState.sent);
      expect(next.state.records, isEmpty);
    });

    test(
      'bytes already SENT before the crash: settled, never re-sent',
      () async {
        final log = <String>[];
        final claims = _Claims(log);
        final store = _Store(log);
        final first = _H(claims: claims, store: store);
        await first.boot();
        await first.slips.recordApplied(
          attempt: a1.attempt(),
          applied: a1.applied(),
          fresh: a1.after,
        );
        claims.claims[a1.guardKey] = PosRoundPrintClaimState.sent;

        final next = _H(claims: claims, store: store);
        await next.boot();
        expect(
          await next.slips.printRecorded(a1.editId),
          OrderEditSlipOutcome.printed,
        );
        await _settle();
        expect(next.printer.slips, isEmpty);
        expect(await store.stored(), isEmpty);
        expect(claims.claims[a1.mirrorKey], PosRoundPrintClaimState.sent);
        expect(
          next.ackTransport.calls.single['p_client_status'],
          'transport_accepted',
        );
      },
    );

    test('bytes SENT before the crash and the journal already CLOSED (nothing '
        'replays the print): the restart settles the slip — no banner, '
        'transport_accepted — and Print again never sends it twice', () async {
      final log = <String>[];
      final claims = _Claims(log);
      final store = _Store(log);
      final first = _H(claims: claims, store: store);
      await first.boot();
      await first.slips.recordApplied(
        attempt: a1.attempt(),
        applied: a1.applied(),
        fresh: a1.after,
      );
      // The transport accepted the bytes and the guard settled `sent`; the
      // process died before the record was removed (the journal had closed).
      claims.claims[a1.guardKey] = PosRoundPrintClaimState.sent;

      final next = _H(claims: claims, store: store);
      next.details.byId[a1.orderId] = a1.after;
      await next.boot();
      await _settle();
      expect(next.pending, isEmpty);
      expect(next.state.records, isEmpty);
      expect(await store.stored(), isEmpty);
      expect(claims.claims[a1.mirrorKey], PosRoundPrintClaimState.sent);
      expect(
        next.ackTransport.calls.single['p_client_status'],
        'transport_accepted',
      );
      final again = await next.slips.printAgain(a1.editId);
      expect(again.status, OrderEditPrintAgainStatus.notFound);
      expect(next.printer.slips, isEmpty);
      expect(claims.claims[a1.guardKey], PosRoundPrintClaimState.sent);
    });

    test('Print again over a guard key that already reads SENT settles the '
        'slip as printed: nothing is sent and `sent` is never downgraded '
        'to `claimed`', () async {
      final h = _H();
      h.printer.script = [
        PosKitchenPrintOutcome.failed,
        PosKitchenPrintOutcome.printed,
      ];
      await h.boot();
      await h.apply(a1);
      await _settle();
      h.details.byId[a1.orderId] = a1.after;
      // The bytes went out after all (e.g. under the same key elsewhere in
      // this session) while the record stayed.
      h.claims.claims[a1.guardKey] = PosRoundPrintClaimState.sent;
      h.log.clear();
      final r = await h.slips.printAgain(a1.editId);
      await _settle();
      expect(r.status, OrderEditPrintAgainStatus.printed);
      expect(h.printer.slips, hasLength(1), reason: 'only the failed attempt');
      expect(h.log, isNot(contains('claim:${a1.guardKey}=claimed')));
      expect(h.claims.claims[a1.guardKey], PosRoundPrintClaimState.sent);
      expect(h.claims.claims[a1.mirrorKey], PosRoundPrintClaimState.sent);
      expect(h.state.records, isEmpty);
      expect(h.log.last, 'ack:transport_accepted');
    });

    test('a replay of an applied edit whose slip record ALREADY exists, after '
        'a void or a newer edit on the server, retires it: nothing printed, '
        'nothing acknowledged', () async {
      for (final fresh in [_newer(a1), _voided(a1)]) {
        final log = <String>[];
        final claims = _Claims(log);
        final store = _Store(log);
        final first = _H(claims: claims, store: store);
        await first.boot();
        await first.slips.recordApplied(
          attempt: a1.attempt(),
          applied: a1.applied(),
          fresh: a1.after,
        );
        // The process died before the journal close: the record is built
        // and pending, the mirror claimed, no guard claim yet.
        expect(claims.claims[a1.mirrorKey], PosRoundPrintClaimState.claimed);
        expect(claims.claims[a1.guardKey], isNull);

        final next = _H(claims: claims, store: store);
        await next.boot();
        expect(
          await next.apply(a1, fresh: fresh),
          OrderEditSlipOutcome.superseded,
        );
        await _settle();
        expect(next.printer.slips, isEmpty);
        expect(next.ackTransport.calls, isEmpty);
        expect(await store.stored(), isEmpty);
        expect(next.pending, isEmpty);
      }
    });

    test('a replay after a FAILED direct print the spool then took over is '
        'handed over: never recorded or printed again', () async {
      final log = <String>[];
      final claims = _Claims(log);
      final store = _Store(log);
      final first = _H(claims: claims, store: store);
      first.printer.script = [PosKitchenPrintOutcome.failed];
      await first.boot();
      expect(await first.apply(a1), OrderEditSlipOutcome.notPrinted);
      // The next drain imported the dispatch (mirror `failed`).
      await first.slips.handOverToSpool(a1.dispatchId);
      expect(claims.claims[a1.guardKey], PosRoundPrintClaimState.failed);
      expect(claims.claims[a1.mirrorKey], PosRoundPrintClaimState.claimed);
      expect(await store.stored(), isEmpty);

      // The journal record stayed open, so the next process replays it.
      final next = _H(claims: claims, store: store);
      await next.boot();
      expect(await next.apply(a1), OrderEditSlipOutcome.handedOver);
      await _settle();
      expect(next.printer.slips, isEmpty);
      expect(next.ackTransport.calls, isEmpty);
      expect(await store.stored(), isEmpty);
      expect(next.pending, isEmpty);
    });

    test('a replay after a print never records it again; a replay after a '
        'hand-over to the spool never records it either', () async {
      final log = <String>[];
      final claims = _Claims(log);
      final store = _Store(log);
      final first = _H(claims: claims, store: store);
      await first.boot();
      expect(await first.apply(a1), OrderEditSlipOutcome.printed);
      // A restart whose journal close did not stick replays the edit.
      final next = _H(claims: claims, store: store);
      await next.boot();
      expect(await next.apply(a1), OrderEditSlipOutcome.printed);
      expect(next.printer.slips, isEmpty);
      expect(await store.stored(), isEmpty);

      // b1 is recorded unbuilt and the spool takes it over.
      expect(
        await next.apply(b1, proven: false),
        OrderEditSlipOutcome.notPrinted,
      );
      await next.slips.handOverToSpool(b1.dispatchId);
      expect(claims.claims[b1.mirrorKey], PosRoundPrintClaimState.claimed);
      expect(next.state.records, isEmpty);
      expect(next.pending, isEmpty);
      final third = _H(claims: claims, store: store);
      await third.boot();
      expect(await third.apply(b1), OrderEditSlipOutcome.handedOver);
      expect(third.printer.slips, isEmpty);
      expect(await store.stored(), isEmpty);
    });

    test('an unreadable claim store never silently drops the slip: it is '
        'recorded, withheld from the automatic print, and offered', () async {
      final h = _H();
      await h.boot();
      // Every key reads `claimed` (F8: unreadable is not "never claimed").
      h.claims.claims[a1.guardKey] = PosRoundPrintClaimState.claimed;
      h.claims.claims[a1.mirrorKey] = PosRoundPrintClaimState.claimed;
      expect(await h.apply(a1), OrderEditSlipOutcome.notPrinted);
      expect(h.printer.slips, isEmpty);
      expect(h.pending.single.orderEditId, a1.editId);
    });
  });

  group('Print again', () {
    test('blocked while the slip is printing, and while the order carries an '
        'unresolved edit', () async {
      final h = _H();
      await h.boot();
      h.printer.script = [PosKitchenPrintOutcome.failed];
      await h.apply(a1);
      h.details.byId[a1.orderId] = a1.after;
      h.printer.gate = Completer<void>();
      h.printer.script = [
        PosKitchenPrintOutcome.failed,
        PosKitchenPrintOutcome.printed,
      ];
      final running = h.slips.printAgain(a1.editId);
      await _settle();
      expect(
        (await h.slips.printAgain(a1.editId)).status,
        OrderEditPrintAgainStatus.blocked,
      );
      h.printer.gate!.complete();
      expect((await running).status, OrderEditPrintAgainStatus.printed);

      // An unresolved edit of the order (its journal record) blocks it.
      final journal = _Journal();
      final pendingEdit = a2.attempt();
      await journal.persist('dev-1', {
        pendingEdit.localOperationId: pendingEdit.toRecord(),
      });
      final g = _H(journal: journal);
      g.printer.script = [PosKitchenPrintOutcome.failed];
      await g.boot();
      g.c.read(orderEditControllerProvider);
      await _settle();
      expect(
        g.c.read(orderEditControllerProvider).hasUnresolvedEditFor(a1.orderId),
        isTrue,
      );
      await g.apply(a1);
      g.details.byId[a1.orderId] = a1.after;
      expect(
        (await g.slips.printAgain(a1.editId)).status,
        OrderEditPrintAgainStatus.blocked,
      );
      expect(g.details.fetches, 0);
    });

    test('a failed fetch keeps the record and prints nothing', () async {
      final h = _H();
      h.printer.script = [PosKitchenPrintOutcome.failed];
      await h.boot();
      await h.apply(a1);
      h.details.error = StateError('offline');
      final r = await h.slips.printAgain(a1.editId);
      expect(r.status, OrderEditPrintAgainStatus.fetchFailed);
      expect(h.printer.slips, hasLength(1));
      expect(h.state.records.keys, [a1.editId]);
      expect(h.pending, hasLength(1));
    });

    test('a voided order retires the slip silently (D9)', () async {
      final h = _H();
      h.printer.script = [PosKitchenPrintOutcome.failed];
      await h.boot();
      await h.apply(a1);
      h.details.byId[a1.orderId] = _voided(a1);
      final r = await h.slips.printAgain(a1.editId);
      expect(r.status, OrderEditPrintAgainStatus.retired);
      expect(h.printer.slips, hasLength(1));
      expect(await h.store.stored(), isEmpty);
      expect(h.pending, isEmpty);
    });

    test('a newer edit: from ANOTHER till -> offer Print latest (an '
        'ORDER-NOW slip, unguarded and unacknowledged); one THIS till '
        'already printed -> nothing to offer', () async {
      // Edit 1 failed here; edit 2 then came from another till.
      final h = _H();
      h.printer.script = [PosKitchenPrintOutcome.failed];
      await h.boot();
      await h.apply(a1);
      await _settle();
      h.ackTransport.calls.clear();
      h.details.byId[a1.orderId] = a2.after;
      final r = await h.slips.printAgain(a1.editId);
      expect(r.status, OrderEditPrintAgainStatus.newerEdit);
      expect(r.offerLatest, isTrue);
      expect(r.newerLocalOrderEditId, isNull);
      expect(r.hasOffer, isTrue);
      expect(h.state.records, isEmpty);
      expect(h.printer.slips, hasLength(1));

      h.printer.script = [PosKitchenPrintOutcome.printed];
      final latest = await h.slips.printLatest(a1.orderId);
      expect(latest.status, OrderEditPrintAgainStatus.printed);
      final slip = h.printer.slips.last;
      expect(slip.editNumber, 2);
      expect(slip.changes, isEmpty);
      expect(slip.staffFirstName, isNull);
      expect(slip.orderNow, isNotEmpty);
      await _settle();
      expect(h.ackTransport.calls, isEmpty);
      expect(h.claims.claims.keys, isNot(contains(a2.guardKey)));

      // Edit 2 printed HERE (its evidence), so a stale edit-1 record found
      // after a restart offers nothing.
      final g = _H();
      await g.boot();
      expect(await g.apply(a2), OrderEditSlipOutcome.printed);
      await g.store.persist('dev-1', {
        a1.editId: OrderEditSlipRecord(
          orderEditId: a1.editId,
          orderId: a1.orderId,
          orderCode: '#00A001',
          editNumber: 1,
          updatedAt: _now,
        ),
      });
      final h3 = _H(claims: g.claims, store: g.store);
      h3.details.byId[a1.orderId] = a2.after;
      await h3.boot();
      final none = await h3.slips.printAgain(a1.editId);
      expect(none.status, OrderEditPrintAgainStatus.newerEdit);
      expect(none.hasOffer, isFalse);
    });

    test(
      'a newer UNSENT slip of this till is what "Print latest" prints',
      () async {
        final h = _H();
        await h.store.persist('dev-1', {
          a1.editId: OrderEditSlipRecord(
            orderEditId: a1.editId,
            orderId: a1.orderId,
            orderCode: '#00A001',
            editNumber: 1,
            updatedAt: _now,
          ),
          a2.editId: OrderEditSlipRecord(
            orderEditId: a2.editId,
            orderId: a2.orderId,
            orderCode: '#00A001',
            editNumber: 2,
            state: OrderEditSlipState.failed,
            updatedAt: _now,
          ),
        });
        h.details.byId[a1.orderId] = a2.after;
        await h.boot();
        final r = await h.slips.printAgain(a1.editId);
        expect(r.status, OrderEditPrintAgainStatus.newerEdit);
        expect(r.newerLocalOrderEditId, a2.editId);
        expect(r.offerLatest, isFalse);
        expect(h.state.records.keys, [a2.editId]);
      },
    );

    test('an UNBUILT record is built at Print again from its frozen inputs '
        '(the full server slip)', () async {
      final h = _H();
      await h.boot();
      await h.apply(a1, proven: false);
      h.details.byId[a1.orderId] = a1.after;
      final r = await h.slips.printAgain(a1.editId);
      await _settle();
      expect(r.status, OrderEditPrintAgainStatus.printed);
      expect(await _bytes(h.printer.slips.single), await _bytes(a1.server));
      expect(h.log.last, 'ack:transport_accepted');
      expect(await h.store.stored(), isEmpty);
    });

    test('a 001E-format record (no frozen "was") prints the ORDER-NOW slip '
        'of THIS edit — never a partial change list', () async {
      final h = _H();
      await h.boot();
      await h.apply(a1, proven: false, withWas: false);
      h.details.byId[a1.orderId] = a1.after;
      final r = await h.slips.printAgain(a1.editId);
      expect(r.status, OrderEditPrintAgainStatus.printed);
      final slip = h.printer.slips.single;
      expect(slip.editNumber, 1);
      expect(slip.changes, isEmpty);
      String line(KdsItemView i) =>
          '${i.linePosition}|${i.quantity}|${i.name}|${i.modifiers}|${i.note}';
      expect(slip.orderNow.map(line), a1.server.orderNow.map(line));
    });

    test('the STORED document is re-sent byte-identically under the SAME '
        'guard key (mirror and guard claimed, then runPreclaimed)', () async {
      final h = _H();
      h.printer.script = [
        PosKitchenPrintOutcome.failed,
        PosKitchenPrintOutcome.printed,
      ];
      await h.boot();
      await h.apply(a1);
      await _settle();
      final stored = (await h.store.stored())[a1.editId]!.slip!;
      h.details.byId[a1.orderId] = a1.after;
      h.log.clear();
      final r = await h.slips.printAgain(a1.editId);
      await _settle();
      expect(r.status, OrderEditPrintAgainStatus.printed);
      expect(
        jsonEncode(encodeOrderChangeSlipView(h.printer.slips[1])),
        jsonEncode(encodeOrderChangeSlipView(stored)),
      );
      expect(
        await _bytes(h.printer.slips[1]),
        await _bytes(h.printer.slips[0]),
      );
      expect(h.log, [
        'claim:${a1.mirrorKey}=claimed',
        'claim:${a1.guardKey}=claimed',
        'print:#00A001#1',
        'claim:${a1.guardKey}=sent',
        'claim:${a1.mirrorKey}=sent',
        'persist:',
        'evidence:${a1.orderId}',
        'ack:transport_accepted',
      ]);
    });

    test('a refused claim at Print again sends nothing', () async {
      final h = _H();
      h.printer.script = [PosKitchenPrintOutcome.failed];
      await h.boot();
      await h.apply(a1);
      h.details.byId[a1.orderId] = a1.after;
      h.claims.refuse.add(a1.guardKey);
      final r = await h.slips.printAgain(a1.editId);
      expect(r.status, OrderEditPrintAgainStatus.notPrinted);
      expect(r.printOutcome, PosKitchenPrintOutcome.failed);
      expect(h.printer.slips, hasLength(1));
      expect(h.pending, hasLength(1));
    });

    test('nothing recorded -> notFound', () async {
      final h = _H();
      await h.boot();
      expect(
        (await h.slips.printAgain('nope')).status,
        OrderEditPrintAgainStatus.notFound,
      );
    });
  });

  group('the pending slips', () {
    PosRecentOrder row(String orderId, {int editCount = 1, String? status}) {
      final at = DateTime.utc(2026, 10, 9, 5);
      return PosRecentOrder(
        snapshot: PosOrderSnapshot(
          orderId: orderId,
          orderCode: '#00A001',
          revision: 2,
          status: status ?? 'submitted',
          settlement: PosSettlement.unpaid,
          subtotalMinor: 15800,
          discountTotalMinor: 0,
          taxTotalMinor: 0,
          grandTotalMinor: 15800,
          createdAt: at,
          updatedAt: at,
          syncAt: at,
          editCount: editCount,
        ),
      );
    }

    test('unsent and not printing; hidden once the order snapshot shows a '
        'newer edit, a void or a cancel', () async {
      final h = _H();
      await h.boot();
      await h.apply(a1, proven: false);
      expect(h.pending.single.orderEditId, a1.editId);
      h.recent.setOrders([row(a1.orderId)]);
      expect(h.pending, hasLength(1));
      h.recent.setOrders([row(a1.orderId, editCount: 2)]);
      expect(h.pending, isEmpty);
      h.recent.setOrders([row(a1.orderId, status: 'voided')]);
      expect(h.pending, isEmpty);
      h.recent.setOrders([row(a1.orderId, status: 'cancelled')]);
      expect(h.pending, isEmpty);
    });

    test('restored after a restart', () async {
      final log = <String>[];
      final store = _Store(log);
      final first = _H(store: store);
      await first.boot();
      await first.apply(a1, proven: false);
      final next = _H(store: store);
      await next.boot();
      expect(next.state.hydrated, isTrue);
      expect(next.pending.single.orderEditId, a1.editId);
    });

    test('a snapshot that PROVES the slip superseded (a newer edit, a void) '
        'RETIRES it — it never resurfaces once the order leaves the recent '
        'window, and nothing offers Print latest for it', () async {
      for (final proof in [
        row(a1.orderId, editCount: 2),
        row(a1.orderId, status: 'voided'),
      ]) {
        final h = _H();
        await h.boot();
        await h.apply(a1, proven: false);
        expect(h.pending.single.orderEditId, a1.editId);
        h.recent.setOrders([proof]);
        await _settle();
        expect(h.state.records, isEmpty);
        expect(await h.store.stored(), isEmpty);
        // The order leaves the recent-orders window.
        h.recent.setOrders(const []);
        expect(h.pending, isEmpty);
        expect(
          (await h.slips.printAgain(a1.editId)).status,
          OrderEditPrintAgainStatus.notFound,
        );
        expect(h.printer.slips, isEmpty);
      }
    });

    test('a slip whose order is gone from the snapshot and whose record is '
        'older than the recent-orders window (start of yesterday) is retired '
        'at boot; a recent one is kept', () async {
      final h = _H();
      await h.store.persist('dev-1', {
        a1.editId: OrderEditSlipRecord(
          orderEditId: a1.editId,
          orderId: a1.orderId,
          orderCode: '#00A001',
          editNumber: 1,
          state: OrderEditSlipState.failed,
          updatedAt: DateTime(_now.year, _now.month, _now.day - 2, 23, 59),
        ),
        b1.editId: OrderEditSlipRecord(
          orderEditId: b1.editId,
          orderId: b1.orderId,
          orderCode: '#00B001',
          editNumber: 1,
          state: OrderEditSlipState.failed,
          updatedAt: DateTime(_now.year, _now.month, _now.day - 1),
        ),
      });
      h.details.byId[a1.orderId] = a2.after;
      await h.boot();
      await _settle();
      expect(h.state.records.keys, [b1.editId]);
      expect((await h.store.stored()).keys, [b1.editId]);
      expect(h.pending.single.orderEditId, b1.editId);
      final r = await h.slips.printAgain(a1.editId);
      expect(r.status, OrderEditPrintAgainStatus.notFound);
      expect(r.hasOffer, isFalse);
      expect(h.printer.slips, isEmpty);
      expect(h.details.fetches, 0);
    });
  });
  group('the spool consult race', () {
    late Directory tempDir;
    late KitchenSpoolDatabase db;
    late DriftKitchenSpoolStore spool;
    final key = SecretValue(base64Url.encode(List<int>.filled(32, 7)));

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rf_slip_spool_race');
      db = await KitchenSpoolDatabaseFactory(
        documentsDirectoryProvider: () async => tempDir,
      ).open();
      spool = DriftKitchenSpoolStore(db);
    });

    tearDown(() async {
      await db.close();
      await tempDir.delete(recursive: true);
    });

    /// The REAL import coordinator over a REAL spool database, wired to
    /// [h]'s slip controller exactly as the spool composition wires it.
    KitchenDispatchImportCoordinator coordinator(_H h, _GatedCipher cipher) =>
        KitchenDispatchImportCoordinator(
          store: spool,
          cipher: cipher,
          key: key,
          scope: const KitchenImportScope(
            organizationId: 'org-1',
            restaurantId: 'rest-1',
            branchId: 'branch-1',
            deviceId: 'dev-1',
          ),
          destination: const ResolvedKitchenDestination(
            destination: NetworkKitchenDestination(
              host: '10.0.0.5',
              port: 9100,
            ),
            fingerprint: 'fp-net-1',
            displayLabel: 'Kitchen',
            transportKind: 'network',
            paperWidth: '80mm',
          ),
          ackRepository: h.ack,
          localJobIdGenerator: () => 'job-1',
          now: () => _now,
          readOrderEditPrintClaim: (dispatchId) =>
              h.claims.claimOf(posOrderEditDispatchClaimKey(dispatchId)),
          isOrderEditSlipInFlight: h.slips.isDispatchInFlight,
          reserveOrderEditSlip: h.slips.reserveForSpool,
          releaseOrderEditSlip: h.slips.releaseSpoolReservation,
          onOrderEditImported: h.slips.handOverToSpool,
        );

    /// [e]'s dispatch as the drain pulls it (re-served: this till's claim).
    PulledKitchenDispatch pulled(_Edit e) => PulledKitchenDispatch(
      dispatchId: e.dispatchId,
      dispatchType: 'order_edit',
      orderId: e.orderId,
      payloadVersion: 1,
      moneyFreePayload: _map(e.raw['dispatch']),
      createdAt: '2026-10-09T05:31:13Z',
    );

    test('the till never prints a slip the spool consult already took: '
        'recordApplied and printRecorded interleaved between the consult and '
        'the hand-over send nothing directly', () async {
      final h = _H();
      await h.boot();
      final cipher = _GatedCipher();
      final importing = coordinator(h, cipher).importDispatches([pulled(a1)]);
      // The consult passed (not in flight, no mirror): the import is running.
      await cipher.entered.future;
      await h.slips.recordApplied(
        attempt: a1.attempt(),
        applied: a1.applied(),
        fresh: a1.after,
      );
      final outcome = await h.slips.printRecorded(a1.editId);
      cipher.gate.complete();
      final summary = await importing;
      await _settle();
      expect(h.printer.slips, isEmpty);
      expect(outcome, OrderEditSlipOutcome.handedOver);
      expect(summary.imported, 1);
      expect(summary.orderEditsHandedOver, 1);
      expect(h.claims.claims[a1.mirrorKey], PosRoundPrintClaimState.claimed);
      expect(h.claims.claims[a1.guardKey], isNull);
      expect(h.state.records, isEmpty);
      expect(await h.store.stored(), isEmpty);
      expect(h.pending, isEmpty);
    });

    test(
      'Print again cannot print a slip the spool consult already took',
      () async {
        final h = _H();
        h.printer.script = [
          PosKitchenPrintOutcome.failed,
          PosKitchenPrintOutcome.printed,
        ];
        await h.boot();
        // The direct print failed: the mirror reads `failed`, so the drain
        // imports the dispatch.
        expect(await h.apply(a1), OrderEditSlipOutcome.notPrinted);
        await _settle();
        h.details.byId[a1.orderId] = a1.after;
        final cipher = _GatedCipher();
        final importing = coordinator(h, cipher).importDispatches([pulled(a1)]);
        await cipher.entered.future;
        final again = await h.slips.printAgain(a1.editId);
        cipher.gate.complete();
        final summary = await importing;
        await _settle();
        expect(
          h.printer.slips,
          hasLength(1),
          reason: 'the failed attempt only',
        );
        expect(again.status, isNot(OrderEditPrintAgainStatus.printed));
        expect(summary.orderEditsHandedOver, 1);
        expect(h.claims.claims[a1.mirrorKey], PosRoundPrintClaimState.claimed);
        expect(h.state.records, isEmpty);
        expect(h.pending, isEmpty);
      },
    );

    test(
      'an import that FAILS after the consult gives the slip back: the '
      'record kept meanwhile shows its banner and Print again prints it',
      () async {
        final h = _H();
        await h.boot();
        final cipher = _GatedCipher()..failWith = StateError('disk full');
        final importing = coordinator(h, cipher).importDispatches([pulled(a1)]);
        await cipher.entered.future;
        await h.slips.recordApplied(
          attempt: a1.attempt(),
          applied: a1.applied(),
          fresh: a1.after,
        );
        await h.slips.printRecorded(a1.editId);
        cipher.gate.complete();
        await expectLater(importing, throwsStateError);
        await _settle();
        expect(h.printer.slips, isEmpty);
        expect(await spool.findByDispatchId(a1.dispatchId), isNull);
        expect(h.pending.single.orderEditId, a1.editId);
        h.details.byId[a1.orderId] = a1.after;
        final again = await h.slips.printAgain(a1.editId);
        expect(again.status, OrderEditPrintAgainStatus.printed);
        expect(h.printer.slips, hasLength(1));
        expect(h.state.records, isEmpty);
      },
    );
  });
}
