import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_kds/src/widgets/kds_status_chip.dart';

Future<void> _pump(WidgetTester tester, KitchenTicketStatus status) {
  return tester.pumpWidget(
    MaterialApp(
      theme: restoflowBaseTheme(),
      home: Scaffold(
        body: Center(child: KdsStatusChip(status: status)),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the raw canonicalName through the shared pill', (
    tester,
  ) async {
    await _pump(tester, KitchenTicketStatus.inPreparation);

    // The visible text stays the raw status data (not localized) — RF-102.
    expect(
      find.text(KitchenTicketStatus.inPreparation.canonicalName),
      findsOneWidget,
    );
    // RF-141E: it's the shared, themeable pill — not a local hardcoded chip.
    expect(find.byType(RestoflowStatusPill), findsOneWidget);
  });

  testWidgets('each status maps to a themeable semantic tone (RF-141E)', (
    tester,
  ) async {
    final tones = <KitchenTicketStatus, RestoflowTone>{};
    for (final status in KitchenTicketStatus.values) {
      await _pump(tester, status);
      tones[status] = tester
          .widget<RestoflowStatusPill>(find.byType(RestoflowStatusPill))
          .tone;
    }

    // The signalling statuses each keep a distinct at-a-glance tone: blue for
    // new (DESIGN-001 — the card now matches its blue "New" column header),
    // warm/amber while cooking, green when ready, red when cancelled.
    expect(tones[KitchenTicketStatus.newTicket], RestoflowTone.info);
    expect(tones[KitchenTicketStatus.acknowledged], RestoflowTone.info);
    expect(tones[KitchenTicketStatus.inPreparation], RestoflowTone.warning);
    expect(tones[KitchenTicketStatus.ready], RestoflowTone.success);
    expect(tones[KitchenTicketStatus.cancelled], RestoflowTone.danger);
    // Cleared work stays quiet.
    expect(tones[KitchenTicketStatus.bumped], RestoflowTone.neutral);
  });
}
