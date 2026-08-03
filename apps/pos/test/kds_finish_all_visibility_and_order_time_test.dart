import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart'
    show posVerifiedKitchenModeProvider;
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show posHasKitchenNativePrinterProvider;
import 'package:restoflow_pos/src/state/discount_controller.dart'
    show staffCapabilitiesProvider;
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_auto_print_prefs.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart'
    show posRecentOrdersStoreProvider;
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';

import 'support/fixed_pos_clock.dart';

/// POS-KDS-FINISH-ALL-AND-ORDER-TIME-015 — two POS corrections.
///
/// A/B/C: "Finish all kitchen orders" drives the PRINTER-ONLY round-close path,
/// which the server only honours on a printer_only branch. Its visibility keyed
/// on a per-device PRINTING preference, so a `kds` branch whose POS happened to
/// have a kitchen printer with auto-print on still offered a cashier a KDS
/// action that could only ever be refused. It is now gated on the authoritative
/// branch workflow, and hidden until printer_only is positively known.
///
/// D..H: the order time. A cart-submitted order carries the DEVICE's local
/// `submittedAt`; an order refreshed from the server carries `createdAt` parsed
/// from an ISO-8601 UTC string. The list rendered `.hour`/`.minute` straight off
/// whichever it had, so the SAME order jumped to the UTC wall clock the moment a
/// server refresh attached its snapshot — which is exactly what paying from the
/// orders list does. Converting to local exactly once fixes it for both sources
/// and adds no fixed offset.

final DateTime _verifiedAt = DateTime.utc(2026, 8, 1, 9);
final _printerOnly = KitchenModePrinterOnlyWithRevision(
  revision: 4,
  verifiedAt: _verifiedAt,
);
final _kds = KitchenModeVerifiedKds(verifiedAt: _verifiedAt, revision: 4);

const _finishKey = Key('finish-all-kitchen-orders-button');

const _scope = PosSyncScope(
  organizationId: 'org1',
  restaurantId: 'r1',
  branchId: 'branch-A',
  deviceId: 'dev1',
);

/// 14:05 UTC. In any zone east of UTC the LOCAL wall clock differs, so a missing
/// conversion shows a different hour — the exact shape of the reported defect.
final DateTime _createdUtc = DateTime.utc(2026, 8, 1, 14, 5);

/// The same instant expressed in the test machine's local zone. Every assertion
/// compares against THIS, never against a hardcoded offset, so the suite is
/// correct in any timezone including UTC itself.
String _expectedHhmm() {
  final l = _createdUtc.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.hour)}:${two(l.minute)}';
}

SubmittedOrderView _view(String code, String orderId) => SubmittedOrderView(
  orderNumber: code,
  orderType: OrderType.dineIn,
  currencyCode: 'ILS',
  subtotalMinor: 12000,
  orderId: orderId,
  lines: const [
    SubmittedLineView(
      name: 'Burger',
      quantity: 1,
      lineTotalMinor: 12000,
      currencyCode: 'ILS',
    ),
  ],
);

