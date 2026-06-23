import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'kds_screen.dart';
import 'widgets/kds_state_message.dart';

/// The provider-backed KDS home (RF-063): watches [kdsViewStateProvider] and
/// renders the shared [KdsScreen] for live/stale data, a spinner before the
/// first pull, and a re-authentication indicator when the session is revoked or
/// expired (polling has stopped).
///
/// RF-102 keeps the same loading/reauth/error ICONS (and spinner) but adds a
/// localized message beside each so the state reads clearly. All chrome text
/// comes from `AppLocalizations` (DECISION D-014).
class KdsSyncedHome extends ConsumerWidget {
  const KdsSyncedHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(kdsViewStateProvider);
    return async.when(
      loading: () => _scaffold(
        l10n,
        KdsStateMessage(message: l10n.kdsLoadingState, showSpinner: true),
      ),
      error: (_, __) => _scaffold(
        l10n,
        KdsStateMessage(icon: Icons.error_outline, message: l10n.kdsErrorState),
      ),
      data: (vs) {
        if (vs.isReauthRequired) {
          // Revoked/expired session: re-auth required, polling stopped.
          return _scaffold(
            l10n,
            KdsStateMessage(
              icon: Icons.lock_outline,
              message: l10n.kdsReauthRequired,
            ),
          );
        }
        if (vs.isError && vs.tickets.isEmpty) {
          return _scaffold(
            l10n,
            KdsStateMessage(
              icon: Icons.error_outline,
              message: l10n.kdsErrorState,
            ),
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
