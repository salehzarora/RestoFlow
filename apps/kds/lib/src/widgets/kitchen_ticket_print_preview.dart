import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kitchen_order.dart';
import '../print/print_document.dart';
import '../print/print_service.dart';
import 'kds_status_chip.dart';

/// A browser-style KITCHEN-TICKET print preview (RF-118): a ticket "paper" over
/// an RF-117 [KitchenOrderTicket] with big quantities, shown in a dialog with
/// Close + Print (browser) actions. A print PREVIEW — the Print button triggers
/// the browser's print on web (no-op elsewhere). Not a hardware printer.
/// Money-free (SECURITY T-003).
class KitchenTicketPrintPreview extends ConsumerWidget {
  const KitchenTicketPrintPreview({
    required this.ticket,
    required this.now,
    super.key,
  });

  final KitchenOrderTicket ticket;
  final DateTime now;

  static Future<void> show(
    BuildContext context, {
    required KitchenOrderTicket ticket,
    required DateTime now,
  }) => showDialog<void>(
    context: context,
    builder: (_) => KitchenTicketPrintPreview(ticket: ticket, now: now),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Dialog(
      key: const Key('kitchen-ticket-preview'),
      insetPadding: const EdgeInsets.all(RestoflowSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PreviewHeader(title: l10n.kdsTicketPreviewTitle),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(RestoflowSpacing.lg),
                // A receipt is PAPER (design-polish sprint): the ticket sheet
                // is a LIGHT-themed island — explicit light surface + dark
                // text — regardless of the surrounding (dark kitchen) theme.
                child: Theme(
                  data: restoflowBaseTheme(),
                  child: _TicketPaper(ticket: ticket, now: now),
                ),
              ),
            ),
            const Divider(height: 1),
            _PreviewActions(
              l10n: l10n,
              onPrint: () => ref
                  .read(printServiceProvider)
                  .printDocument(buildKitchenTicketDocument(l10n, ticket, now)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The light "paper" sheet of the preview. Reads its colours from the
/// (light) Theme injected above it, so every nested widget — status chip,
/// pills, rules, item lines — renders paper-correct dark-on-light.
class _TicketPaper extends StatelessWidget {
  const _TicketPaper({required this.ticket, required this.now});

  final KitchenOrderTicket ticket;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dineIn = ticket.orderType == OrderType.dineIn;
    final typeLabel = dineIn
        ? l10n.posOrderTypeDineIn
        : l10n.posOrderTypeTakeaway;
    final minutes = now.difference(ticket.submittedAt).inMinutes;
    final elapsed = l10n.kdsElapsedMinutes(minutes < 0 ? 0 : minutes);
    final station = ticket.stationId;

    return Container(
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(RestoflowRadii.sm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ticket.orderNumber,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              KdsStatusChip(status: ticket.status),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          Wrap(
            spacing: RestoflowSpacing.sm,
            runSpacing: RestoflowSpacing.xs,
            children: [
              RestoflowStatusPill(
                icon: dineIn ? Icons.restaurant : Icons.takeout_dining,
                label: typeLabel,
              ),
              if (dineIn && ticket.tableLabel != null)
                RestoflowStatusPill(
                  icon: Icons.event_seat,
                  label: '${l10n.posTableLabel} ${ticket.tableLabel}',
                ),
              if (station != null)
                RestoflowStatusPill(
                  icon: Icons.kitchen_outlined,
                  label: '${l10n.kdsStationLabel}: $station',
                ),
              RestoflowStatusPill(icon: Icons.schedule, label: elapsed),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          const _Rule(),
          const SizedBox(height: RestoflowSpacing.sm),
          for (final item in ticket.items)
            _TicketItem(item: item, noteLabel: l10n.kdsNoteLabel),
          const SizedBox(height: RestoflowSpacing.sm),
          const _Rule(),
          const SizedBox(height: RestoflowSpacing.sm),
          _Note(message: l10n.kdsDemoFeedBanner),
        ],
      ),
    );
  }
}

/// Builds the ISOLATED print document for a kitchen ticket (RF-118). The printed
/// page contains ONLY these lines — never the KDS board behind the modal. Big
/// quantities; money-free (SECURITY T-003).
PrintDocument buildKitchenTicketDocument(
  AppLocalizations l10n,
  KitchenOrderTicket ticket,
  DateTime now,
) {
  final dineIn = ticket.orderType == OrderType.dineIn;
  final minutes = now.difference(ticket.submittedAt).inMinutes;
  final station = ticket.stationId;
  // Built into a local (not an inline `title:` literal) so the RF-020
  // no-hardcoded-strings guard isn't tripped by this l10n-interpolated value.
  final docTitle = '${l10n.kdsTicketPreviewTitle} ${ticket.orderNumber}';
  return PrintDocument(
    title: docTitle,
    lines: <PrintLine>[
      PrintLine.title(ticket.orderNumber),
      PrintLine.center(ticket.status.canonicalName),
      PrintLine.rule(),
      PrintLine.kv(
        l10n.posOrderTypeLabel,
        dineIn ? l10n.posOrderTypeDineIn : l10n.posOrderTypeTakeaway,
      ),
      if (dineIn && ticket.tableLabel != null)
        PrintLine.kv(l10n.posTableLabel, ticket.tableLabel!),
      if (station != null) PrintLine.kv(l10n.kdsStationLabel, station),
      PrintLine.kv(
        l10n.kdsElapsedLabel,
        l10n.kdsElapsedMinutes(minutes < 0 ? 0 : minutes),
      ),
      PrintLine.rule(),
      for (final item in ticket.items) ...[
        PrintLine.item(item.name, '${item.quantity}×', emphasised: true),
        if (item.modifiers.isNotEmpty)
          PrintLine.sub('+ ${item.modifiers.join(', ')}'),
        if (item.note != null)
          PrintLine.sub('${l10n.kdsNoteLabel}: ${item.note}'),
      ],
      PrintLine.rule(),
      PrintLine.note(l10n.kdsDemoFeedBanner),
    ],
  );
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.lg,
        RestoflowSpacing.sm,
        RestoflowSpacing.sm,
        RestoflowSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(Icons.print_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            key: const Key('ticket-preview-close-icon'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            tooltip: MaterialLocalizations.of(context).closeButtonLabel,
          ),
        ],
      ),
    );
  }
}

class _PreviewActions extends StatelessWidget {
  const _PreviewActions({required this.l10n, required this.onPrint});

