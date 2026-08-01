import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/kitchen_finish_repository.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart'
    show posVerifiedKitchenModeProvider;
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/state/kitchen_finish_controller.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show posHasKitchenNativePrinterProvider;
import 'package:restoflow_pos/src/state/discount_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_auto_print_prefs.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart'
    show posRecentOrdersStoreProvider;
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';

/// KITCHEN-PRINT-DUAL-001D (case D) — the bulk "Finish all kitchen orders" header
/// button is VISIBLE only in real mode with the auto-print toggle ON and a role
/// authorized to change order kitchen statuses; hidden otherwise. Pressing it with
/// no active orders shows an honest localized message.
class _StubAutoKitchen extends PosAutoPrintKitchenTicketController {
  _StubAutoKitchen(this._on);
  final bool _on;
  @override
  Future<bool?> build() async => _on;
}

const _finishKey = Key('finish-all-kitchen-orders-button');

/// SINGLE-DEVICE-ADDITION-CLOSE-AND-STALE-FAILURES-007 self-review — BLOCKER 1.
///
/// The BUG 1 fix lives in `_FinishAllKitchenButton.deriveActive()`, and nothing
/// observed it: reverting that derivation alone left the whole POS suite green
/// while fully restoring the user-reported defect. These drive the real widget
/// through the real controller and record what the batch actually asked for.
class _RecordingRepo implements KitchenFinishRepository {
  final List<String> advanced = [];
  final List<String> completed = [];

  @override
  Future<KitchenFinishResult> advanceToServed({
    required String orderId,
    required String fromStatus,
    required String batchRunId,
    required Future<String?> Function(String orderId) refreshStatus,
  }) async {
    advanced.add(orderId);
    return KitchenFinishResult(orderId, KitchenFinishStatus.finished);
  }

  @override
  Future<KitchenFinishResult> completeServedOrder({
    required String orderId,
    required String localOperationId,
  }) async {
    completed.add(orderId);
    return KitchenFinishResult(orderId, KitchenFinishStatus.finished);
  }
}

/// The till's scope in this harness — `_Host` pairs it to org1/r1/branch-A/dev1
/// and the session is dev1, so the recent-order cache keys on exactly this.
const _scope = PosSyncScope(
  organizationId: 'org1',
  restaurantId: 'r1',
  branchId: 'branch-A',
  deviceId: 'dev1',
);

PosRecentOrder _order({
  required String orderId,
  required String status,
  required PosSettlement settlement,
}) => PosRecentOrder.discovered(
  PosOrderSnapshot(
    orderId: orderId,
    orderCode: '#O0000$orderId',
    revision: 3,
    status: status,
    settlement: settlement,
    subtotalMinor: 12000,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: 12000,
    createdAt: DateTime.utc(2026, 8, 1, 10),
    updatedAt: DateTime.utc(2026, 8, 1, 10),
    syncAt: DateTime.utc(2026, 8, 1, 10),
    orderType: 'dine_in',
    tableLabel: 'T1',
    currencyCode: 'ILS',
  ),
);

/// A branch the server verified as printer_only — the one-device workflow.
final DateTime _verifiedAtValue = DateTime.utc(2026, 8, 1, 9);
final _printerOnly = KitchenModePrinterOnlyWithRevision(
  revision: 4,
  verifiedAt: _verifiedAtValue,
);

class _Host extends ConsumerStatefulWidget {
  const _Host();
  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(posDeviceContextProvider.notifier)
          .set(
            const DeviceContext(
              organizationId: 'org1',
              branchId: 'branch-A',
              restaurantId: 'r1',
              deviceId: 'dev1',
            ),
          );
    });
  }

  @override
  Widget build(BuildContext context) => const RecentOrdersSheet();
}

