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

/// KITCHEN-DISPATCH-ENFORCE-001 (Codex HIGH 1) — the "server order was NEVER
/// created" state must cover EVERY permanent rejection of an `order.submit`,
/// not just `item_unavailable`.
///
/// `app.sync_push` dispatches each operation inside its own EXCEPTION
/// subtransaction and validates `order.submit` BEFORE `app.submit_order` runs,
/// so a PERMANENT rejection of an `order.submit` means no `orders` row exists —
/// whatever the typed code. Offering Pay / Pay later / Discount / receipt for
/// such an order is a lie about server state.
///
/// The classification is deliberately scoped to `order.submit`: a permanent
/// rejection of a LATER operation (a payment, a discount) says nothing about
/// whether the order itself was created, so it must NOT be treated as a
/// never-created shell.
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
      fetchedAt: DateTime(2026, 7, 29, 12),
      printers: const [],
    ),
  );
}

OutboxEntry _entry(
  OutboxSyncState state, {
  String? code,
  String operationType = 'order.submit',
}) => OutboxEntry(
  id: 'e1',
  deviceId: 'dev-1',
  localOperationId: 'op-1',
  operationType: operationType,
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
  clientCreatedAt: DateTime.utc(2026, 7, 29),
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
  // A NON-NULL locally-generated id — never proof of server acceptance.
  orderId: 'order-1',
  outboxEntryId: 'e1',
  localOperationId: 'op-1',
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required OutboxSyncState state,
  String? code,
  String operationType = 'order.submit',
}) async {
  SharedPreferences.setMockInitialValues(const {});
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      // REAL (non-demo) so the kitchen-print eligibility rule is genuinely
      // exercised instead of being hidden by the demo guard.
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posPrinterAssignmentsReaderProvider.overrideWithValue(
        _EmptyAssignments(),
      ),
      paymentRepositoryProvider.overrideWithValue(DemoPaymentStore()),
      outboxControllerProvider.overrideWith(
        () => _FakeOutbox([
          _entry(state, code: code, operationType: operationType),
        ]),
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
  return container;
}

void _expectNoServerOrderActions() {
  expect(
    find.byKey(const Key('pay-cash-button')),
    findsNothing,
    reason: 'Pay requires a server order that was never created',
  );
  expect(
    find.byKey(const Key('pay-later-button')),
    findsNothing,
    reason: 'Pay later records a debt against an order that does not exist',
  );
  expect(
    find.byKey(const Key('apply-discount-button')),
    findsNothing,
    reason: 'Discount mutates an order that does not exist',
  );
  expect(
    find.byKey(const Key('sync-retry-button')),
    findsNothing,
    reason: 'a permanent verdict replays forever — Retry would be a lie',
  );
  expect(
    find.byKey(const Key('print-kitchen-ticket-button')),
    findsNothing,
    reason: 'there is no server order to cook',
  );
  expect(
    find.byKey(const Key('receipt-print-status')),
    findsNothing,
    reason: 'no receipt for an order that was never created',
  );
  expect(find.byKey(const Key('receipt-print-retry')), findsNothing);
}

void main() {
  group('a PERMANENT order.submit rejection is a never-created shell', () {
    testWidgets('A. dispatch_mode_not_allowed exposes NO server-order action', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        state: OutboxSyncState.rejected,
        code: 'dispatch_mode_not_allowed',
      );

      // The honest not-created presentation renders (existing strings/keys).
      expect(find.byKey(const Key('recovery-actions')), findsOneWidget);
      expect(find.byKey(const Key('recovery-not-created')), findsOneWidget);

      _expectNoServerOrderActions();

      // No payment could have been triggered: nothing to tap, and the payment
      // controller holds no payment for this order identity.
      expect(
        container.read(paymentControllerProvider).paymentFor(_order.identity),
        isNull,
      );
    });

    testWidgets(
      'B. item_unavailable keeps its existing never-created behavior',
      (tester) async {
        await _pump(
          tester,
          state: OutboxSyncState.rejected,
          code: 'item_unavailable',
        );
        expect(find.byKey(const Key('recovery-actions')), findsOneWidget);
        expect(find.byKey(const Key('recovery-not-created')), findsOneWidget);
        _expectNoServerOrderActions();
      },
    );

    testWidgets('C. a RETRYABLE unknown order.submit failure keeps Retry', (
      tester,
    ) async {
      await _pump(
        tester,
        state: OutboxSyncState.rejected,
        code: 'some_transient_thing',
      );
      // Not a permanent verdict -> not a never-created shell, and the
      // idempotent re-push stays available.
      expect(find.byKey(const Key('recovery-actions')), findsNothing);
      expect(find.byKey(const Key('sync-retry-button')), findsOneWidget);
    });

    testWidgets('D. a permanent rejection of a NON-submit op is NOT a shell', (
      tester,
    ) async {
      await _pump(
        tester,
        state: OutboxSyncState.rejected,
        code: 'rejected',
        operationType: 'payment.create',
      );
      // A later operation failing says nothing about whether the ORDER exists,
      // so the never-created presentation must not appear.
      expect(find.byKey(const Key('recovery-actions')), findsNothing);
    });

    testWidgets('E. an APPLIED order keeps its normal actions', (tester) async {
      await _pump(tester, state: OutboxSyncState.applied);
      expect(find.byKey(const Key('recovery-actions')), findsNothing);
      expect(find.byKey(const Key('pay-cash-button')), findsOneWidget);
    });
  });
}
