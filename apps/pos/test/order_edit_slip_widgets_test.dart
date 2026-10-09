import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_feature_kitchen/kitchen_print.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsItemView;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_edit_read_model.dart';
import 'package:restoflow_pos/src/data/order_edit_slip_store.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/state/order_edit_slip_controller.dart'
    show orderEditSlipClockProvider;
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/widgets/order_action_row.dart';
import 'package:restoflow_pos/src/widgets/order_edit_slip_widgets.dart';

import 'support/order_edit_fixtures.dart';

/// ORDER-EDIT-001F — the cashier's side of an UNSENT paper change slip:
///
///  * the menu screen carries one "Kitchen change slip not printed" banner
///    per unsent slip — "#code · Change N" and Print again — in en / ar / he
///    (RTL for ar / he), and none when every slip is on paper;
///  * Print again maps its outcome onto the existing kitchen-print snacks,
///    "still being sent" and the fetch failure;
///  * a NEWER edit from another till offers "Print latest" / "Cancel" — also
///    when the banner that was tapped is gone by the time the order is read;
///  * however many slips are unsent, the banner area stays bounded and the
///    menu grid keeps its height;
///  * the order's own row carries Print again for its newest unsent slip.

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

/// The slip clock, pinned to the day of every fixture below. The slip
/// controller retires a record older than the recent-orders window (the start
/// of yesterday), so an unpinned clock would retire these fixtures once the
/// real date moves two days past them.
final _now = DateTime.utc(2026, 10, 9, 12);

class _Details implements OrderDetailRepository {
  PosOrderDetail? current;
  Object? error;

  /// When set, every read waits for it (a slow network).
  Completer<void>? gate;

  @override
  Future<PosOrderDetail> fetch(String orderId) async {
    if (gate case final g?) await g.future;
    if (error case final e?) throw e;
    final d = current;
    if (d == null) {
      throw const PosOrderDetailException(
        PosOrderDetailFailure.notFound,
        'order_not_found',
      );
    }
    return d;
  }
}

class _Printer {
  final List<OrderChangeSlipView> slips = [];
  PosKitchenPrintOutcome outcome = PosKitchenPrintOutcome.printed;

  Future<PosKitchenPrintOutcome> call({
    required PosProviderReader read,
    required OrderChangeSlipView slip,
    required KitchenTicketPrintLabels labels,
    required KitchenChangeSlipLabels changeLabels,
  }) async {
    slips.add(slip);
    return outcome;
  }
}

/// A paper order (Burger ×2) whose edit [editNumber] is known.
PosOrderDetail _paper({int editNumber = 1}) {
  final d = detail(
    items: [
      detailItem(
        'oi-burger',
        menuItemId: 'mi-burger',
        name: 'Burger',
        quantity: 2,
        unit: 4000,
      ),
    ],
    channel: PosKitchenChannel.paper,
  );
  return PosOrderDetail(
    orderId: d.orderId,
    orderCode: d.orderCode,
    orderType: d.orderType,
    status: d.status,
    revision: d.revision + editNumber,
    currencyCode: d.currencyCode,
    subtotalMinor: d.subtotalMinor,
    discountTotalMinor: d.discountTotalMinor,
    taxTotalMinor: d.taxTotalMinor,
    grandTotalMinor: d.grandTotalMinor,
    items: d.items,
    rounds: d.rounds,
    tableLabel: d.tableLabel,
    kitchenChannel: d.kitchenChannel,
    branchFeatures: d.branchFeatures,
    editCount: editNumber,
    edits: [
      for (var n = 1; n <= editNumber; n++)
        PosOrderDetailEdit(
          orderEditId: 'edit-$n',
          editNumber: n,
          createdAt: DateTime.utc(2026, 10, 9, 11, n),
          reasonCode: 'entry_mistake',
        ),
    ],
  );
}

/// The stored slip of edit 1 ("Change 1"): the burger went from 1 to 2.
OrderEditSlipRecord _record({bool built = true}) => OrderEditSlipRecord(
  orderEditId: 'edit-1',
  orderId: 'order-1',
  orderCode: '#A1B2C3',
  editNumber: 1,
  dispatchId: 'dispatch-1',
  slip: built
      ? const OrderChangeSlipView(
          orderCode: '#A1B2C3',
          editNumber: 1,
          changes: [
            OrderChangeQuantity(
              was: KdsItemView(name: 'Burger', quantity: 1),
              nowQuantity: 2,
            ),
          ],
          orderNow: [KdsItemView(name: 'Burger', quantity: 2, linePosition: 1)],
        )
      : null,
  state: OrderEditSlipState.failed,
  attempts: 1,
  updatedAt: DateTime.utc(2026, 10, 9, 11, 2),
);

