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
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
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
}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = InMemoryRecentOrdersStore();
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

  testWidgets('D: pressing it with no active kitchen orders shows an honest '
      'localized message', (tester) async {
    await _pump(tester, toggleOn: true, role: 'cashier');
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.byKey(_finishKey));
    await tester.pump();
    expect(find.text(l10n.posFinishAllNoActiveOrders), findsOneWidget);
  });
}
