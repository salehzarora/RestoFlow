import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/kitchen_print.dart' as shared;
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/kds_screen.dart';
import 'package:restoflow_kds/src/print/kds_ticket_document.dart';
import 'package:restoflow_kds/src/state/kds_status_pusher.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// PSC-001C — service-round surfaces on the KDS app:
///  * a ROUND ticket's card announces "Addition · Round N";
///  * card actions on a round ticket dispatch `order.round_status` with the
///    ROUND id as the canonical target (never the parent `order.status`);
///  * the original ticket keeps dispatching `order.status` unchanged.
///
/// ORDER-EDIT-001D (O-6): a round OPENED by a sent-order edit prints "Change N
/// · Round M" on the KDS paper (the KDS label adapter now carries
/// `changeNumberLabel`, exactly like the shared adapter); a plain addition
/// round still prints "Addition · Round M".

class _FakeTransport implements SyncRpcTransport {
  final List<(String, Map<String, dynamic>)> calls = [];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return {'ok': true, 'results': <Object?>[]};
  }
}

KdsTicketView _ticket({
  String? roundId,
  int? roundNumber,
  int? openedByEditNumber,
}) => KdsTicketView(
  kitchenTicketId: roundId == null
      ? 'o1:unassigned'
      : 'o1:unassigned:r$roundId',
  stationId: 'unassigned',
  orderId: 'o1',
  orderNumber: '#ABC123',
  orderType: 'dine_in',
  tableLabel: 'T1',
  status: KitchenTicketStatus.newTicket,
  submittedAt: DateTime.utc(2026, 7, 22, 10),
  items: [const KdsItemView(name: 'Fries', quantity: 1)],
  roundId: roundId,
  roundNumber: roundNumber,
  openedByEditNumber: openedByEditNumber,
);

List<String> _texts(KdsTicketView ticket, AppLocalizations l10n) => [
  for (final line in buildKdsTicketDocument(l10n, ticket).lines)
    line.left ?? '',
];

void main() {
  test(
    'a ROUND ticket advance dispatches order.round_status (round target)',
    () async {
      final transport = _FakeTransport();
      final pusher = KdsStatusPusher(
        transport: transport,
        session: const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
        generateOperationId: () => 'op-1',
      );
      final ok = await pusher.push(
        _ticket(roundId: 'r1', roundNumber: 2),
        KitchenTicketStatus.acknowledged,
      );
      expect(ok, isTrue);
      final op =
          (transport.calls.single.$2['p_operations'] as List).single as Map;
      expect(op['operation_type'], 'order.round_status');
      expect(op['target_entity'], 'order_service_round');
      expect(op['target_id'], 'r1');
      expect((op['payload'] as Map)['round_id'], 'r1');
      expect((op['payload'] as Map)['new_status'], 'accepted');
      expect((op['payload'] as Map).containsKey('order_id'), isFalse);
    },
  );

  test(
    'the ORIGINAL ticket keeps dispatching order.status unchanged',
    () async {
      final transport = _FakeTransport();
      final pusher = KdsStatusPusher(
        transport: transport,
        session: const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
        generateOperationId: () => 'op-1',
      );
      await pusher.push(_ticket(), KitchenTicketStatus.ready);
      final op =
          (transport.calls.single.$2['p_operations'] as List).single as Map;
      expect(op['operation_type'], 'order.status');
      expect(op['target_id'], 'o1');
      expect((op['payload'] as Map)['order_id'], 'o1');
      expect((op['payload'] as Map)['new_status'], 'ready');
    },
  );

  testWidgets('a round card announces "Addition · Round N"; the original card '
      'does not', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: KdsScreen(
          tickets: [
            _ticket(),
            _ticket(roundId: 'r1', roundNumber: 2),
          ],
          allowRecall: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('kds-round-o1:unassigned:rr1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('kds-round-o1:unassigned')), findsNothing);
    expect(
      find.text('${l10n.kdsAdditionLabel} · ${l10n.kdsRoundLabel(2)}'),
      findsOneWidget,
    );
  });

  testWidgets('Arabic renders the round label under RTL', (tester) async {
    final ar = await AppLocalizations.delegate.load(const Locale('ar'));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: KdsScreen(
          tickets: [_ticket(roundId: 'r1', roundNumber: 2)],
          allowRecall: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('${ar.kdsAdditionLabel} · ${ar.kdsRoundLabel(2)}'),
      findsOneWidget,
    );
  });

  group('ORDER-EDIT-001D (O-6): the KDS paper of an edit-opened round', () {
    for (final code in const ['en', 'ar', 'he']) {
      test(
        '$code: prints "Change 2 · Round 3", never the addition word',
        () async {
          final l10n = await AppLocalizations.delegate.load(Locale(code));
          final texts = _texts(
            _ticket(roundId: 'r3', roundNumber: 3, openedByEditNumber: 2),
            l10n,
          );
          expect(
            texts,
            contains(
              '${l10n.kitchenEditChangeNumber(2)} · ${l10n.kdsRoundLabel(3)}',
            ),
          );
          expect(
            texts.where((t) => t.contains(l10n.kdsAdditionLabel)),
            isEmpty,
          );
          // The ORIGINAL order code still sits above the marker.
          expect(texts, contains('#ABC123'));
        },
      );

      test('$code: a plain addition round still prints "Addition · Round 3"; '
          'the original ticket prints neither marker', () async {
        final l10n = await AppLocalizations.delegate.load(Locale(code));
        final round = _texts(_ticket(roundId: 'r3', roundNumber: 3), l10n);
        expect(
          round,
          contains('${l10n.kdsAdditionLabel} · ${l10n.kdsRoundLabel(3)}'),
        );
        expect(
          round.where((t) => t.contains(l10n.kitchenEditChangeNumber(2))),
          isEmpty,
        );
        final original = _texts(_ticket(), l10n);
        expect(
          original.where(
            (t) =>
                t.contains(l10n.kdsAdditionLabel) ||
                t.contains(l10n.kdsRoundLabel(3)),
          ),
          isEmpty,
        );
      });

      test('$code: the KDS label adapter equals the shared adapter, field by '
          'field', () async {
        final l10n = await AppLocalizations.delegate.load(Locale(code));
        final kds = kitchenTicketPrintLabelsFromL10n(l10n);
        final pos = shared.kitchenTicketPrintLabelsFromL10n(l10n);
        expect(kds.ticketLabel, pos.ticketLabel);
        expect(kds.previewTitle, pos.previewTitle);
        expect(kds.dineIn, pos.dineIn);
        expect(kds.takeaway, pos.takeaway);
        expect(kds.tableLabel, pos.tableLabel);
        expect(kds.customerLabel, pos.customerLabel);
        expect(kds.customerPhoneLabel, pos.customerPhoneLabel);
        expect(kds.stationLabel, pos.stationLabel);
        expect(kds.noteLabel, pos.noteLabel);
        expect(kds.kitchenTotal('2', 'x'), pos.kitchenTotal('2', 'x'));
        expect(kds.prepWithOption('a', 'b'), pos.prepWithOption('a', 'b'));
        expect(
          kds.prepWithoutOption('a', 'b'),
          pos.prepWithoutOption('a', 'b'),
        );
        expect(kds.additionLabel, pos.additionLabel);
        expect(kds.roundLabel(3), pos.roundLabel(3));
        expect(kds.restaurantNameFallback, pos.restaurantNameFallback);
        expect(kds.changeNumberLabel, isNotNull);
        expect(kds.changeNumberLabel!(2), pos.changeNumberLabel!(2));
      });
    }
  });
}
