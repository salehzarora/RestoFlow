import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show
        DevicePrinterAssignments,
        DevicePrinterAssignmentsFailure,
        DevicePrinterAssignmentsReader;
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/pos_printer_assignments.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_confirmation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// KITCHEN-MODIFIER-PREP-CLASSIFIER-REJECTION-UX-AUDIT-FIX-022 — Codex HIGH.
///
/// The confirmation rendered the GREEN success header and "Order submitted" for
/// every state, including a PERMANENTLY REJECTED submit. For that state the
/// server created no order at all: `app.sync_push` validates and dispatches
/// `order.submit` inside its own exception subtransaction, so a permanent
/// rejection means no `orders` row exists. Announcing success over it is the
/// single loudest thing on the screen contradicting everything below it — the
/// failed sync card, the "not created" notice, the withdrawn Pay/Discount.
///
/// The rejection title is asserted as a LITERAL so these fail on BEHAVIOUR
/// against HEAD da8c0de rather than on a missing symbol.
const _rejectedTitle = 'Order not submitted';

const String _staleCode = 'modifier_prep_snapshot_stale';

class _FakeOutbox extends OutboxController {
  _FakeOutbox(this.entries);
  final List<OutboxEntry> entries;
  @override
  List<OutboxEntry> build() => entries;
}

class _EmptyAssignments implements DevicePrinterAssignmentsReader {
  @override
  Future<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>>
  load() async => Success(
    DevicePrinterAssignments(
      fetchedAt: DateTime(2026, 8, 2, 12),
      printers: const [],
    ),
  );
}

OutboxEntry _entry(OutboxSyncState state, {String? code}) => OutboxEntry(
  id: 'e1',
  deviceId: 'dev-1',
  localOperationId: 'op-1',
  operationType: 'order.submit',
  targetEntity: 'order',
  targetId: 'order-1',
  payloadJson: '{}',
  summary: const OrderSummary(
    orderNumber: '#3F7A2C',
    orderType: OrderType.takeaway,
    tableLabel: null,
    itemCount: 1,
    subtotalMinor: 4200,
    currencyCode: 'ILS',
  ),
  syncState: state,
  clientCreatedAt: DateTime.utc(2026, 8, 2),
  lastErrorCode: code,
);

const _order = SubmittedOrderView(
  orderNumber: '#3F7A2C',
  orderType: OrderType.takeaway,
  currencyCode: 'ILS',
  subtotalMinor: 4200,
  lines: [
    SubmittedLineView(
      name: 'Classic Burger',
      quantity: 1,
      lineTotalMinor: 4200,
      currencyCode: 'ILS',
    ),
  ],
  // A locally-generated id — never proof of server acceptance.
  orderId: 'order-1',
  outboxEntryId: 'e1',
  localOperationId: 'op-1',
);

Future<void> _pump(
  WidgetTester tester, {
  required OutboxSyncState state,
  String? code,
}) async {
  SharedPreferences.setMockInitialValues(const {});
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posPrinterAssignmentsReaderProvider.overrideWithValue(
        _EmptyAssignments(),
      ),
      paymentRepositoryProvider.overrideWithValue(DemoPaymentStore()),
      outboxControllerProvider.overrideWith(
        () => _FakeOutbox([_entry(state, code: code)]),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: OrderConfirmation(order: _order, onNewOrder: () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  group('A. a stale-rejected draft must not look accepted', () {
    testWidgets('022-A1 the success TITLE is gone', (tester) async {
      final l10n = await _en();
      await _pump(tester, state: OutboxSyncState.rejected, code: _staleCode);
      expect(
        find.text(l10n.posOrderSubmittedTitle),
        findsNothing,
        reason: 'the server created no order — nothing was submitted',
      );
    });

    testWidgets('022-A2 the green success HEADER is gone', (tester) async {
      await _pump(tester, state: OutboxSyncState.rejected, code: _staleCode);
      expect(
        find.byKey(const Key('confirmation-success-header')),
        findsNothing,
      );
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('022-A3 a distinct REJECTION header is rendered', (
      tester,
    ) async {
      await _pump(tester, state: OutboxSyncState.rejected, code: _staleCode);
      expect(
        find.byKey(const Key('confirmation-rejected-header')),
        findsOneWidget,
      );
      expect(find.text(_rejectedTitle), findsOneWidget);
    });

    testWidgets('022-A4 the misleading local "Submitted" pill is gone', (
      tester,
    ) async {
      await _pump(tester, state: OutboxSyncState.rejected, code: _staleCode);
      expect(
        find.byKey(const Key('confirmation-local-status')),
        findsNothing,
        reason:
            'a Submitted chip claims a lifecycle state the order never entered',
      );
    });

    testWidgets('022-A5 the actionable stale note and recovery both remain', (
      tester,
    ) async {
      final l10n = await _en();
      await _pump(tester, state: OutboxSyncState.rejected, code: _staleCode);
      expect(find.text(l10n.posPrepSnapshotStale), findsOneWidget);
      expect(find.byKey(const Key('recovery-actions')), findsOneWidget);
      expect(find.byKey(const Key('recovery-not-created')), findsOneWidget);
    });

    testWidgets('022-A6 no accepted-order action is offered', (tester) async {
      await _pump(tester, state: OutboxSyncState.rejected, code: _staleCode);
      for (final k in const [
        'pay-cash-button',
        'pay-later-button',
        'apply-discount-button',
        'sync-retry-button',
        'print-kitchen-ticket-button',
        'receipt-print-status',
      ]) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
    });

    testWidgets('022-A7 every OTHER permanent rejection reads the same', (
      tester,
    ) async {
      // The correction is keyed to the CLASSIFICATION, not to one code — an
      // item_unavailable shell was equally never created.
      final l10n = await _en();
      await _pump(
        tester,
        state: OutboxSyncState.rejected,
        code: 'item_unavailable',
      );
      expect(find.text(l10n.posOrderSubmittedTitle), findsNothing);
      expect(find.text(_rejectedTitle), findsOneWidget);
    });
  });

  group('B. everything else is untouched', () {
    testWidgets('022-B1 an APPLIED order still shows the success header', (
      tester,
    ) async {
      final l10n = await _en();
      await _pump(tester, state: OutboxSyncState.applied);
      expect(find.text(l10n.posOrderSubmittedTitle), findsOneWidget);
      expect(
        find.byKey(const Key('confirmation-success-header')),
        findsOneWidget,
      );
      expect(find.text(_rejectedTitle), findsNothing);
    });

    testWidgets('022-B2 a TRANSIENT failure still shows the success header', (
      tester,
    ) async {
      // No server verdict was recorded, so the order may well exist. Claiming
      // it was rejected would be its own lie, and Retry stays meaningful.
      final l10n = await _en();
      await _pump(tester, state: OutboxSyncState.dead, code: 'transport');
      expect(find.text(l10n.posOrderSubmittedTitle), findsOneWidget);
      expect(
        find.byKey(const Key('confirmation-success-header')),
        findsOneWidget,
      );
      expect(find.text(_rejectedTitle), findsNothing);
    });

    testWidgets('022-B3 a PENDING order still shows the success header', (
      tester,
    ) async {
      final l10n = await _en();
      await _pump(tester, state: OutboxSyncState.pending);
      expect(find.text(l10n.posOrderSubmittedTitle), findsOneWidget);
      expect(
        find.byKey(const Key('confirmation-local-status')),
        findsOneWidget,
      );
    });
  });
}