  final AppLocalizations l10n;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.printPreviewHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          TextButton(
            key: const Key('ticket-preview-close-button'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.printPreviewClose),
          ),
          const SizedBox(width: RestoflowSpacing.xs),
          FilledButton.icon(
            key: const Key('ticket-preview-print-button'),
            onPressed: onPrint,
            icon: const Icon(Icons.print, size: 18),
            label: Text(l10n.printPreviewPrint),
          ),
        ],
      ),
    );
  }
}

/// A kitchen-ticket item line with a BIG, prominent quantity (kitchen-readable).
class _TicketItem extends StatelessWidget {
  const _TicketItem({required this.item, required this.noteLabel});

  final KitchenOrderItem item;
  final String noteLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = item.note;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '${item.quantity}×',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (item.modifiers.isNotEmpty)
                  Text(
                    '+ ${item.modifiers.join(', ')}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (note != null)
                  Text(
                    '$noteLabel: $note',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: RestoflowSpacing.xs),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return LayoutBuilder(
      builder: (context, constraints) {
        const dash = 3.0;
        const gap = 3.0;
        final count = (constraints.maxWidth / (dash + gap)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List<Widget>.generate(
            count < 1 ? 1 : count,
            (_) => SizedBox(
              width: dash,
              height: 1,
              child: ColoredBox(color: color),
            ),
          ),
        );
      },
    );
  }
}
