import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_sync/restoflow_sync.dart';

import 'src/kds_screen.dart';
import 'src/kds_synced_home.dart';

void main() => runApp(const KdsApp());

/// Localized KDS app.
///
/// RF-063: when a [KdsSyncSource] is injected, the app renders the
/// provider-backed live data path — polling-first `sync_pull` via
/// `feature_kitchen` (no realtime; DECISION D-010). With NO source (the
/// default), it falls back to the RF-034 in-memory fixture so the app and its
/// widget tests run with NO Supabase credentials (approved decision A1). RTL/LTR
/// is data-driven by the shared `packages/l10n` wiring.
class KdsApp extends StatelessWidget {
  const KdsApp({this.source, super.key});

  /// The injected sync source (authenticated). Null -> use the local fixture.
  final KdsSyncSource? source;

  @override
  Widget build(BuildContext context) {
    final injected = source;
    final app = MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).kdsAppTitle,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      localeResolutionCallback: restoflowResolveLocale,
      debugShowCheckedModeBanner: false,
      home: injected == null
          ? KdsScreen(tickets: _demoTickets())
          : const KdsSyncedHome(),
    );
    if (injected == null) return app;
    return ProviderScope(
      overrides: [kdsSyncSourceProvider.overrideWithValue(injected)],
      child: app,
    );
  }
}

/// A small local fixture (data only) so the running app shows sample tickets
/// when no real session is injected (RF-034 fallback).
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
