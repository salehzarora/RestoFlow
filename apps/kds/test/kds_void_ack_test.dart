import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_kds/src/kds_screen.dart';

/// PSC-001D — the red cancellation card and its acknowledgement surfaces,
/// through the production KdsScreen -> KdsBoard -> KdsTicketCard path.

KdsTicketView _cancelled(
  String orderId, {
  String from = 'preparing',
  DateTime? voidedAt,
}) => KdsTicketView(
  kitchenTicketId: '$orderId:unassigned',
  stationId: 'unassigned',
  orderId: orderId,
  orderNumber: '#ABC123',
  orderType: 'takeaway',
  status: KitchenTicketStatus.cancelled,
  submittedAt: DateTime.utc(2026, 7, 21, 10),
  voidedAt: voidedAt ?? DateTime.utc(2026, 7, 21, 10, 5),
  voidedFromStatus: from,
  items: [const KdsItemView(name: 'Burger', quantity: 2)],
);

KdsTicketView _active(String orderId) => KdsTicketView(
  kitchenTicketId: '$orderId:unassigned',
  stationId: 'unassigned',
  orderId: orderId,
  orderNumber: '#DEF456',
  orderType: 'takeaway',
  status: KitchenTicketStatus.inPreparation,
  submittedAt: DateTime.utc(2026, 7, 21, 9, 55),
  items: [const KdsItemView(name: 'Wrap', quantity: 1)],
);

Future<AppLocalizations> _l10n([String locale = 'en']) =>
    AppLocalizations.delegate.load(Locale(locale));

