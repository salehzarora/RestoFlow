import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show hasNativePrinterProvider;

import 'kds_screen.dart';
import 'print/kds_native_printer.dart';
import 'print/kds_ticket_document.dart';
import 'state/kds_kitchen_print_controller.dart';
import 'state/kds_printer_assignments.dart';
import 'state/kds_session.dart';
import 'state/kds_status_pusher.dart';
import 'widgets/device_settings_menu.dart';
import 'widgets/kds_state_message.dart';
import 'widgets/kds_ticket_card.dart' show KdsTicketPrintStatus;
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
        // Part D/F: the honest per-ticket kitchen print-job status, keyed by
        // order id so a ticket keeps its status across poll rebuilds.
        final printJobs = ref.watch(kdsKitchenPrintControllerProvider);
        return KdsScreen(
          tickets: vs.tickets,
          allowRecall: false,
          // Sprint (I): the language switcher is visible on the LIVE data
          // board too; stale (last good pull) data is visibly flagged.
          appBarActions: const [LanguageSelector(), DeviceSettingsMenu()],
          showStaleBanner: vs.isStale,
          printStatusFor: (ticket) => _printStatusFor(
            ref,
            l10n,
            ticket,
            printJobs[KdsKitchenPrintController.keyFor(ticket)],
          ),
          onAdvanced: pusher == null
              ? null
              : (ticket, to) async {
                  final pushedOk = await pusher.push(ticket, to);
                  // Snappy server confirm (demo-readiness sprint): pull right
                  // after the push instead of waiting for the next poll tick.
                  // Best-effort — a failure just leaves the regular poll.
                  try {
                    await ref.read(kdsRepositoryProvider).refresh();
                  } catch (_) {}
                  // Part F: prepare the kitchen ticket print job ONLY when a
                  // real Acknowledge status update SUCCEEDED. This fires from
                  // the user's tap (never from a poll), and the controller's
                  // policy is idempotent per order id, so repeated taps /
                  // reloads never double-print. A status-push failure prints
                  // nothing. The controller honors the per-device toggle +
                  // printer assignment; the widget only owns the l10n payload.
                  if (to == KitchenTicketStatus.acknowledged && pushedOk) {
                    // RF-115 + ANDROID-004: prepare, then — if a print target is
                    // configured — encode + submit it. The ACTIVE bridge is the
                    // native local printer (Wi-Fi/Bluetooth) when one is set up on
                    // this Android display, else the loopback bridge. With no
                    // target the job stays honestly "prepared"; a confirmed write
                    // flips it to "sent to printer", never a fabricated print.
                    final bridge = ref.read(kdsActivePrintBridgeProvider);
                    ref
                        .read(kdsKitchenPrintControllerProvider.notifier)
                        .prepareOnAcknowledge(
                          ticket,
                          buildDocument: () =>
                              buildKdsTicketDocument(l10n, ticket),
                          submitToBridge: bridge == null ? null : bridge.submit,
                          nativePrinterConfigured: ref.read(
                            hasNativePrinterProvider,
                          ),
                        );
                  }
                },
        );
      },
    );
  }

  /// The honest kitchen print-job status for a ticket, or null when no job
  /// exists yet (auto-print off / not acknowledged). A confirmed bridge write
  /// shows "sent to printer" (NOT a hardware-confirmed print, which stays
  /// unreachable); recoverable states expose a Retry action.
  KdsTicketPrintStatus? _printStatusFor(
    WidgetRef ref,
    AppLocalizations l10n,
    KdsTicketView ticket,
    KdsPrintJob? job,
  ) {
    if (job == null) return null;
    final (label, canRetry) = switch (job.status) {
      KdsPrintJobStatus.prepared => (l10n.printStatusPrepared, false),
      KdsPrintJobStatus.sentToPrinter => (l10n.printStatusSentToPrinter, false),
      KdsPrintJobStatus.bridgeUnavailable => (
        l10n.printStatusBridgeUnavailable,
        true,
      ),
      KdsPrintJobStatus.printed => (l10n.printStatusPrinted, false),
      KdsPrintJobStatus.failed => (l10n.printStatusFailed, true),
      KdsPrintJobStatus.notConfigured => (l10n.printStatusNotConfigured, true),
    };
    return KdsTicketPrintStatus(
      label: label,
      onRetry: canRetry ? () => _retryPrint(ref, l10n, ticket) : null,
      // The recoverable states ARE the attention states — render them in the
      // danger tone on the card (DESIGN-001).
      isError: canRetry,
    );
  }

  /// Re-runs a recoverable kitchen print job through the same pipeline.
  void _retryPrint(WidgetRef ref, AppLocalizations l10n, KdsTicketView ticket) {
    final assignments = switch (ref
        .read(kdsPrinterAssignmentsProvider)
        .valueOrNull) {
      Success(:final value) => value,
      _ => null,
    };
    // ANDROID-004: retry through the ACTIVE bridge (native local printer when set
    // up on this display, else the loopback bridge). A device-local printer
    // counts as an enabled printer even without a server assignment.
    final bridge = ref.read(kdsActivePrintBridgeProvider);
    final hasNativePrinter = ref.read(hasNativePrinterProvider);
    ref
        .read(kdsKitchenPrintControllerProvider.notifier)
        .retry(
          ticket,
          hasEnabledPrinter:
              (assignments?.hasEnabledPrinter ?? false) || hasNativePrinter,
          buildDocument: () => buildKdsTicketDocument(l10n, ticket),
          submitToBridge: bridge == null ? null : bridge.submit,
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
          actions: const [LanguageSelector(), DeviceSettingsMenu()],
        ),
        body: body,
      );
}
