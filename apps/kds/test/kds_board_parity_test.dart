import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/data/kitchen_order.dart';
import 'package:restoflow_kds/src/widgets/kds_board.dart';
import 'package:restoflow_kds/src/widgets/kitchen_order_card.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// DESIGN-001 demo/live board parity:
///  * both boards fill the width on big kitchen TVs (all 4 columns fit at
///    their 340px minimum) and keep the fixed-width horizontal scroll below
///    that — including every previously tested viewport;
///  * both cards dim cleared (bumped) work the same way.
Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void _useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

KdsTicketView _liveTicket() => KdsTicketView(
  kitchenTicketId: 'o1:grill',
  stationId: 'grill',
  status: KitchenTicketStatus.ready,
  items: [const KdsItemView(name: 'Burger', quantity: 2)],
);

Widget _liveBoard(AppLocalizations l10n) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: restoflowLocalizationsDelegates,
  supportedLocales: kSupportedLocales,
  home: Scaffold(
    body: KdsBoard(
      tickets: [_liveTicket()],
      l10n: l10n,
      onAdvance: (_, _) {},
      onRecall: null,
    ),
  ),
);

bool _hasHorizontalScroller(WidgetTester tester) => tester
    .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
    .any((s) => s.scrollDirection == Axis.horizontal);

void main() {
  testWidgets('live board: fixed-width scroll at 1400, fills at 1600', (
    tester,
  ) async {
    final l10n = await _en();

    _useSurface(tester, const Size(1400, 900));
    await tester.pumpWidget(_liveBoard(l10n));
    await tester.pumpAndSettle();
    // 4 × (340 + 12) + 12 = 1420 > 1400 — the original scroll path.
    expect(_hasHorizontalScroller(tester), isTrue);
    expect(find.byKey(const Key('kds-col-new')), findsOneWidget);

    _useSurface(tester, const Size(1600, 900));
    await tester.pumpWidget(_liveBoard(l10n));
    await tester.pumpAndSettle();
    // Big TV: columns grow to fill; no horizontal scroller.
    expect(_hasHorizontalScroller(tester), isFalse);
    for (final key in ['new', 'preparing', 'ready', 'cleared']) {
      expect(find.byKey(Key('kds-col-$key')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('demo card dims bumped work exactly like the live card', (
    tester,
  ) async {
    KitchenOrderTicket ticket(KitchenTicketStatus status) => KitchenOrderTicket(
      ticketId: 'K-9001',
      orderNumber: 'DEMO-9001',
      orderType: OrderType.takeaway,
      tableLabel: null,
      stationId: null,
      submittedAt: DateTime(2026, 7, 5, 11, 58),
      items: const [KitchenOrderItem(name: 'Burger', quantity: 1)],
      status: status,
    );

    Widget harness(KitchenTicketStatus status) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 420,
          child: KitchenOrderCard(
            ticket: ticket(status),
            now: DateTime(2026, 7, 5, 12, 0),
            onStart: () {},
            onMarkReady: () {},
            onComplete: () {},
            onRecall: () {},
          ),
        ),
      ),
    );

    bool dimmed() => tester
        .widgetList<Opacity>(find.byType(Opacity))
        .any((w) => w.opacity == 0.62);

    await tester.pumpWidget(harness(KitchenTicketStatus.bumped));
    await tester.pumpAndSettle();
    expect(dimmed(), isTrue);

    await tester.pumpWidget(harness(KitchenTicketStatus.ready));
    await tester.pumpAndSettle();
    expect(dimmed(), isFalse);
    expect(tester.takeException(), isNull);
  });
}