class _H {
  _H({List<OrderEditSlipRecord>? records}) {
    final initial = records ?? [_record()];
    store.persist('dev-1', {for (final r in initial) r.orderEditId: r});
    details.current = _paper();
    c = ProviderContainer(
      overrides: [
        posSyncSessionProvider.overrideWithValue(_session),
        orderEditSlipStoreProvider.overrideWithValue(store),
        orderDetailRepositoryProvider.overrideWithValue(details),
        posOrderEditSlipPrintProvider.overrideWithValue(printer.call),
        orderEditSlipClockProvider.overrideWithValue(() => _now),
      ],
    );
    addTearDown(c.dispose);
  }

  final InMemoryOrderEditSlipStore store = InMemoryOrderEditSlipStore();
  final _Details details = _Details();
  final _Printer printer = _Printer();
  late final ProviderContainer c;
}

Future<void> _pumpBanner(
  WidgetTester tester,
  _H h, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.c,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const Scaffold(body: OrderEditSlipBanner()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The real menu screen over [h], at [size].
Future<void> _pumpMenu(
  WidgetTester tester,
  _H h, {
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.c,
      child: MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosMenuScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// An unsent slip of order [n] ("#B0000n · Change 1").
OrderEditSlipRecord _other(int n) => OrderEditSlipRecord(
  orderEditId: 'edit-x$n',
  orderId: 'order-x$n',
  orderCode: '#B0000$n',
  editNumber: 1,
  updatedAt: DateTime.utc(2026, 10, 9, 11, 10 + n),
);

Future<AppLocalizations> _l10n([String code = 'en']) =>
    AppLocalizations.delegate.load(Locale(code));

Finder _key(String key) => find.byKey(Key(key));

void main() {
  group('the banner', () {
    for (final code in ['en', 'ar', 'he']) {
      testWidgets('$code: "not printed", the order and "Change N", Print '
          'again — on the menu screen', (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final l10n = await _l10n(code);
        final h = _H();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: h.c,
            child: MaterialApp(
              locale: Locale(code),
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              home: const PosMenuScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final banner = _key('order-edit-slip-banner-edit-1');
        expect(banner, findsOneWidget);
        expect(
          find.descendant(
            of: banner,
            matching: find.text(l10n.posOrderEditSlipNotPrinted),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: banner,
            matching: find.text('#A1B2C3 · ${l10n.kitchenEditChangeNumber(1)}'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _key('order-edit-slip-print-again-edit-1'),
            matching: find.text(l10n.posOrderEditPrintAgain),
          ),
          findsOneWidget,
        );
        expect(
          Directionality.of(tester.element(banner)),
          code == 'en' ? TextDirection.ltr : TextDirection.rtl,
        );

        await tester.tap(_key('order-edit-slip-print-again-edit-1'));
        await tester.pumpAndSettle();
        expect(h.printer.slips, hasLength(1));
        expect(find.text(l10n.posKitchenTicketPrintedSnack), findsOneWidget);
        expect(_key('order-edit-slip-banner-edit-1'), findsNothing);
      });
    }

    testWidgets('nothing unsent: no banner, the bare grid', (tester) async {
      final h = _H(records: const []);
      await _pumpBanner(tester, h);
      expect(_key('order-edit-slip-banners'), findsNothing);
    });

    testWidgets('one banner per unsent slip', (tester) async {
      final h = _H(
        records: [
          _record(),
          OrderEditSlipRecord(
            orderEditId: 'edit-9',
            orderId: 'order-9',
            orderCode: '#B00009',
            editNumber: 3,
            updatedAt: DateTime.utc(2026, 10, 9, 11, 3),
          ),
        ],
      );
      final l10n = await _l10n();
      await _pumpBanner(tester, h);
      expect(_key('order-edit-slip-banner-edit-1'), findsOneWidget);
      expect(_key('order-edit-slip-banner-edit-9'), findsOneWidget);
      expect(
        find.text('#B00009 · ${l10n.kitchenEditChangeNumber(3)}'),
        findsOneWidget,
      );
    });

    testWidgets('six unsent slips on a 1024x600 till: the banners scroll in '
        'a bounded area and the menu grid keeps its height', (tester) async {
      final h = _H(records: [for (var n = 1; n <= 6; n++) _other(n)]);
      await _pumpMenu(tester, h, size: const Size(1024, 600));
      expect(tester.takeException(), isNull);
      final area = tester.getSize(_key('order-edit-slip-banner-area')).height;
      final grid = tester.getSize(_key('pos-menu-scroll')).height;
      // The grid keeps most of the menu pane: never squeezed out.
      expect(grid, greaterThan(area));
      // Every slip is still reachable: the area scrolls to the last one.
      final last = _key('order-edit-slip-print-again-edit-x6');
      await tester.scrollUntilVisible(
        last,
        100,
        scrollable: find.descendant(
          of: _key('order-edit-slip-banner-area'),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Print again says what it came to', () {
    testWidgets('no printer / a failed send: the kitchen-print snacks, and '
        'the banner stays', (tester) async {
      final l10n = await _l10n();
      final h = _H();
      await _pumpBanner(tester, h);
      h.printer.outcome = PosKitchenPrintOutcome.noPrinterConfigured;
      await tester.tap(_key('order-edit-slip-print-again-edit-1'));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.posKitchenPrinterNotConfiguredSnack),
        findsOneWidget,
      );
      expect(_key('order-edit-slip-banner-edit-1'), findsOneWidget);

      ScaffoldMessenger.of(
        tester.element(_key('order-edit-slip-banners')),
      ).removeCurrentSnackBar();
      h.printer.outcome = PosKitchenPrintOutcome.failed;
      await tester.tap(_key('order-edit-slip-print-again-edit-1'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.posKitchenTicketPrintFailedSnack), findsOneWidget);
      expect(_key('order-edit-slip-banner-edit-1'), findsOneWidget);
    });

    testWidgets('the order cannot be re-read: the fetch-failed message, '
        'nothing printed', (tester) async {
      final l10n = await _l10n();
      final h = _H();
      h.details.error = StateError('offline');
      await _pumpBanner(tester, h);
      await tester.tap(_key('order-edit-slip-print-again-edit-1'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.posReprintKitchenFetchFailed), findsOneWidget);
      expect(h.printer.slips, isEmpty);
      expect(_key('order-edit-slip-banner-edit-1'), findsOneWidget);
    });

    testWidgets('a voided order: the slip is retired silently (D9)', (
      tester,
    ) async {
      final h = _H();
      final paper = _paper();
      h.details.current = PosOrderDetail(
        orderId: paper.orderId,
        orderCode: paper.orderCode,
        orderType: paper.orderType,
        status: 'voided',
        revision: paper.revision,
        currencyCode: paper.currencyCode,
        subtotalMinor: paper.subtotalMinor,
        discountTotalMinor: paper.discountTotalMinor,
        taxTotalMinor: paper.taxTotalMinor,
        grandTotalMinor: paper.grandTotalMinor,
        items: paper.items,
        rounds: paper.rounds,
        kitchenChannel: paper.kitchenChannel,
        editCount: paper.editCount,
        edits: paper.edits,
      );
      await _pumpBanner(tester, h);
      await tester.tap(_key('order-edit-slip-print-again-edit-1'));
      await tester.pumpAndSettle();
      expect(h.printer.slips, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(_key('order-edit-slip-banners'), findsNothing);
    });

    testWidgets('a NEWER edit from another till: "Print latest" prints the '
        'ORDER-NOW slip of the latest change; Cancel prints nothing', (
      tester,
    ) async {
      final l10n = await _l10n();
      final h = _H();
      h.details.current = _paper(editNumber: 2);
      await _pumpBanner(tester, h);
      await tester.tap(_key('order-edit-slip-print-again-edit-1'));
      await tester.pumpAndSettle();
      expect(_key('order-edit-newer-slip-offer'), findsOneWidget);
      expect(find.text(l10n.posOrderEditNewerSlipOffer), findsOneWidget);
      expect(find.text(l10n.posOrderEditPrintLatest), findsOneWidget);
      expect(find.text(l10n.adminCancel), findsOneWidget);
      // The older slip is retired already: its banner is gone.
      expect(_key('order-edit-slip-banners'), findsNothing);

      await tester.tap(_key('order-edit-newer-slip-print-latest'));
      await tester.pumpAndSettle();
      final slip = h.printer.slips.single;
      expect(slip.editNumber, 2);
      expect(slip.changes, isEmpty);
      expect(slip.orderNow.single.name, 'Burger');
      expect(find.text(l10n.posKitchenTicketPrintedSnack), findsOneWidget);
    });

    testWidgets('on the menu screen, the ONLY unsent slip and a NEWER edit '
        'from another till: its banner leaves while the order is re-read, '
        'and the "Print latest" offer still comes', (tester) async {
      final l10n = await _l10n();
      final h = _H();
      h.details.current = _paper(editNumber: 2);
      final read = h.details.gate = Completer<void>();
      await _pumpMenu(tester, h);
      await tester.tap(_key('order-edit-slip-print-again-edit-1'));
      await tester.pump();
      // Printing: the slip is no longer unsent, so its banner is gone.
      expect(_key('order-edit-slip-banners'), findsNothing);
      read.complete();
      await tester.pumpAndSettle();
      expect(_key('order-edit-newer-slip-offer'), findsOneWidget);

      await tester.tap(_key('order-edit-newer-slip-print-latest'));
      await tester.pumpAndSettle();
      expect(h.printer.slips.single.editNumber, 2);
      expect(find.text(l10n.posKitchenTicketPrintedSnack), findsOneWidget);
    });

    testWidgets('Cancel on the offer prints nothing', (tester) async {
      final h = _H();
      h.details.current = _paper(editNumber: 2);
      await _pumpBanner(tester, h);
      await tester.tap(_key('order-edit-slip-print-again-edit-1'));
      await tester.pumpAndSettle();
      await tester.tap(_key('order-edit-newer-slip-cancel'));
      await tester.pumpAndSettle();
      expect(h.printer.slips, isEmpty);
      expect(_key('order-edit-newer-slip-offer'), findsNothing);
    });

    testWidgets('an UNBUILT slip is built on demand and printed', (
      tester,
    ) async {
      final h = _H(records: [_record(built: false)]);
      await _pumpBanner(tester, h);
      await tester.tap(_key('order-edit-slip-print-again-edit-1'));
      await tester.pumpAndSettle();
      // No frozen inputs: the ORDER-NOW slip of THIS edit.
      final slip = h.printer.slips.single;
      expect(slip.editNumber, 1);
      expect(slip.orderNow.single.quantity, 2);
      expect(slip.staffFirstName, isNull);
    });
  });

  group('the order row', () {
    PosRecentOrder row({int editCount = 1}) {
      final at = DateTime.utc(2026, 10, 9, 11);
      return PosRecentOrder.discovered(
        PosOrderSnapshot(
          orderId: 'order-1',
          orderCode: '#A1B2C3',
          revision: 4,
          status: 'preparing',
          settlement: PosSettlement.unpaid,
          subtotalMinor: 8000,
          discountTotalMinor: 0,
          taxTotalMinor: 0,
          grandTotalMinor: 8000,
          createdAt: at,
          updatedAt: at,
          syncAt: at,
          editCount: editCount,
        ),
      );
    }

    const actions = PosOrderActions(
      canPay: false,
      canDiscount: false,
      canFullComp: false,
      canVoid: false,
      canMoveTable: false,
      canOpenReceipt: false,
      pendingKind: null,
    );

    Future<AppLocalizations> pumpRow(
      WidgetTester tester,
      _H h,
      PosRecentOrder order,
    ) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final l10n = await _l10n();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.c,
          child: MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              body: OrderActionRow(order: order, l10n: l10n, actions: actions),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return l10n;
    }

    testWidgets('an unsent slip of the order: Print again on the row, which '
        'prints it and then leaves', (tester) async {
      final h = _H();
      final l10n = await pumpRow(tester, h, row());
      final button = _key('recent-edit-slip-print-again-#A1B2C3');
      expect(button, findsOneWidget);
      expect(
        find.descendant(
          of: button,
          matching: find.text(l10n.posOrderEditPrintAgain),
        ),
        findsOneWidget,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(h.printer.slips, hasLength(1));
      expect(find.text(l10n.posKitchenTicketPrintedSnack), findsOneWidget);
      expect(button, findsNothing);
    });

    testWidgets('no unsent slip, or one the snapshot shows superseded: no '
        'button', (tester) async {
      await pumpRow(tester, _H(records: const []), row());
      expect(_key('recent-edit-slip-print-again-#A1B2C3'), findsNothing);
      await pumpRow(tester, _H(), row(editCount: 2));
      expect(_key('recent-edit-slip-print-again-#A1B2C3'), findsNothing);
    });
  });
}
