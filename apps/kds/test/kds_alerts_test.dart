import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/kds_screen.dart';
import 'package:restoflow_kds/src/widgets/kds_ticket_card.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KDS-ALERTS-AND-KITCHEN-COUNTS-002 (A): the per-card Reprint action and the
/// new-arrival attention glow.
Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

KdsTicketView _ticket(String id, {KitchenTicketStatus? status}) =>
    KdsTicketView(
      kitchenTicketId: id,
      stationId: 'grill',
      status: status ?? KitchenTicketStatus.newTicket,
      orderId: id,
      orderNumber: '#$id',
      items: const [KdsItemView(name: 'Burger', quantity: 1)],
    );

Widget _card(
  AppLocalizations l10n,
  KdsTicketView ticket, {
  VoidCallback? onReprint,
  bool highlightNew = false,
  bool disableAnimations = false,
}) => MaterialApp(
  localizationsDelegates: restoflowLocalizationsDelegates,
  supportedLocales: kSupportedLocales,
  theme: restoflowBaseTheme(brightness: Brightness.dark),
  // Inject the reduce-motion flag BELOW the app's MediaQuery so the alert's
  // accessibility branch (static outline, no animation) is exercised.
  builder: (context, child) => disableAnimations
      ? MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        )
      : child!,
  home: Scaffold(
    body: SizedBox(
      width: 460,
      child: KdsTicketCard(
        ticket: ticket,
        l10n: l10n,
        now: DateTime(2026, 7, 9, 12),
        onAdvance: (_) {},
        onRecall: null,
        onReprint: onReprint,
        highlightNew: highlightNew,
        newArrivalWindow: const Duration(milliseconds: 120),
      ),
    ),
  ),
);

Widget _screen(
  List<KdsTicketView> tickets, {
  bool enableAlert = true,
  Duration window = const Duration(milliseconds: 120),
}) => MaterialApp(
  localizationsDelegates: restoflowLocalizationsDelegates,
  supportedLocales: kSupportedLocales,
  theme: restoflowBaseTheme(brightness: Brightness.dark),
  home: KdsScreen(
    tickets: tickets,
    allowRecall: false,
    enableNewArrivalAlert: enableAlert,
    newArrivalWindow: window,
  ),
);

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('A1 per-card reprint', () {
    testWidgets('shows a Reprint control and calls onReprint when tapped', (
      tester,
    ) async {
      final l10n = await _en();
      var reprints = 0;
      await tester.pumpWidget(
        _card(l10n, _ticket('o1'), onReprint: () => reprints++),
      );
      await tester.pumpAndSettle();

      final btn = find.byKey(const Key('kds-reprint-o1'));
      expect(btn, findsOneWidget);
      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(reprints, 1);
      // No money anywhere on the card.
      expect(find.textContaining('₪'), findsNothing);
    });

    testWidgets('hides the Reprint control when onReprint is null', (
      tester,
    ) async {
      final l10n = await _en();
      await tester.pumpWidget(_card(l10n, _ticket('o1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kds-reprint-o1')), findsNothing);
    });
  });

  group('A2 new-arrival alert', () {
    testWidgets('a card renders the glow when highlightNew is true, not when '
        'false', (tester) async {
      final l10n = await _en();
      await tester.pumpWidget(_card(l10n, _ticket('o1'), highlightNew: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kds-new-arrival-o1')), findsOneWidget);

      await tester.pumpWidget(_card(l10n, _ticket('o1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kds-new-arrival-o1')), findsNothing);
    });

    testWidgets('a ticket present on FIRST load does NOT blink', (
      tester,
    ) async {
      _wide(tester);
      await tester.pumpWidget(_screen([_ticket('o1')]));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kds-new-arrival-o1')), findsNothing);
    });

    testWidgets('a ticket that ARRIVES later IS highlighted', (tester) async {
      _wide(tester);
      // First build: no tickets (initializes the tracker).
      await tester.pumpWidget(_screen(const []));
      await tester.pumpAndSettle();
      // A new order arrives on a later build -> highlighted.
      await tester.pumpWidget(_screen([_ticket('o2')]));
      await tester.pump(); // let the arrival register
      expect(find.byKey(const Key('kds-new-arrival-o2')), findsOneWidget);
      await tester.pumpAndSettle(); // let the finite glow self-terminate
    });

    testWidgets('the glow STOPS on acknowledge', (tester) async {
      _wide(tester);
      final l10n = await _en();
      await tester.pumpWidget(_screen(const []));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_screen([_ticket('o3')]));
      await tester.pump();
      expect(find.byKey(const Key('kds-new-arrival-o3')), findsOneWidget);

      // Acknowledge -> leaves the "new" column -> glow removed.
      await tester.tap(find.text(l10n.kdsAcknowledgeAction));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kds-new-arrival-o3')), findsNothing);
    });

    testWidgets('a zero window highlights nothing (window gates the timeout)', (
      tester,
    ) async {
      _wide(tester);
      await tester.pumpWidget(_screen(const [], window: Duration.zero));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_screen([_ticket('o4')], window: Duration.zero));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kds-new-arrival-o4')), findsNothing);
    });
  });

  // ---- TABLET-UX-001 (C): the STRONGER, more noticeable new-order alert. ----
  group('C stronger new-order alert', () {
    testWidgets('a highlighted card shows a loud "New order" badge; a '
        'non-highlighted one does not — and it stays readable + money-free', (
      tester,
    ) async {
      final l10n = await _en();
      await tester.pumpWidget(_card(l10n, _ticket('o1'), highlightNew: true));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('kds-new-badge-o1')), findsOneWidget);
      expect(find.text(l10n.kdsNewOrderBadge), findsOneWidget);
      // The order content stays present/readable, and no money leaks (T-003).
      expect(find.text('Burger ×1'), findsOneWidget);
      expect(find.textContaining('₪'), findsNothing);

      await tester.pumpWidget(_card(l10n, _ticket('o1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kds-new-badge-o1')), findsNothing);
      expect(find.text(l10n.kdsNewOrderBadge), findsNothing);
    });

    testWidgets('reduce-motion still shows a static, visible alert (highlight '
        'wrapper + badge), with no animation exception', (tester) async {
      final l10n = await _en();
      await tester.pumpWidget(
        _card(l10n, _ticket('o1'), highlightNew: true, disableAnimations: true),
      );
      await tester.pumpAndSettle();

      // The alert is still present (the accessibility branch renders a static
      // outline) and unmistakable via the badge — no infinite animation hang.
      expect(find.byKey(const Key('kds-new-arrival-o1')), findsOneWidget);
      expect(find.byKey(const Key('kds-new-badge-o1')), findsOneWidget);
      expect(find.text('Burger ×1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('on the board the badge appears on arrival and clears on '
        'acknowledge', (tester) async {
      _wide(tester);
      final l10n = await _en();
      await tester.pumpWidget(_screen(const []));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_screen([_ticket('o5')]));
      await tester.pump();
      expect(find.byKey(const Key('kds-new-badge-o5')), findsOneWidget);

      await tester.tap(find.text(l10n.kdsAcknowledgeAction));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kds-new-badge-o5')), findsNothing);
    });
  });
}
