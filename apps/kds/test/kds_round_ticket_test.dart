import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/kds_screen.dart';
import 'package:restoflow_kds/src/state/kds_status_pusher.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// PSC-001C — service-round surfaces on the KDS app:
///  * a ROUND ticket's card announces "Addition · Round N";
///  * card actions on a round ticket dispatch `order.round_status` with the
///    ROUND id as the canonical target (never the parent `order.status`);
///  * the original ticket keeps dispatching `order.status` unchanged.

class _FakeTransport implements SyncRpcTransport {
  final List<(String, Map<String, dynamic>)> calls = [];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return {'ok': true, 'results': <Object?>[]};
  }
}

KdsTicketView _ticket({String? roundId, int? roundNumber}) => KdsTicketView(
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
);

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
}
