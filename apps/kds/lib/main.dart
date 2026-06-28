import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_sync/restoflow_sync.dart';

import 'src/kds_synced_home.dart';
import 'src/kitchen_orders_home.dart';

void main() => runApp(const KdsApp());

/// Localized KDS app (RF-063 + RF-108).
///
/// The root ALWAYS provides a [ProviderScope] now (RF-108 normalization). When a
/// [KdsSyncSource] is injected, it renders the provider-backed live data path —
/// polling-first `sync_pull` via `feature_kitchen` (no realtime; DECISION
/// D-010). With NO source: in DEMO mode (`RESTOFLOW_DEMO_MODE` default true) it
/// shows the RF-034 in-memory fixture (no Supabase credentials needed); in auth
/// mode it routes through the kitchen_staff/owner/manager role gate
/// (`AppSurface.kds`). Real live KDS data in auth mode needs an injected
/// SyncSession (device session + PIN), which is DEFERRED (no client-reachable
/// device-session minting yet) - so the authed entry currently shows the demo
/// board. RTL/LTR is data-driven by the shared `packages/l10n` wiring.
class KdsApp extends StatelessWidget {
  const KdsApp({
    this.source,
    this.invalidationSource,
    this.demoMode,
    this.fetchContext,
    super.key,
  });

  /// The injected sync source (authenticated). Null -> demo/auth-gate path.
  final KdsSyncSource? source;

  /// RF-058: an OPTIONAL realtime invalidation source. When provided (and a sync
  /// [source] is too), realtime hints are bridged to refresh() on top of
  /// polling. Null -> polling-only (realtime is never required).
  final InvalidationSource? invalidationSource;

  /// Test-only override of the demo/auth mode (null => `RESTOFLOW_DEMO_MODE`).
  final bool? demoMode;

  /// Test-only override of the auth-context fetcher (null => env config).
  final AuthContextFetcher? fetchContext;

  @override
  Widget build(BuildContext context) {
    final injected = source;
    final invSource = invalidationSource;
    final app = MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).kdsAppTitle,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      localeResolutionCallback: restoflowResolveLocale,
      debugShowCheckedModeBanner: false,
      theme: restoflowBaseTheme(),
      home: injected != null
          // RF-063 injected live path (tests / future authed session wiring).
          ? const KdsSyncedHome()
          : AuthGatedHome(
              surface: AppSurface.kds,
              // RF-117: the visible kitchen order board (demo feed) — status
              // columns + kitchen actions. Live backend/realtime is deferred
              // (the feature_kitchen polling path is the seam for that).
              demoHome: const KitchenOrdersHome(),
              onReady: (context, state) => const KitchenOrdersHome(),
              demoMode: demoMode,
              fetchContext: fetchContext,
            ),
    );
    return ProviderScope(
      overrides: [
        if (injected != null) kdsSyncSourceProvider.overrideWithValue(injected),
        if (injected != null && invSource != null)
          kdsInvalidationSourceProvider.overrideWithValue(invSource),
      ],
      child: app,
    );
  }
}
