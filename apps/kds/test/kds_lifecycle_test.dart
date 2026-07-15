import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/kds_screen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// RF-103: a ticket can be advanced through its full lifecycle from the KDS,
/// using ONLY the existing KitchenTicketStateMachine transitions. The status
/// chip text (raw canonicalName) and the status-gated action update each step.
void main() {
  testWidgets('advances new -> acknowledged -> in_preparation -> ready -> '
      'bumped -> (recall) in_preparation', (tester) async {
    RecallAuditEvent? captured;
    late AppLocalizations l10n;
    final tickets = [
      KdsTicketView(
        kitchenTicketId: 't1',
        stationId: 'grill',
        items: const [KdsItemView(name: 'Burger', quantity: 1)],
        status: KitchenTicketStatus.newTicket,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return KdsScreen(tickets: tickets, onRecall: (e) => captured = e);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // new -> Acknowledge
    expect(find.text('new'), findsOneWidget);
    expect(find.text(l10n.kdsAcknowledgeAction), findsOneWidget);
    await tester.tap(find.text(l10n.kdsAcknowledgeAction));
    await tester.pumpAndSettle();

    // acknowledged -> Start
    expect(find.text('acknowledged'), findsOneWidget);
    expect(find.text(l10n.kdsStartAction), findsOneWidget);
    await tester.tap(find.text(l10n.kdsStartAction));
    await tester.pumpAndSettle();

    // in_preparation -> Mark ready
    expect(find.text('in_preparation'), findsOneWidget);
    expect(find.text(l10n.kdsReadyAction), findsOneWidget);
    await tester.tap(find.text(l10n.kdsReadyAction));
    await tester.pumpAndSettle();

    // ready -> Bump
    expect(find.text('ready'), findsOneWidget);
    expect(find.text(l10n.kdsServedAction), findsOneWidget);
    await tester.tap(find.text(l10n.kdsServedAction));
    await tester.pumpAndSettle();

    // bumped -> Recall (existing audited path)
    expect(find.text('bumped'), findsOneWidget);
    expect(find.text(l10n.kdsRecallAction), findsOneWidget);
    expect(captured, isNull);
    await tester.tap(find.text(l10n.kdsRecallAction));
    await tester.pumpAndSettle();

    // Recall returns to in_preparation and emits the recall audit placeholder.
    expect(find.text('in_preparation'), findsOneWidget);
    expect(captured, isNotNull);
    expect(captured!.kitchenTicketId, 't1');
    expect(captured!.fromStatus, KitchenTicketStatus.bumped);
    expect(captured!.toStatus, KitchenTicketStatus.inPreparation);
  });
}
