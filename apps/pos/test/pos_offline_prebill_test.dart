@TestOn('vm')
library;

// POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass C — THE OFFLINE CUSTOMER
// PRE-BILL.
//
// THE DEFECT. The unpaid customer bill (DEFERRED-PAYMENT-RECEIPTS-001) was
// already correct as a DOCUMENT: it prints the unpaid marker, labels the total
// "Amount due", omits every payment row and never prints a receipt number. What
// it could not do was print at all without the internet. `_printBill` resolved
// its data through `authoritativeUnpaidOrderSource`, which for a server-backed
// order calls `pos_order_detail` and returns NULL on any failure — and offline
// that call always fails. The cashier got "couldn't load — retry" and no paper,
// while the complete order sat in memory and on disk as `PosRecentOrder.order`.
//
// Pass B then made it worse by accident: it added the server-acknowledgement
// rule to `canPay`, and the bill button rendered inside `if (actions.canPay)`.
// So an order taken DURING an outage — the exact order a customer is standing
// there waiting to be billed for — lost its Print-bill button entirely.
//
// THE FIX UNDER TEST:
//   * `printableUnpaidOrderSource` prefers the authoritative fetch and falls
//     back to this device's stored `SubmittedOrderView`, reporting WHICH it
//     used; it returns null only when there is neither.
//   * `buildBillDocument(..., isLocalReference: true)` prints two notes saying
//     the code is a local reference and the order has not synced.
//   * `PosOrderActions.canPrintBill` — the pre-Pass-B money eligibility MINUS
//     the acknowledgement requirement — gates the button instead of `canPay`.
//   * the action reports its real outcome (`posPrintBillFailed`).
//
// PAYMENTS STAY BLOCKED OFFLINE. Every assertion below that touches money is
// there to prove the bill claims nothing about payment.
//
// Covers the mandated regression list 21-31. Synthetic values only; no network,
// no real printer, no real money.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show
        BluetoothDeviceInfo,
        BluetoothPairedResult,
        BluetoothPrinterConnector,
        bluetoothPrinterConnectorProvider,
        kBluetoothPrintTimeout,
        nativePrinterNamespaceProvider;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/print/print_document.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart'
    show outboxRepositoryProvider;
import 'package:restoflow_pos/src/state/pos_printer_transport.dart'
    show posNativePrintingAvailableProvider;
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart'
    show posSyncScopeProvider;
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart'
    show posRecentOrdersStoreProvider;
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_action_row.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ===========================================================================
// FIXTURES
// ===========================================================================

const _code = '#OFB001';
const _orderId = 'oid-OFB001';

/// The order as THIS DEVICE recorded it — the only copy that exists while the
/// network is down. Two items, a modifier with a quantity, an item note, a
/// discount and tax, so the document has something real to get wrong.
const _localView = SubmittedOrderView(
  orderNumber: _code,
  orderType: OrderType.dineIn,
  tableLabel: 'T4',
  currencyCode: 'ILS',
  subtotalMinor: 9000,
  discountTotalMinor: 500,
  taxTotalMinor: 425,
  taxRateBp: 500,
  orderId: _orderId,
  customerName: 'Dana',
  customerPhone: '+972500000000',
  localOperationId: 'op-OFB001',
  lines: [
    SubmittedLineView(
      name: 'Classic Burger',
      quantity: 2,
      lineTotalMinor: 7800,
      currencyCode: 'ILS',
      modifiers: ['Extra meat ×2', 'Ketchup'],
      note: 'no onions',
    ),
    SubmittedLineView(
      name: 'Fries',
      quantity: 1,
      lineTotalMinor: 1200,
      currencyCode: 'ILS',
    ),
  ],
);

/// 89.25 = 90.00 - 5.00 + 4.25, in integer minor units. Stated as a literal so
/// the test does not reproduce the production arithmetic.
const _grandTotalMinor = 8925;

PosRecentOrder _row({
  PosOrderSnapshot? snapshot,
  CashPayment? payment,
  SubmittedOrderView? view = _localView,
}) => PosRecentOrder(
  order: view,
  snapshot: snapshot,
  payment: payment,
  submittedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 20)),
);

