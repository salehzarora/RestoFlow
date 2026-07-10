import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/data/kitchen_order.dart';
import 'package:restoflow_kds/src/widgets/kds_board.dart';
import 'package:restoflow_kds/src/widgets/kitchen_board.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KDS-FIFO-001: every column — live and demo — shows tickets OLDEST-first, so
/// the chef can trust the top card is the next to make. Verified positionally
/// (top-to-bottom card order), independent of the ticket id.

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void _useSurface(WidgetTester tester) {
  // Wide enough that all four columns fill the width, tall enough that a
  // column's cards all lay out on-screen (so getTopLeft is meaningful).
  tester.view.physicalSize = const Size(1500, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

DateTime _at(int h, int m) => DateTime.utc(2026, 7, 5, h, m);

KdsTicketView _live(
  String id,
  KitchenTicketStatus status,
  DateTime? submittedAt,
) => KdsTicketView(
  kitchenTicketId: id,
  stationId: 'grill',
  status: status,
  submittedAt: submittedAt,
  items: const [KdsItemView(name: 'Burger', quantity: 1)],
);

double _cardTop(WidgetTester tester, String id) =>
    tester.getTopLeft(find.byKey(ValueKey('kds-card-$id'))).dy;

KitchenOrderTicket _demo(
  String id,
  KitchenTicketStatus status,
  DateTime submittedAt,
) => KitchenOrderTicket(
  ticketId: id,
  orderNumber: id,
  orderType: OrderType.takeaway,
  tableLabel: null,
  stationId: 'grill',
  submittedAt: submittedAt,
  status: status,
  items: const [KitchenOrderItem(name: 'Burger', quantity: 1)],
);

double _demoCardTop(WidgetTester tester, String id) =>
    tester.getTopLeft(find.byKey(Key('kitchen-card-$id'))).dy;

void main() {
  testWidgets('LIVE board: New and Ready columns render oldest-first '
      '(by submitted time, not id)', (tester) async {
    _useSurface(tester);
    final l10n = await _en();

    // Ids chosen so alphabetical order is the REVERSE of arrival order.
    final tickets = [
      _live('n-a:grill', KitchenTicketStatus.newTicket, _at(10, 20)), // newest
      _live('n-z:grill', KitchenTicketStatus.newTicket, _at(10, 0)), // oldest
      _live('n-m:grill', KitchenTicketStatus.newTicket, _at(10, 10)),
      _live('r-a:grill', KitchenTicketStatus.ready, _at(10, 5)),
      _live('r-b:grill', KitchenTicketStatus.ready, _at(9, 55)), // older
    ];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: KdsBoard(
            tickets: tickets,
            l10n: l10n,
            onAdvance: (_, _) {},
            onRecall: null,
            onReprint: (_) {},
            newArrivalIds: const {'n-a:grill'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // New column: oldest (10:00) at top, newest (10:20) at bottom.
    expect(
      _cardTop(tester, 'n-z:grill'),
      lessThan(_cardTop(tester, 'n-m:grill')),
    );
    expect(
      _cardTop(tester, 'n-m:grill'),
      lessThan(_cardTop(tester, 'n-a:grill')),
    );

    // Ready column also oldest-first.
    expect(
      _cardTop(tester, 'r-b:grill'),
      lessThan(_cardTop(tester, 'r-a:grill')),
    );

    // Preserved: money-free, per-card reprint present, new-order alert still
    // fires for a freshly-arrived ticket.
    expect(find.textContaining('₪'), findsNothing);
    expect(find.byKey(const Key('kds-reprint-n-z:grill')), findsOneWidget);
    expect(find.byKey(const Key('kds-new-badge-n-a:grill')), findsOneWidget);
  });

  testWidgets('LIVE board: an undated ticket sorts below dated ones', (
    tester,
  ) async {
    _useSurface(tester);
    final l10n = await _en();

    final tickets = [
      _live('u:grill', KitchenTicketStatus.newTicket, null), // no timestamp
      _live('d1:grill', KitchenTicketStatus.newTicket, _at(10, 0)),
      _live('d2:grill', KitchenTicketStatus.newTicket, _at(10, 30)),
    ];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: KdsBoard(
            tickets: tickets,
            l10n: l10n,
            onAdvance: (_, _) {},
            onRecall: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Dated tickets oldest-first, the undated one last — never above a known age.
    expect(
      _cardTop(tester, 'd1:grill'),
      lessThan(_cardTop(tester, 'd2:grill')),
    );
    expect(_cardTop(tester, 'd2:grill'), lessThan(_cardTop(tester, 'u:grill')));
  });

  testWidgets('DEMO board: the New column renders oldest-first', (
    tester,
  ) async {
    _useSurface(tester);

    final tickets = [
      // Deliberately NOT in FIFO order in the source list.
      _demo('K-new', KitchenTicketStatus.newTicket, _at(10, 20)), // newest
      _demo('K-old', KitchenTicketStatus.newTicket, _at(10, 0)), // oldest
      _demo('K-mid', KitchenTicketStatus.newTicket, _at(10, 10)),
    ];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: KitchenBoard(
            tickets: tickets,
            now: _at(10, 25),
            onStart: (_) {},
            onMarkReady: (_) {},
            onComplete: (_) {},
            onRecall: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      _demoCardTop(tester, 'K-old'),
      lessThan(_demoCardTop(tester, 'K-mid')),
    );
    expect(
      _demoCardTop(tester, 'K-mid'),
      lessThan(_demoCardTop(tester, 'K-new')),
    );
    // Demo board is money-free too.
    expect(find.textContaining('₪'), findsNothing);
  });
}