Future<void> _pump(
  WidgetTester tester, {
  required List<KdsTicketView> tickets,
  void Function(KdsTicketView)? onAck,
  Set<String> pending = const <String>{},
  Set<String> failed = const <String>{},
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: KdsScreen(
        tickets: tickets,
        allowRecall: false,
        onAcknowledgeCancellation: onAck,
        ackPendingOrderIds: pending,
        ackFailedOrderIds: failed,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a pending-ack cancellation renders the red card: banner, canceled time, '
    'item summary, ONE acknowledge action, NO progression actions',
    (tester) async {
      final l10n = await _l10n();
      await _pump(tester, tickets: [_cancelled('o1')], onAck: (_) {});
      expect(
        find.byKey(const Key('kds-cancelled-banner-o1:unassigned')),
        findsOneWidget,
      );
      expect(find.text(l10n.kdsCancelledCardTitle), findsOneWidget);
      expect(find.text(l10n.kdsCancelledCardBody), findsOneWidget);
      expect(find.byKey(const Key('kds-cancelled-at')), findsOneWidget);
      // The safe item summary stays visible.
      expect(find.text('Burger ×2'), findsOneWidget);
      // Exactly one acknowledgement action; no kitchen progression buttons.
      expect(find.byKey(const Key('kds-ack-o1:unassigned')), findsOneWidget);
      expect(find.text(l10n.kdsAcknowledgeCancellation), findsOneWidget);
      expect(find.text(l10n.kdsAcknowledgeAction), findsNothing);
      expect(find.text(l10n.kdsStartAction), findsNothing);
      expect(find.text(l10n.kdsReadyAction), findsNothing);
    },
  );

  testWidgets('the card is placed by voided_from_status (locked columns)', (
    tester,
  ) async {
    // The WIDE board (side-by-side Row columns) inflates every column; the
    // narrow stacked ListView is lazy and would not build off-screen columns.
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(
      tester,
      tickets: [
        _cancelled('o1', from: 'submitted'),
        _cancelled('o2', from: 'preparing'),
        _cancelled('o3', from: 'ready'),
      ],
      onAck: (_) {},
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('kds-col-new')),
        matching: find.byKey(const ValueKey('kds-card-o1:unassigned')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('kds-col-preparing')),
        matching: find.byKey(const ValueKey('kds-card-o2:unassigned')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('kds-col-ready')),
        matching: find.byKey(const ValueKey('kds-card-o3:unassigned')),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'tapping Acknowledge fires ONCE; a pending ack disables the button and '
    'keeps the card visible',
    (tester) async {
      final l10n = await _l10n();
      final acked = <String>[];
      await _pump(
        tester,
        tickets: [_cancelled('o1')],
        onAck: (t) => acked.add(t.orderId!),
      );
      await tester.tap(find.byKey(const Key('kds-ack-o1:unassigned')));
      await tester.pumpAndSettle();
      expect(acked, ['o1']);

      // Re-pump as the LIVE board would after the controller marks it pending.
      await _pump(
        tester,
        tickets: [_cancelled('o1')],
        onAck: (t) => acked.add(t.orderId!),
        pending: {'o1'},
      );
      // The card is STILL there (never hidden before the authoritative pull)…
      expect(
        find.byKey(const Key('kds-cancelled-banner-o1:unassigned')),
        findsOneWidget,
      );
      expect(find.text(l10n.kdsAckPending), findsOneWidget);
      // …and the disabled button blocks duplicate taps.
      await tester.tap(
        find.byKey(const Key('kds-ack-o1:unassigned')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(acked, ['o1']);
    },
  );

  testWidgets(
    'a failed ack keeps the card, shows the failure, stays retryable',
    (tester) async {
      final l10n = await _l10n();
      final acked = <String>[];
      await _pump(
        tester,
        tickets: [_cancelled('o1')],
        onAck: (t) => acked.add(t.orderId!),
        failed: {'o1'},
      );
      expect(
        find.byKey(const Key('kds-ack-failed-o1:unassigned')),
        findsOneWidget,
      );
      expect(find.text(l10n.kdsAckFailed), findsOneWidget);
      // Retry is possible: the button is live again.
      await tester.tap(find.byKey(const Key('kds-ack-o1:unassigned')));
      await tester.pumpAndSettle();
      expect(acked, ['o1']);
    },
  );

  testWidgets('without a live controller no acknowledge button is rendered '
      '(demo boards get no dead control)', (tester) async {
    await _pump(tester, tickets: [_cancelled('o1')]);
    expect(find.byKey(const Key('kds-ack-o1:unassigned')), findsNothing);
    // The red banner still informs.
    expect(
      find.byKey(const Key('kds-cancelled-banner-o1:unassigned')),
      findsOneWidget,
    );
  });

  testWidgets(
    'a cancellation ARRIVING after first build gets the finite danger pulse; '
    'cards present on load do not pulse',
    (tester) async {
      final l10n = await _l10n();
      // enableNewArrivalAlert drives both alerts on the live board.
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: KdsScreen(
            tickets: [_cancelled('o1')],
            allowRecall: false,
            enableNewArrivalAlert: true,
            onAcknowledgeCancellation: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Present on FIRST build: no pulse.
      expect(
        find.byKey(const Key('kds-cancel-arrival-o1:unassigned')),
        findsNothing,
      );
      expect(l10n.kdsCancelledCardTitle, isNotEmpty);
      // A SECOND cancellation arrives later -> it pulses (finite, settles).
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: KdsScreen(
            tickets: [
              _cancelled('o1'),
              _cancelled('o2', from: 'ready'),
            ],
            allowRecall: false,
            enableNewArrivalAlert: true,
            onAcknowledgeCancellation: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('kds-cancel-arrival-o2:unassigned')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('kds-cancel-arrival-o1:unassigned')),
        findsNothing,
      );
      // FINITE: the pulse self-terminates, so the tree settles.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );

  testWidgets('normal active tickets are unaffected next to a cancellation', (
    tester,
  ) async {
    final l10n = await _l10n();
    await _pump(
      tester,
      tickets: [_active('o9'), _cancelled('o1')],
      onAck: (_) {},
    );
    // The active card keeps its normal progression action.
    expect(find.text(l10n.kdsReadyAction), findsOneWidget);
    // And carries NO acknowledgement control.
    expect(find.byKey(const Key('kds-ack-o9:unassigned')), findsNothing);
  });

  testWidgets('Arabic renders the cancellation card under RTL', (tester) async {
    final ar = await _l10n('ar');
    await _pump(
      tester,
      tickets: [_cancelled('o1')],
      onAck: (_) {},
      locale: const Locale('ar'),
    );
    expect(find.text(ar.kdsCancelledCardTitle), findsOneWidget);
    expect(find.text(ar.kdsAcknowledgeCancellation), findsOneWidget);
    final banner = find.byKey(const Key('kds-cancelled-banner-o1:unassigned'));
    expect(Directionality.of(tester.element(banner)), TextDirection.rtl);
  });
}