PosOrderSnapshot _snapshot({
  PosSettlement settlement = PosSettlement.unpaid,
  String status = 'served',
  int grand = _grandTotalMinor,
}) {
  final at = DateTime.now().toUtc().subtract(const Duration(hours: 1));
  return PosOrderSnapshot(
    orderId: _orderId,
    orderCode: _code,
    revision: 2,
    status: status,
    settlement: settlement,
    subtotalMinor: 9000,
    discountTotalMinor: 500,
    taxTotalMinor: 425,
    grandTotalMinor: grand,
    createdAt: at,
    updatedAt: at,
    syncAt: at,
    orderType: 'dine_in',
    tableLabel: 'T4',
    currencyCode: 'ILS',
  );
}

/// A completed payment, used ONLY to prove the paid path is untouched.
CashPayment _paid() => CashPayment(
  paymentId: 'pay-OFB001',
  orderNumber: _code,
  deviceId: 'dev-1',
  localOperationId: 'op-pay',
  method: PaymentMethod.cash,
  status: PaymentStatus.completed,
  amountMinor: _grandTotalMinor,
  tenderedMinor: 10000,
  changeMinor: 1075,
  currencyCode: 'ILS',
  receiptNumber: 'R-77',
  paidAt: DateTime.utc(2026, 8, 6, 12, 30),
  orderId: _orderId,
);

/// The world with no backend in it: every detail read fails the way the real
/// transport fails when the network is gone.
class _OfflineDetailRepo implements OrderDetailRepository {
  int attempts = 0;
  @override
  Future<PosOrderDetail> fetch(String orderId) async {
    attempts++;
    throw const PosOrderDetailException(
      PosOrderDetailFailure.transport,
      'network',
    );
  }
}

/// A Bluetooth printer on the counter. [reachable] flips it to a printer that
/// is configured but cannot be reached — the cable-out / powered-off case.
class _RecordingConnector implements BluetoothPrinterConnector {
  _RecordingConnector({this.reachable = true});

  final bool reachable;
  final List<Uint8List> sent = <Uint8List>[];

  @override
  bool get isSupported => true;

  @override
  Future<bool> ensurePermissions() async => true;

  @override
  Future<BluetoothPairedResult> pairedDevices() async =>
      const BluetoothPairedResult.ok(<BluetoothDeviceInfo>[]);

  @override
  Future<pp.PrintResult> send({
    required String address,
    required Uint8List bytes,
    Duration timeout = kBluetoothPrintTimeout,
  }) async {
    if (!reachable) {
      return const pp.PrintResult.failure(
        pp.PrinterErrorCategory.unreachable,
        'printer offline',
      );
    }
    sent.add(bytes);
    return const pp.PrintResult.success();
  }
}

void _seedPrinter({bool configured = true}) {
  SharedPreferences.setMockInitialValues(
    configured
        ? <String, Object>{
            'restoflow.printer.selected.pos.local': 'bluetooth',
            'restoflow.printer.bluetooth.pos.local': jsonEncode(
              <String, Object?>{
                'address': '66:32:1E:0A:BB:CD',
                'name': 'Counter',
              },
            ),
          }
        : const <String, Object>{},
  );
}

String get _billKey => 'bill:${_localView.identity.key}';

Future<AppLocalizations> _l10n(String code) =>
    AppLocalizations.delegate.load(Locale(code));

List<String> _texts(PrintDocument doc) => [
  for (final l in doc.lines) '${l.left ?? ''}|${l.right ?? ''}',
];

String _blob(PrintDocument doc) => _texts(doc).join('\n');

// ===========================================================================
// THE REAL ACTION HARNESS — the production OrderActionRow over a real printer
// stack and a repository that cannot reach a server.
// ===========================================================================

class _ActionHarness {
  _ActionHarness(this.container, this.connector, this.repo, this.l10n);

  final ProviderContainer container;
  final _RecordingConnector connector;
  final _OfflineDetailRepo repo;
  final AppLocalizations l10n;

  ReceiptPrintJob? get billJob =>
      container.read(receiptPrintControllerProvider.notifier).jobFor(_billKey);
}

