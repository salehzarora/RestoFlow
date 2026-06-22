import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'kds_screen.dart';

/// The provider-backed KDS home (RF-063): watches [kdsViewStateProvider] and
/// renders the shared [KdsScreen] for live/stale data, a spinner before the
/// first pull, and a re-authentication indicator when the session is revoked or
/// expired (polling has stopped).
///
/// All chrome text comes from `AppLocalizations` (RF-020 / DECISION D-014); the
/// loading / reauth / error cues are icons and a spinner so NO new localized
/// string is introduced by RF-063.
class KdsSyncedHome extends ConsumerWidget {
  const KdsSyncedHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(kdsViewStateProvider);
    return async.when(
      loading: () =>
          _scaffold(l10n, const Center(child: CircularProgressIndicator())),
      error: (_, __) =>
          _scaffold(l10n, const Center(child: Icon(Icons.error_outline))),
      data: (vs) {
        if (vs.isReauthRequired) {
          // Revoked/expired session: re-auth required, polling stopped.
          return _scaffold(l10n, const Center(child: Icon(Icons.lock_outline)));
        }
        if (vs.isError && vs.tickets.isEmpty) {
          return _scaffold(
            l10n,
            const Center(child: Icon(Icons.error_outline)),
          );
        }
        // data / offlineStale (and any state once we have tickets): show the
        // shared screen. Stale data is the last good pull, retained on purpose.
        return KdsScreen(tickets: vs.tickets);
      },
    );
  }

  Widget _scaffold(AppLocalizations l10n, Widget body) => Scaffold(
    appBar: AppBar(title: Text(l10n.kdsAppTitle)),
    body: body,
  );
}
