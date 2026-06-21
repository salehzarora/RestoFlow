import 'package:flutter/material.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'src/kds_screen.dart';
import 'src/kds_ticket_view.dart';

void main() => runApp(const KdsApp());

/// Minimal localized KDS app (RF-034). Hosts the local [KdsScreen] driven by a
/// fake in-memory fixture — no backend, no repository, no persistence. RTL/LTR
/// is data-driven by the shared `packages/l10n` wiring.
class KdsApp extends StatelessWidget {
  const KdsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).kdsAppTitle,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      localeResolutionCallback: restoflowResolveLocale,
      debugShowCheckedModeBanner: false,
      home: KdsScreen(tickets: _demoTickets()),
    );
  }
}

/// A small local fixture (data only) so the running app shows sample tickets.
List<KdsTicketView> _demoTickets() => [
  KdsTicketView(
    kitchenTicketId: 'order-1:grill',
    stationId: 'grill',
    items: const [
      KdsItemView(name: 'Burger', quantity: 2),
      KdsItemView(name: 'Steak', quantity: 1),
    ],
  ),
  KdsTicketView(
    kitchenTicketId: 'order-1:bar',
    stationId: 'bar',
    items: const [KdsItemView(name: 'Beer', quantity: 3)],
  ),
];