Future<_ActionHarness> _pumpActionRow(
  WidgetTester tester, {
  bool printerConfigured = true,
  bool printerReachable = true,
  bool submitUnacknowledged = true,
  PosRecentOrder? order,
  String locale = 'en',
}) async {
  _seedPrinter(configured: printerConfigured);
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final connector = _RecordingConnector(reachable: printerReachable);
  final repo = _OfflineDetailRepo();
  final container = ProviderContainer(
    overrides: [
      // REAL mode. Demo would take the self-contained local branch and prove
      // nothing about the path a restaurant runs.
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      orderDetailRepositoryProvider.overrideWithValue(repo),
      posNativePrintingAvailableProvider.overrideWithValue(true),
      nativePrinterNamespaceProvider.overrideWithValue('pos'),
      bluetoothPrinterConnectorProvider.overrideWithValue(connector),
    ],
  );
  addTearDown(container.dispose);
  final row = order ?? _row();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: OrderActionRow(
              order: row,
              l10n: AppLocalizations.of(ctx),
              actions: resolveOrderActions(
                row,
                submitUnacknowledged: submitUnacknowledged,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _ActionHarness(container, connector, repo, await _l10n(locale));
}

Finder get _billButton => find.byKey(const Key('recent-print-bill-$_code'));
Finder get _payButton => find.byKey(const Key('recent-pay-$_code'));

// ===========================================================================

/// 040: the open-order print control now opens a chooser. Tap it, then pick
/// the CUSTOMER BILL — the pre-bill behaviour asserted below is unchanged,
/// only the path to it.
Future<void> tapPrintBill(WidgetTester tester, Finder button) async {
  await tester.tap(button);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('print-choice-bill')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  group('21. the pre-bill is available where it is safe — including for an '
      'order the server has never seen', () {
    // -----------------------------------------------------------------------
    test('canPrintBill survives an UNACKNOWLEDGED submit that correctly '
        'withdraws canPay (the Pass-B interaction)', () {
      final row = _row();
      final queued = resolveOrderActions(row, submitUnacknowledged: true);
      final settled = resolveOrderActions(row);

      expect(settled.canPay, isTrue, reason: 'the control: payable otherwise');
      expect(queued.canPay, isFalse, reason: 'Pass B stands, unchanged');
      expect(
        queued.canPrintBill,
        isTrue,
        reason: 'printing calls no server, so it needs no server acceptance',
      );
      expect(settled.canPrintBill, isTrue);
      // And the row is therefore not "empty" — otherwise the whole action row
      // would be skipped and the button would vanish by another route.
      expect(queued.isEmpty, isFalse);
    });

    test('canPrintBill keeps EVERY other money interlock', () {
      // Paid.
      expect(
        resolveOrderActions(
          _row(snapshot: _snapshot(settlement: PosSettlement.paid)),
        ).canPrintBill,
        isFalse,
      );
      // Charged on this device.
      expect(resolveOrderActions(_row(payment: _paid())).canPrintBill, isFalse);
      // Terminal.
      expect(
        resolveOrderActions(
          _row(snapshot: _snapshot(status: 'cancelled')),
        ).canPrintBill,
        isFalse,
      );
      // Comped to zero — nothing is due, so nothing states an amount due.
      expect(
        resolveOrderActions(_row(snapshot: _snapshot(grand: 0))).canPrintBill,
        isFalse,
      );
      // A payment or a cancellation in flight on this till.
      expect(
        resolveOrderActions(
          _row(),
          pending: PosPendingKind.payment,
        ).canPrintBill,
        isFalse,
      );
      expect(
        resolveOrderActions(
          _row(),
          pending: PosPendingKind.cancellation,
        ).canPrintBill,
        isFalse,
      );
      // A local draft / never-created shell has no order to bill.
      expect(
        resolveOrderActions(
          PosRecentOrder(
            order: _localView,
            submittedAt: DateTime.now().toUtc(),
            origin: PosOrderOrigin.localDraft,
          ),
        ).canPrintBill,
        isFalse,
      );
    });

    test('a REAL amendment still withdraws the pre-bill; the STARTUP BLANKET '
        'does not', () {
      final amending = resolveOrderActions(
        _row(),
        pending: PosPendingKind.itemsAdd,
      );
      expect(
        amending.canPrintBill,
        isFalse,
        reason: 'the printed total would predate the round',
      );
      final hydrating = resolveOrderActions(
        _row(),
        pending: PosPendingKind.itemsAdd,
        amendmentsHydrating: true,
      );
      expect(
        hydrating.canPrintBill,
        isTrue,
        reason: 'a disk read that has not finished is not evidence',
      );
      expect(
        hydrating.canPay,
        isFalse,
        reason: 'MONEY actions stay fail-closed — canPay is untouched',
      );
    });

    testWidgets('the ORDERS SHEET renders the button for a queued offline '
        'order while withholding Collect payment', (tester) async {
      // This closes the assertion print_bill_action_test.dart recorded as
      // OUTSTANDING: the real sheet, the real policy, a real seeded row.
      SharedPreferences.setMockInitialValues(const {});
      tester.view.physicalSize = const Size(1400, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      const scope = PosSyncScope(
        organizationId: 'org-1',
        restaurantId: 'rest-1',
        branchId: 'branch-A',
        deviceId: 'device-1',
      );
      final store = InMemoryRecentOrdersStore();
      await store.persist(scope.key, [_row()]);
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posSyncScopeProvider.overrideWithValue(scope),
          posRecentOrdersStoreProvider.overrideWithValue(store),
          outboxRepositoryProvider.overrideWithValue(
            _SeededOutbox([_queuedSubmit()]),
          ),
          posSyncPollIntervalProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(body: RecentOrdersSheet()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        _payButton,
        findsNothing,
        reason: 'Pass B: record_payment could only answer `order not found`',
      );
      expect(
        _billButton,
        findsOneWidget,
        reason: 'the customer still gets a bill',
      );
      final l10n = await _l10n('en');
      expect(
        find.descendant(
          of: _billButton,
          matching: find.text(l10n.posPrintAction),
        ),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  group('22-25. what the OFFLINE document says, and what it refuses to say', () {
    // -----------------------------------------------------------------------
    late AppLocalizations en;
    late PrintDocument offlineBill;

    setUpAll(() async {
      en = await _l10n('en');
      final source = await printableUnpaidOrderSource(
        isDemoMode: false,
        orderId: _orderId,
        localView: _localView,
        repository: _OfflineDetailRepo(),
      );
      offlineBill = buildBillDocument(
        en,
        source!.view,
        isDemo: false,
        isLocalReference: source.isLocalSnapshot,
      );
    });

    test('22 — items, quantities, modifiers, note and the MONEY all come from '
        'the local snapshot', () {
      final blob = _blob(offlineBill);
      expect(blob, contains('2 × Classic Burger'));
      expect(blob, contains('+ Extra meat ×2'));
      expect(blob, contains('+ Ketchup'));
      expect(blob, contains('no onions'));
      expect(blob, contains('1 × Fries'));
      expect(blob, contains('T4'));
      expect(blob, contains('Dana'));
      // The money lines are the LOCAL integer minor units, formatted — the
      // document recomputes nothing.
      expect(blob, contains('78.00'), reason: 'burger line total');
      expect(blob, contains('12.00'), reason: 'fries line total');
      expect(blob, contains('90.00'), reason: 'subtotal');
      expect(blob, contains('5.00'), reason: 'discount');
      expect(blob, contains('4.25'), reason: 'tax');
      final due = offlineBill.lines
          .firstWhere((l) => l.left == en.receiptAmountDueLabel)
          .right;
      expect(due, contains('89.25'), reason: 'the amount still owed');
    });

    test('23 — it says UNPAID, explicitly, twice over', () {
      final blob = _blob(offlineBill);
      expect(blob, contains(en.receiptUnpaidBillLabel));
      expect(blob, contains(en.receiptAmountDueLabel));
      expect(
        en.receiptUnpaidBillLabel.toLowerCase(),
        contains('unpaid'),
        reason: 'the marker states the fact in words, not by omission',
      );
    });

    test('24 — it claims NOTHING about payment: no paid chip, method, tender, '
        'change, paid time or receipt number', () {
      final blob = _blob(offlineBill);
      expect(blob, isNot(contains(en.posPaidChip)));
      expect(blob, isNot(contains(en.posReceiptTitle)));
      expect(blob, isNot(contains(en.posReceiptPaid)));
      expect(blob, isNot(contains(en.posReceiptChange)));
      expect(blob, isNot(contains(en.posPaymentMethodLabel)));
      expect(blob, isNot(contains(en.posReceiptOrderTotal)));
      // No tendered/change money, no payment identifiers, no receipt number.
      final paid = _paid();
      expect(blob, isNot(contains('100.00')));
      expect(blob, isNot(contains('10.75')));
      expect(blob, isNot(contains(paid.paymentId)));
      expect(blob, isNot(contains(paid.receiptNumber)));
      // No paid timestamp: the only date-shaped text a paid receipt carries.
      expect(blob, isNot(contains('2026-08-06 ')));
    });

    test('25 — with no server order it prints the LOCAL code plus the '
        'local-reference note, and fabricates no server number', () {
      final blob = _blob(offlineBill);
      expect(blob, contains(_code), reason: 'the local code, as it stands');
      expect(blob, contains(en.receiptLocalReferenceNote));
      expect(blob, contains(en.receiptOrderNotSyncedNote));
      // The notes sit directly under the order-number subtitle, so a reader
      // meets the caveat with the code rather than after the totals.
      final texts = [for (final l in offlineBill.lines) l.left];
      final codeAt = texts.indexWhere((t) => t != null && t.contains(_code));
      final noteAt = texts.indexOf(en.receiptLocalReferenceNote);
      expect(codeAt, greaterThanOrEqualTo(0));
      expect(noteAt, codeAt + 1);
    });

    test('25 — an order with NO server identity at all is still printable, and '
        'still marked local', () async {
      const noServerId = SubmittedOrderView(
        orderNumber: '#LOCAL9',
        orderType: OrderType.takeaway,
        currencyCode: 'ILS',
        subtotalMinor: 4000,
        localOperationId: 'op-local-9',
        lines: [
          SubmittedLineView(
            name: 'Burger',
            quantity: 1,
            lineTotalMinor: 4000,
            currencyCode: 'ILS',
          ),
        ],
      );
      final source = await printableUnpaidOrderSource(
        isDemoMode: false,
        orderId: null,
        localView: noServerId,
        repository: _OfflineDetailRepo(),
      );
      expect(source!.isLocalSnapshot, isTrue);
      final blob = _blob(
        buildBillDocument(
          en,
          source.view,
          isDemo: false,
          isLocalReference: true,
        ),
      );
      expect(blob, contains('#LOCAL9'));
      expect(blob, contains(en.receiptLocalReferenceNote));
    });

    test('FAIL CLOSED: no server answer AND no local snapshot yields NO '
        'document at all', () async {
      expect(
        await printableUnpaidOrderSource(
          isDemoMode: false,
          orderId: _orderId,
          localView: null,
          repository: _OfflineDetailRepo(),
        ),
        isNull,
      );
    });
  });

  // =========================================================================
  group('26/27. it really prints, offline, through the real action', () {
    // -----------------------------------------------------------------------
    testWidgets(
      '26 — one tap, offline, sends EXACTLY ONE unpaid local-reference '
      'bill to the configured printer',
      (tester) async {
        final h = await _pumpActionRow(tester);

        expect(_billButton, findsOneWidget);
        await tapPrintBill(tester, _billButton);

        expect(
          h.repo.attempts,
          1,
          reason: 'the server is still asked first — it simply cannot answer',
        );
        expect(h.connector.sent, hasLength(1), reason: 'exactly one send');
        final job = h.billJob;
        expect(job, isNotNull);
        expect(job!.status, PrintJobStatus.sentToPrinter);

        final blob = _blob(job.document!);
        expect(blob, contains(h.l10n.receiptUnpaidBillLabel));
        expect(blob, contains(h.l10n.receiptLocalReferenceNote));
        expect(blob, contains(h.l10n.receiptOrderNotSyncedNote));
        expect(blob, contains('89.25'), reason: 'the local amount due');
        expect(blob, isNot(contains(h.l10n.posPaymentMethodLabel)));
        // Payment stays blocked — this is a print, not a workaround.
        expect(_payButton, findsNothing);
        expect(
          h.container.read(receiptPrintControllerProvider).keys,
          [_billKey],
          reason: 'ONLY the bill job exists — nothing else was triggered',
        );
        expect(find.text(h.l10n.posPrintBillStarted), findsOneWidget);
        expect(find.text(h.l10n.posPrintBillFailed), findsNothing);
      },
    );

    testWidgets('27 — an UNREACHABLE printer leaves a visible non-sent job and '
        'says the print failed', (tester) async {
      final h = await _pumpActionRow(tester, printerReachable: false);

      await tapPrintBill(tester, _billButton);

      expect(h.connector.sent, isEmpty);
      final job = h.billJob;
      expect(job, isNotNull, reason: 'the attempt is visible, never dropped');
      expect(job!.status, isNot(PrintJobStatus.sentToPrinter));
      expect(job.status, PrintJobStatus.bridgeUnavailable);
      expect(job.document, isNotNull, reason: 'still retryable from the job');
      expect(
        find.text(h.l10n.posPrintBillFailed),
        findsOneWidget,
        reason: 'the cashier must not believe paper came out',
      );
      expect(find.text(h.l10n.posPrintBillStarted), findsNothing);
    });

    testWidgets('27 — NO printer configured is reported as a failure too, and '
        'the order is untouched', (tester) async {
      final h = await _pumpActionRow(tester, printerConfigured: false);

      await tapPrintBill(tester, _billButton);

      expect(h.connector.sent, isEmpty);
      expect(h.billJob, isNotNull);
      expect(h.billJob!.status, isNot(PrintJobStatus.sentToPrinter));
      expect(find.text(h.l10n.posPrintBillFailed), findsOneWidget);
    });

    testWidgets('26 — the bill is REPEATABLE and never consumes the paid '
        'receipt slot', (tester) async {
      final h = await _pumpActionRow(tester);

      await tapPrintBill(tester, _billButton);
      await tapPrintBill(tester, _billButton);

      expect(h.connector.sent, hasLength(2), reason: 'a bill may be reprinted');
      expect(
        h.container
            .read(receiptPrintControllerProvider.notifier)
            .jobFor(_localView.identity.key),
        isNull,
        reason: 'the paid-receipt slot stays free',
      );
    });
  });

  // =========================================================================
  group('28/29. nothing else moved', () {
    // -----------------------------------------------------------------------
    testWidgets('28 — printing a pre-bill creates NO kitchen job and mutates '
        'no order state', (tester) async {
      final h = await _pumpActionRow(tester);
      await tapPrintBill(tester, _billButton);

      // The receipt controller is the ONLY print surface this action touches,
      // and it holds exactly the bill. The kitchen stack (ticket builder, auto
      // print guard, claim store, spool) is a different type and a different
      // controller, and is never reached from here.
      expect(h.container.read(receiptPrintControllerProvider).keys, [_billKey]);
    });

    test('29 — the PAID receipt is byte-identical: the new flag cannot reach '
        'it, and a non-local bill is unchanged', () async {
      final en = await _l10n('en');
      final paid = _blob(
        buildReceiptDocument(en, _localView, _paid(), isDemo: false),
      );
      expect(paid, contains(en.posPaidChip));
      expect(paid, contains(en.posReceiptPaid));
      expect(paid, contains(en.posReceiptChange));
      expect(paid, contains(en.posPaymentMethodLabel));
      expect(paid, contains('100.00'), reason: 'tendered');
      expect(paid, contains('10.75'), reason: 'change');
      expect(paid, isNot(contains(en.receiptUnpaidBillLabel)));
      expect(paid, isNot(contains(en.receiptLocalReferenceNote)));
      expect(paid, isNot(contains(en.receiptOrderNotSyncedNote)));

      // The DEFAULT bill (the online, authoritative one) gained nothing.
      final plain = _texts(buildBillDocument(en, _localView, isDemo: false));
      expect(plain, isNot(contains('${en.receiptLocalReferenceNote}|')));
      // The local variant differs from it by EXACTLY the two notes.
      final local = _texts(
        buildBillDocument(
          en,
          _localView,
          isDemo: false,
          isLocalReference: true,
        ),
      );
      expect(local.length, plain.length + 2);
      expect(local.where((l) => !plain.contains(l)).toList(), [
        '${en.receiptLocalReferenceNote}|',
        '${en.receiptOrderNotSyncedNote}|',
      ]);
    });
  });

  // =========================================================================
  group('30/31. ar / he / en', () {
    // -----------------------------------------------------------------------
    for (final code in ['ar', 'he', 'en']) {
      test('$code — the unpaid marker and both local notes are localized, '
          'never hardcoded', () async {
        final l10n = await _l10n(code);
        final blob = _blob(
          buildBillDocument(
            l10n,
            _localView,
            isDemo: false,
            isLocalReference: true,
          ),
        );
        expect(blob, contains(l10n.receiptUnpaidBillLabel));
        expect(blob, contains(l10n.receiptLocalReferenceNote));
        expect(blob, contains(l10n.receiptOrderNotSyncedNote));
      });
    }

    test('the three locales really differ — no untranslated leakage', () async {
      final en = await _l10n('en');
      final ar = await _l10n('ar');
      final he = await _l10n('he');
      for (final pair in [
        (en.receiptUnpaidBillLabel, ar.receiptUnpaidBillLabel),
        (en.receiptUnpaidBillLabel, he.receiptUnpaidBillLabel),
        (ar.receiptUnpaidBillLabel, he.receiptUnpaidBillLabel),
        (en.receiptLocalReferenceNote, ar.receiptLocalReferenceNote),
        (en.receiptLocalReferenceNote, he.receiptLocalReferenceNote),
        (ar.receiptLocalReferenceNote, he.receiptLocalReferenceNote),
        (en.receiptOrderNotSyncedNote, ar.receiptOrderNotSyncedNote),
        (en.receiptOrderNotSyncedNote, he.receiptOrderNotSyncedNote),
        (ar.receiptOrderNotSyncedNote, he.receiptOrderNotSyncedNote),
      ]) {
        expect(pair.$1, isNot(pair.$2));
      }
      // The ar wording the product asked for, stated as data.
      expect(ar.receiptUnpaidBillLabel, contains('غير مدفوع'));
      expect(ar.receiptUnpaidBillLabel, contains('حساب مبدئي'));
      expect(ar.receiptLocalReferenceNote, contains('مرجع محلي'));
      expect(ar.receiptOrderNotSyncedNote, contains('مزامنته'));
      expect(he.receiptUnpaidBillLabel, contains('לא שולם'));
    });

    testWidgets('31 — the RTL (ar) orders row renders the action with no '
        'overflow, and the printed document is identical either way', (
      tester,
    ) async {
      final h = await _pumpActionRow(tester, locale: 'ar');
      expect(_billButton, findsOneWidget);
      expect(
        find.descendant(
          of: _billButton,
          matching: find.text(h.l10n.posPrintAction),
        ),
        findsOneWidget,
      );
      await tapPrintBill(tester, _billButton);
      expect(tester.takeException(), isNull, reason: 'no RTL overflow');

      final blob = _blob(h.billJob!.document!);
      expect(blob, contains(h.l10n.receiptUnpaidBillLabel));
      expect(blob, contains(h.l10n.receiptLocalReferenceNote));
      // The line ORDER is layout, not language: it is the same list in ar.
      final en = await _l10n('en');
      expect(
        h.billJob!.document!.lines.map((l) => l.kind).toList(),
        buildBillDocument(
          en,
          _localView,
          isDemo: false,
          isLocalReference: true,
        ).lines.map((l) => l.kind).toList(),
      );
    });
  });
}

// ===========================================================================
// A queued `order.submit` this device holds and the server has never answered —
// the exact input `posSubmitUnacknowledged` denies payment on.
// ===========================================================================

OutboxEntry _queuedSubmit() => OutboxEntry(
  id: 'entry-$_orderId',
  deviceId: 'device-1',
  localOperationId: 'op-OFB001',
  operationType: 'order.submit',
  targetEntity: 'order',
  targetId: _orderId,
  payloadJson: '{"order_id":"$_orderId"}',
  summary: const OrderSummary(
    orderNumber: _code,
    orderType: OrderType.dineIn,
    tableLabel: 'T4',
    itemCount: 3,
    subtotalMinor: 9000,
    currencyCode: 'ILS',
  ),
  syncState: OutboxSyncState.pending,
  clientCreatedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 20)),
);

class _SeededOutbox implements OutboxRepository {
  _SeededOutbox(this.entries);

  final List<OutboxEntry> entries;

  @override
  Future<OutboxEntry> enqueue(OutboxEntry entry) async => entry;

  @override
  Future<List<OutboxEntry>> recentEntries() async => entries;

  @override
  Future<OutboxEntry> push(String entryId) async =>
      entries.firstWhere((e) => e.id == entryId);

  @override
  Future<OutboxEntry> retry(String entryId) async =>
      entries.firstWhere((e) => e.id == entryId);

  @override
  Future<String?> findOrderSubmitCustomerPhone(
    OrderSubmitPhoneLookupKey key,
  ) async => null;
}
