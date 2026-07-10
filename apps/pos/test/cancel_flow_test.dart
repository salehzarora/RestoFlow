import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/void_repository.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/state/void_controller.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';

/// MONEY-VOID-001: the POS cancel (void) flow for a WRONG UNPAID order. An
/// unpaid card offers Cancel; the confirm sheet requires a reason and pushes the
/// server-authoritative void via [VoidRepository]; success marks the order
/// cancelled locally (drops off the unpaid list, no pay/reprint); a server
/// refusal is surfaced honestly and the order is left untouched. Money-free.
Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

SubmittedOrderView _view(String number) => SubmittedOrderView(
  orderNumber: number,
  orderType: OrderType.takeaway,
  currencyCode: 'ILS',
  subtotalMinor: 4200,
  orderId: 'oid-$number',
  lines: [
    SubmittedLineView(
      name: 'Burger',
      quantity: 1,
      lineTotalMinor: 4200,
      currencyCode: 'ILS',
    ),
  ],
);

Future<InMemoryRecentOrdersStore> _seededStore() async {
  final store = InMemoryRecentOrdersStore();
  await store.persist('demo-device', [
    PosRecentOrder(order: _view('#U1'), submittedAt: DateTime.now()),
  ]);
  return store;
}

/// A test double for [VoidRepository] that records the calls and, optionally,
/// fails with a typed [VoidException] or blocks until released.
class _FakeVoidRepo implements VoidRepository {
  _FakeVoidRepo({this.error, this.gate});
  final VoidException? error;
  final Future<void>? gate;
  int calls = 0;
  final List<String> orderIds = <String>[];
  final List<String> reasons = <String>[];

  @override
  Future<void> voidOrder({
    required String orderId,
    required String reason,
    int? expectedRevision,
  }) async {
    calls++;
    orderIds.add(orderId);
    reasons.add(reason);
    if (gate != null) await gate;
    if (error != null) throw error!;
  }
}

Widget _wrap(
  InMemoryRecentOrdersStore store,
  _FakeVoidRepo repo, {
  Locale locale = const Locale('en'),
}) => ProviderScope(
  overrides: [
    posRecentOrdersStoreProvider.overrideWithValue(store),
    voidRepositoryProvider.overrideWithValue(repo),
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: const Scaffold(body: RecentOrdersSheet()),
  ),
);

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('an unpaid order offers Cancel; confirm cancels it', (
    tester,
  ) async {
    _wide(tester);
    final l10n = await _en();
    final repo = _FakeVoidRepo();
    await tester.pumpWidget(_wrap(await _seededStore(), repo));
    await tester.pumpAndSettle();

    // Unpaid order shows both Take payment and Cancel.
    expect(find.byKey(const Key('recent-pay-#U1')), findsOneWidget);
    expect(find.byKey(const Key('recent-cancel-#U1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('recent-cancel-#U1')));
    await tester.pumpAndSettle();
    // The confirmation sheet: warning banner + reason field + confirm.
    expect(find.byKey(const Key('cancel-order-warning')), findsOneWidget);
    expect(find.text(l10n.posCancelOrderWarning), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('cancel-reason-field')),
      'wrong table',
    );
    await tester.tap(find.byKey(const Key('cancel-confirm-button')));
    await tester.pumpAndSettle();

    // The server-authoritative void was pushed exactly once, with the reason.
    expect(repo.calls, 1);
    expect(repo.orderIds.single, 'oid-#U1');
    expect(repo.reasons.single, 'wrong table');
    // The sheet closed; a success snackbar shows.
    expect(find.byKey(const Key('cancel-order-sheet')), findsNothing);
    expect(find.text(l10n.posOrderCancelledSnack), findsOneWidget);

    // The order is now Cancelled: pill shown, no pay/cancel actions.
    expect(find.byKey(const Key('recent-cancelled-#U1')), findsOneWidget);
    expect(find.byKey(const Key('recent-pay-#U1')), findsNothing);
    expect(find.byKey(const Key('recent-cancel-#U1')), findsNothing);
  });

  testWidgets('an empty reason is rejected before any backend call', (
    tester,
  ) async {
    _wide(tester);
    final l10n = await _en();
    final repo = _FakeVoidRepo();
    await tester.pumpWidget(_wrap(await _seededStore(), repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('recent-cancel-#U1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-confirm-button')));
    await tester.pumpAndSettle();

    expect(repo.calls, 0);
    expect(find.text(l10n.posCancellationReasonRequired), findsOneWidget);
    // The order is untouched.
    expect(find.byKey(const Key('recent-cancelled-#U1')), findsNothing);
  });

  testWidgets(
    'a server permission refusal is surfaced; the order is left unpaid',
    (tester) async {
      _wide(tester);
      final l10n = await _en();
      final repo = _FakeVoidRepo(
        error: const VoidException('denied', permissionDenied: true),
      );
      await tester.pumpWidget(_wrap(await _seededStore(), repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recent-cancel-#U1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('cancel-reason-field')),
        'mistake',
      );
      await tester.tap(find.byKey(const Key('cancel-confirm-button')));
      await tester.pumpAndSettle();

      // Honest inline error; the sheet stays open; the order is NOT cancelled.
      expect(find.text(l10n.posCancelPermissionDenied), findsOneWidget);
      expect(find.byKey(const Key('cancel-order-sheet')), findsOneWidget);
      expect(repo.calls, 1);
    },
  );

  testWidgets('a paid-order refusal shows the paid message', (tester) async {
    _wide(tester);
    final l10n = await _en();
    final repo = _FakeVoidRepo(
      error: const VoidException('paid', alreadyPaid: true),
    );
    await tester.pumpWidget(_wrap(await _seededStore(), repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('recent-cancel-#U1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('cancel-reason-field')),
      'oops',
    );
    await tester.tap(find.byKey(const Key('cancel-confirm-button')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.posCancelPaidOrderError), findsOneWidget);
  });

  testWidgets('a double tap on confirm pushes the void only once', (
    tester,
  ) async {
    _wide(tester);
    final completer = Completer<void>();
    final repo = _FakeVoidRepo(gate: completer.future);
    await tester.pumpWidget(_wrap(await _seededStore(), repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('recent-cancel-#U1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cancel-reason-field')), 'dup');
    // Two taps before the in-flight void resolves.
    await tester.tap(find.byKey(const Key('cancel-confirm-button')));
    await tester.tap(find.byKey(const Key('cancel-confirm-button')));
    await tester.pump();
    completer.complete();
    await tester.pumpAndSettle();

    expect(repo.calls, 1);
  });

  testWidgets('renders in Arabic (RTL) without crashing', (tester) async {
    _wide(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
    final repo = _FakeVoidRepo();
    await tester.pumpWidget(
      _wrap(await _seededStore(), repo, locale: const Locale('ar')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('recent-cancel-#U1')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.posCancelOrderWarning), findsOneWidget);
    expect(find.byKey(const Key('cancel-confirm-button')), findsOneWidget);
  });
}