Future<void> _pump(
  WidgetTester tester, {
  required bool toggleOn,
  required String role,
  KitchenFinishRepository? repo,
  List<PosRecentOrder> orders = const [],
  KitchenModeResult? mode,
}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = InMemoryRecentOrdersStore();
  if (orders.isNotEmpty) await store.persist(_scope.key, orders);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posSyncSessionProvider.overrideWithValue(
          const SyncSession(pinSessionId: 'pin1', deviceId: 'dev1'),
        ),
        posRecentOrdersStoreProvider.overrideWithValue(store),
        posSyncCursorStoreProvider.overrideWithValue(InMemorySyncCursorStore()),
        posSyncPollIntervalProvider.overrideWithValue(null),
        orderSnapshotRepositoryProvider.overrideWithValue(
          DemoOrderSnapshotRepository(),
        ),
        posHasKitchenNativePrinterProvider.overrideWithValue(true),
        posAutoPrintKitchenTicketProvider.overrideWith(
          () => _StubAutoKitchen(toggleOn),
        ),
        staffCapabilitiesProvider.overrideWith(
          (ref) async => PosStaffCapabilities.fromJson(const {}, role: role),
        ),
        if (repo != null)
          kitchenFinishRepositoryProvider.overrideWithValue(repo),
        posVerifiedKitchenModeProvider.overrideWithValue(mode),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const Scaffold(body: _Host()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('D: hidden when the auto-print toggle is OFF', (tester) async {
    await _pump(tester, toggleOn: false, role: 'manager');
    expect(find.byKey(_finishKey), findsNothing);
  });

  testWidgets('D: hidden for an unauthorized role even with the toggle ON', (
    tester,
  ) async {
    await _pump(tester, toggleOn: true, role: 'accountant');
    expect(find.byKey(_finishKey), findsNothing);
  });

  testWidgets('D: visible with the toggle ON and an authorized role', (
    tester,
  ) async {
    await _pump(tester, toggleOn: true, role: 'manager');
    expect(find.byKey(_finishKey), findsOneWidget);
  });

  testWidgets('D: confirming with no active kitchen orders (post-confirmation '
      'refresh) shows an honest localized message', (tester) async {
    await _pump(tester, toggleOn: true, role: 'cashier');
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    // Press -> the confirmation dialog appears FIRST (the eligible set is derived
    // only AFTER confirmation, never captured before the dialog).
    await tester.tap(find.byKey(_finishKey));
    await tester.pumpAndSettle();
    expect(find.text(l10n.posFinishAllConfirmBody), findsOneWidget);
    // Confirm -> refresh the (empty) window + derive -> honest zero/zero message.
    await tester.tap(find.text(l10n.posFinishAllConfirmAction));
    await tester.pumpAndSettle();
    expect(find.text(l10n.posFinishAllNoActiveOrders), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // E. THE DERIVATION ITSELF (007 self-review, BLOCKER 1). What the batch is
  //    ASKED to do, observed through the real button + real controller.
  // -------------------------------------------------------------------------
  group('E deriveActive', () {
    Future<void> confirm(WidgetTester tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.byKey(_finishKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.posFinishAllConfirmAction));
      await tester.pumpAndSettle();
    }

    testWidgets('E1 a served, fully-settled order — the one an Add-items round '
        'strands for ever — IS completed on a printer_only branch', (
      tester,
    ) async {
      final repo = _RecordingRepo();
      await _pump(
        tester,
        toggleOn: true,
        role: 'manager',
        repo: repo,
        mode: _printerOnly,
        orders: [
          _order(
            orderId: 'o-stranded',
            status: 'served',
            settlement: PosSettlement.paid,
          ),
        ],
      );
      await confirm(tester);

      expect(
        repo.completed,
        ['o-stranded'],
        reason:
            'BUG 1: served was excluded as "already off the kitchen board" — '
            'true of the kitchen, false of the ACTIVE ORDERS LIST',
      );
      expect(
        repo.advanced,
        isEmpty,
        reason: 'a served order is never walked forward again',
      );
    });

    testWidgets('E2 a served but UNPAID order is never completed', (
      tester,
    ) async {
      final repo = _RecordingRepo();
      await _pump(
        tester,
        toggleOn: true,
        role: 'manager',
        repo: repo,
        mode: _printerOnly,
        orders: [
          _order(
            orderId: 'o-unpaid',
            status: 'served',
            settlement: PosSettlement.unpaid,
          ),
        ],
      );
      await confirm(tester);

      expect(repo.completed, isEmpty);
      expect(repo.advanced, isEmpty);
    });

    testWidgets('E3 a KDS-verified branch completes NOTHING from the POS — the '
        'KDS/served gate owns that, not this button', (tester) async {
      final repo = _RecordingRepo();
      await _pump(
        tester,
        toggleOn: true,
        role: 'manager',
        repo: repo,
        mode: KitchenModeVerifiedKds(verifiedAt: _verifiedAtValue, revision: 4),
        orders: [
          _order(
            orderId: 'o-stranded',
            status: 'served',
            settlement: PosSettlement.paid,
          ),
        ],
      );
      await confirm(tester);

      expect(
        repo.completed,
        isEmpty,
        reason:
            'the bulk path must obey the SAME close policy as the per-row '
            'Complete button, which forbids a POS close in a KDS workflow',
      );
    });

    testWidgets('E4 an UNVERIFIED workflow mode fails closed', (tester) async {
      final repo = _RecordingRepo();
      await _pump(
        tester,
        toggleOn: true,
        role: 'manager',
        repo: repo,
        orders: [
          _order(
            orderId: 'o-stranded',
            status: 'served',
            settlement: PosSettlement.paid,
          ),
        ],
      );
      await confirm(tester);

      expect(repo.completed, isEmpty);
    });

    testWidgets('E5 an order still ON the kitchen board is advanced, not '
        'completed — the pre-existing behaviour is unchanged', (tester) async {
      final repo = _RecordingRepo();
      await _pump(
        tester,
        toggleOn: true,
        role: 'manager',
        repo: repo,
        mode: _printerOnly,
        orders: [
          _order(
            orderId: 'o-cooking',
            status: 'preparing',
            settlement: PosSettlement.paid,
          ),
        ],
      );
      await confirm(tester);

      expect(repo.advanced, ['o-cooking']);
      expect(repo.completed, isEmpty);
    });
  });
}
