import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/kds_screen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// RF-034 AC#1: bump moves a ready ticket to `bumped`; recall returns it to
/// `in_preparation` and produces an in-memory recall audit placeholder. All
/// local widget state — no backend, no real audit write.
void main() {
  testWidgets('bump then recall drives ticket status + emits a recall event', (
    tester,
  ) async {
    RecallAuditEvent? captured;
    late AppLocalizations l10n;
    final tickets = [
      KdsTicketView(
        kitchenTicketId: 't1',
        stationId: 'grill',
        items: const [KdsItemView(name: 'Burger', quantity: 1)],
        status: KitchenTicketStatus.ready,
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

    // A ready ticket shows the bump action and its status.
    expect(find.text('ready'), findsOneWidget);
    expect(find.text(l10n.kdsBumpAction), findsOneWidget);
    expect(find.text(l10n.kdsRecallAction), findsNothing);

    // Bump -> status becomes bumped; the recall action appears.
    await tester.tap(find.text(l10n.kdsBumpAction));
    await tester.pumpAndSettle();
    expect(find.text('bumped'), findsOneWidget);
    expect(find.text(l10n.kdsRecallAction), findsOneWidget);
    expect(find.text(l10n.kdsBumpAction), findsNothing);
    expect(captured, isNull); // no recall yet

    // Recall -> status returns to in_preparation; a placeholder event is emitted.
    await tester.tap(find.text(l10n.kdsRecallAction));
    await tester.pumpAndSettle();
    expect(find.text('in_preparation'), findsOneWidget);
    expect(find.text(l10n.kdsRecallAction), findsNothing);

    expect(captured, isNotNull);
    expect(captured!.kitchenTicketId, 't1');
    expect(captured!.fromStatus, KitchenTicketStatus.bumped);
    expect(captured!.toStatus, KitchenTicketStatus.inPreparation);
    expect(captured!.reason, isNotEmpty);
    expect(captured!.actorId, isNotEmpty);
  });
}