PosOrderSnapshot _snapshot(String orderId, {required DateTime createdAt}) =>
    PosOrderSnapshot(
      orderId: orderId,
      orderCode: '#O00001',
      revision: 3,
      status: 'served',
      settlement: PosSettlement.paid,
      subtotalMinor: 12000,
      discountTotalMinor: 0,
      taxTotalMinor: 0,
      grandTotalMinor: 12000,
      createdAt: createdAt,
      updatedAt: createdAt.add(const Duration(minutes: 30)),
      syncAt: createdAt.add(const Duration(minutes: 30)),
      orderType: 'dine_in',
      tableLabel: 'T1',
      currencyCode: 'ILS',
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
  required KitchenModeResult? mode,
  List<PosRecentOrder> orders = const [],
  bool hasKitchenPrinter = true,
  String role = 'manager',
}) async {
  tester.view.physicalSize = const Size(1000, 1800);
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
        // POS-CI-TIME-TEST-STABILITY-011: pin the recent-orders window's
        // clock. Left on DateTime.now these fixtures aged out of the
        // 1-day window and every list rendered empty.
        pinnedPosSyncClock(),
        orderSnapshotRepositoryProvider.overrideWithValue(
          DemoOrderSnapshotRepository(),
        ),
        posHasKitchenNativePrinterProvider.overrideWithValue(hasKitchenPrinter),
        // The stored auto-print toggle is ON — the pre-fix visibility input.
        posAutoPrintKitchenTicketProvider.overrideWith(_OnKitchenPref.new),
        staffCapabilitiesProvider.overrideWith(
          (ref) async => PosStaffCapabilities.fromJson(const {}, role: role),
        ),
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

class _OnKitchenPref extends PosAutoPrintKitchenTicketController {
  @override
  Future<bool?> build() async => true;
}

void main() {
  group(
    'A/B/C. Finish-all visibility follows the AUTHORITATIVE branch mode',
    () {
      testWidgets('A. kds HIDES the action entirely — not disabled, no tooltip '
          'row, even with a kitchen printer and the auto-print toggle ON', (
        tester,
      ) async {
        await _pump(tester, mode: _kds);
        expect(find.byKey(_finishKey), findsNothing);
        // The rest of the sheet is untouched: its header still renders.
        expect(find.byType(RecentOrdersSheet), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('B. printer_only keeps the action visible and connected', (
        tester,
      ) async {
        await _pump(tester, mode: _printerOnly);
        final btn = find.byKey(_finishKey);
        expect(btn, findsOneWidget);
        expect(
          tester.widget<IconButton>(btn).onPressed,
          isNotNull,
          reason: 'the existing handler stays wired',
        );
      });

      testWidgets('C1. an UNRESOLVED mode does not show it prematurely', (
        tester,
      ) async {
        await _pump(tester, mode: null);
        expect(find.byKey(_finishKey), findsNothing);
      });

      testWidgets('C2. every typed mode FAILURE hides it (fail-safe, never '
          'assume printer_only)', (tester) async {
        for (final m in <KitchenModeResult>[
          const KitchenModeRevisionUnavailable(),
          const KitchenModeInvalidSession(),
          const KitchenModeTransientFailure(),
        ]) {
          await _pump(tester, mode: m);
          expect(find.byKey(_finishKey), findsNothing, reason: '$m');
        }
      });

      testWidgets(
        'C3. hiding it does not block normal order viewing — the order '
        'rows and their time still render in kds',
        (tester) async {
          await _pump(
            tester,
            mode: _kds,
            orders: [
              PosRecentOrder(
                order: _view('#AAA111', 'o-1'),
                submittedAt: _createdUtc.toLocal(),
                snapshot: _snapshot('o-1', createdAt: _createdUtc),
              ),
            ],
          );
          expect(find.byKey(_finishKey), findsNothing);
          expect(find.text(_expectedHhmm()), findsWidgets);
        },
      );
    },
  );

  group('D..H. the order time survives a server refresh', () {
    testWidgets(
      'D. a CART-submitted order (device-local submittedAt, no server '
      'snapshot yet) shows the correct local time',
      (tester) async {
        await _pump(
          tester,
          mode: _printerOnly,
          orders: [
            PosRecentOrder(
              order: _view('#AAA111', 'o-1'),
              submittedAt: _createdUtc.toLocal(),
            ),
          ],
        );
        expect(find.text(_expectedHhmm()), findsWidgets);
      },
    );

    testWidgets('E. the SAME order after a server refresh — the shape an '
        'orders-list payment produces — shows the SAME time, not the UTC '
        'wall clock', (tester) async {
      await _pump(
        tester,
        mode: _printerOnly,
        orders: [
          // Server snapshot attached; `sortAt` now prefers the UTC createdAt.
          PosRecentOrder(
            order: _view('#AAA111', 'o-1'),
            submittedAt: _createdUtc.toLocal(),
            snapshot: _snapshot('o-1', createdAt: _createdUtc),
          ),
        ],
      );
      expect(
        find.text(_expectedHhmm()),
        findsWidgets,
        reason: 'the refreshed row must equal the cart-flow display',
      );
      // And it is NOT the raw UTC wall clock (the reported "hours earlier").
      String two(int v) => v.toString().padLeft(2, '0');
      final utcHhmm = '${two(_createdUtc.hour)}:${two(_createdUtc.minute)}';
      if (utcHhmm != _expectedHhmm()) {
        expect(
          find.text(utcHhmm),
          findsNothing,
          reason: 'the UTC wall clock must never be displayed',
        );
      }
    });

    testWidgets('F+G. a DISCOVERED order (no local submittedAt at all — only '
        'the server UTC createdAt) shows the same instant, and repeated '
        'rebuilds keep it stable', (tester) async {
      await _pump(
        tester,
        mode: _printerOnly,
        orders: [
          PosRecentOrder.discovered(_snapshot('o-2', createdAt: _createdUtc)),
        ],
      );
      expect(find.text(_expectedHhmm()), findsWidgets);

      // A rebuild (provider refresh / re-render) must not move it.
      await tester.pumpAndSettle();
      expect(find.text(_expectedHhmm()), findsWidgets);
    });

    test('H. the row time is derived from the ORDER creation time, never from '
        'a payment/update timestamp', () {
      final paidLater = _createdUtc.add(const Duration(hours: 3));
      final order = PosRecentOrder(
        order: _view('#AAA111', 'o-1'),
        submittedAt: _createdUtc.toLocal(),
        snapshot: _snapshot('o-1', createdAt: _createdUtc),
      );
      // `sortAt` is the creation instant; updatedAt/syncAt moved on but must not
      // be what the row shows.
      expect(order.sortAt.toUtc(), _createdUtc);
      expect(order.sortAt.toUtc(), isNot(paidLater));
      expect(order.snapshot!.updatedAt.toUtc(), isNot(_createdUtc));
    });

    test('G2. cart-local and server-UTC representations of the SAME instant '
        'render identically — the two flows agree by construction', () {
      final fromCart = PosRecentOrder(
        order: _view('#A', 'o-1'),
        submittedAt: _createdUtc.toLocal(),
      );
      final fromServer = PosRecentOrder.discovered(
        _snapshot('o-1', createdAt: _createdUtc),
      );
      expect(
        fromCart.sortAt.toUtc(),
        fromServer.sortAt.toUtc(),
        reason: 'same instant regardless of which field supplied it',
      );
    });
  });
}
