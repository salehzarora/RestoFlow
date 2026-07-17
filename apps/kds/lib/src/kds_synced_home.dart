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
import 'state/kds_void_ack_controller.dart';
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
    // PSC-001D correction: after every FRESH authoritative pull, drop
    // acknowledgement pending/failed entries for orders no longer among the
    // server's pending-ack cancellations (acknowledged here or elsewhere).
    // Deliberately gated on genuine data: a stale last-good snapshot, an
    // error, a reauth stop or the loading placeholder never cleans anything,
    // so a still-visible card keeps its state and the regular poll converges.
    // The set is derived from the COMPLETE ticket list, never one column.
    ref.listen(kdsViewStateProvider, (previous, next) {
      final vs = next.valueOrNull;
      if (vs == null || vs.isStale || vs.isError || vs.isReauthRequired) {
        return;
      }
      ref.read(kdsVoidAckControllerProvider.notifier).reconcile([
        for (final t in vs.tickets)
          if (t.requiresAck && t.orderId != null) t.orderId!,
      ]);
    });
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
        // PSC-001D: the per-order acknowledgement state for the red
        // cancellation cards (pending until the authoritative pull clears the
        // card; failed stays visible + retryable).
        final ackState = ref.watch(kdsVoidAckControllerProvider);
        return KdsScreen(
          tickets: vs.tickets,
          allowRecall: false,
          // Sprint (I): the language switcher is visible on the LIVE data
          // board too; stale (last good pull) data is visibly flagged.
          appBarActions: const [LanguageSelector(), DeviceSettingsMenu()],
          showStaleBanner: vs.isStale,
          // A2: subtle new-arrival attention glow on the LIVE board (tickets that
          // ARRIVE during this session; not the ones already present on load).
          enableNewArrivalAlert: true,
          printStatusFor: (ticket) => _printStatusFor(
            ref,
            l10n,
            ticket,
            printJobs[KdsKitchenPrintController.keyFor(ticket)],
          ),
          // A1: the always-visible per-card Reprint runs the SAME money-free
          // kitchen print pipeline — it creates no order and changes no status,
          // and preserves the native Wi-Fi/Bluetooth + Arabic/Hebrew raster path.
          onReprint: (ticket) => _retryPrint(ref, l10n, ticket),
          // PSC-001D: acknowledge a pending cancellation — the server-
          // authoritative order.void_ack through the existing sync path. The
          // card stays until the authoritative pull returns kitchen_ack_at.
          onAcknowledgeCancellation: (ticket) {
            final orderId = ticket.orderId;
            if (orderId == null) return;
            ref
                .read(kdsVoidAckControllerProvider.notifier)
                .acknowledge(orderId);
          },
          ackPendingOrderIds: ackState.pending,
          ackFailedOrderIds: ackState.failed,
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
    // (label, isError, isReprint): error states show a danger-tone Retry;
    // PRINT-STABILITY-001 adds a quiet Reprint on an already-SENT ticket so staff
    // can print another money-free copy (paper jam / extra copy) without changing
    // any order state. `printed` is unreachable-by-design and offers no action.
    final (label, isError, isReprint) = switch (job.status) {
      KdsPrintJobStatus.prepared => (l10n.printStatusPrepared, false, false),
      KdsPrintJobStatus.sentToPrinter => (
        l10n.printStatusSentToPrinter,
        false,
        true,
      ),
      KdsPrintJobStatus.bridgeUnavailable => (
        l10n.printStatusBridgeUnavailable,
        true,
        false,
      ),
      KdsPrintJobStatus.printed => (l10n.printStatusPrinted, false, false),
      KdsPrintJobStatus.failed => (l10n.printStatusFailed, true, false),
      KdsPrintJobStatus.notConfigured => (
        l10n.printStatusNotConfigured,
        true,
        false,
      ),
    };
    final hasAction = isError || isReprint;
    return KdsTicketPrintStatus(
      label: label,
      onRetry: hasAction ? () => _retryPrint(ref, l10n, ticket) : null,
      // The recoverable states ARE the attention states — render them in the
      // danger tone on the card (DESIGN-001). A reprint is a quiet action.
      isError: isError,
      actionLabel: isReprint ? l10n.printReprintAction : null,
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
