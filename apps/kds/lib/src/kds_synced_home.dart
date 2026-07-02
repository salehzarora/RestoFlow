import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'kds_screen.dart';
import 'state/kds_session.dart';
import 'state/kds_status_pusher.dart';
import 'widgets/kds_state_message.dart';
import 'widgets/language_selector.dart';

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
        context,
        l10n,
        KdsStateMessage(message: l10n.kdsLoadingState, showSpinner: true),
      ),
      error: (_, __) => _scaffold(
        context,
        l10n,
        KdsStateMessage(
          icon: Icons.error_outline,
          tone: RestoflowTone.danger,
          message: l10n.kdsErrorState,
        ),
      ),
      data: (vs) {
        if (vs.isReauthRequired) {
          // Revoked/expired session: re-auth required, polling stopped. The
          // action ENDS the local session, so the app root falls back to the
          // staff PIN screen (review fix — never a dead end until restart).
          return _scaffold(
            context,
            l10n,
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                KdsStateMessage(
                  icon: Icons.lock_outline,
                  tone: RestoflowTone.warning,
                  message: l10n.kdsReauthRequired,
                ),
                const SizedBox(height: RestoflowSpacing.lg),
                FilledButton.tonalIcon(
                  onPressed: () => ref
                      .read(kdsSessionControllerProvider.notifier)
                      .endSession(),
                  icon: const Icon(Icons.pin_outlined),
                  label: Text(l10n.kdsSignInAgain),
                ),
              ],
            ),
          );
        }
        if (vs.isError && vs.tickets.isEmpty) {
          return _scaffold(
            context,
            l10n,
            KdsStateMessage(
              icon: Icons.error_outline,
              tone: RestoflowTone.danger,
              message: l10n.kdsErrorState,
            ),
          );
        }
        // data / offlineStale (and any state once we have tickets): show the
        // shared screen. Stale data is the last good pull, retained on purpose.
        // A live advance is PERSISTED via the status pusher (order.status
        // through sync_push); the next poll re-syncs to the server's state.
        // RECALL is hidden on the LIVE board (review fix): the backend allows
        // forward transitions only, so a local-only recall would lie and then
        // revert on the next poll.
        final pusher = ref.watch(kdsStatusPusherProvider);
        return KdsScreen(
          tickets: vs.tickets,
          allowRecall: false,
          // Sprint (I): the language switcher is visible on the LIVE data
          // board too; stale (last good pull) data is visibly flagged.
          appBarActions: const [LanguageSelector()],
          showStaleBanner: vs.isStale,
          onAdvanced: pusher == null
              ? null
              : (ticket, to) async {
                  await pusher.push(ticket, to);
                  // Snappy server confirm (demo-readiness sprint): pull right
                  // after the push instead of waiting for the next poll tick.
                  // Best-effort — a failure just leaves the regular poll.
                  try {
                    await ref.read(kdsRepositoryProvider).refresh();
                  } catch (_) {}
                },
        );
      },
    );
  }

  Widget _scaffold(BuildContext context, AppLocalizations l10n, Widget body) =>
      Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.kitchen_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Text(l10n.kdsAppTitle),
            ],
          ),
          // Sprint (I): the language switcher is visible on the LIVE board too.
          actions: const [LanguageSelector()],
        ),
        body: body,
      );
}
