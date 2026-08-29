/// The Platform Console AUDIT LOG page (ADMIN-125C.2).
///
/// Consumes `public.platform_admin_audit_search` — a KEYSET-paged read of the
/// append-only platform-admin audit trail.
///
/// Keyset, not offset, and the UI follows suit: there is a "load more" that
/// grows one list, not previous/next page buttons. That is not a styling choice.
/// The log is append-only and grows while it is being read, so an offset page 2
/// taken a minute after page 1 would silently skip rows that page 1 pushed down.
///
/// The projection is deliberately narrow: occurred-at, action, reason, and the
/// actor / target as SHORTENED IDs. The `details` jsonb is never returned by the
/// server and is not modelled here, and actor ids are NOT resolved to people —
/// putting operator emails on a shared console screen is a PII decision that
/// belongs to its own ticket, not a side effect of building a log viewer.
///
/// Opening this page writes its OWN `platform.audit.search` row. That is
/// correct — a platform read is a platform event — so the newest row an operator
/// sees is often their own arrival.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/console_models.dart';
import '../state/platform_admin_providers.dart';
import 'console_widgets.dart';

/// The audit actions the console offers as a filter. A fixed list of the actions
/// THIS console and its predecessor emit — an unknown action simply matches
/// nothing, and the unfiltered view still shows every row whatever its action.
const List<String> kKnownAuditActions = <String>[
  'platform.console.overview',
  'platform.subscribers.list',
  'platform.subscriber.detail',
  'platform.restaurants.list',
  'platform.audit.search',
  'platform.organizations.overview',
  'platform.organization.detail',
  'platform.audit.read',
];

class ConsoleAuditLogPage extends ConsumerWidget {
  const ConsoleAuditLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(auditFilterProvider);
    final feed = ref.watch(auditFeedProvider);

    void setFilter(AuditQuery next) =>
        ref.read(auditFilterProvider.notifier).state = next;

    final filters = ConsoleFilterBar(
      isFiltered:
          filter.action != null ||
          filter.targetOrganizationId != null ||
          filter.from != null ||
          filter.to != null,
      onClear: () => setFilter(const AuditQuery()),
      children: [
        ConsoleFilterDropdown<String>(
          key: const Key('audit-action-filter'),
          label: l10n.adminAuditActionLabel,
          value: filter.action,
          options: kKnownAuditActions,
          // Raw wire keys, deliberately untranslated: they ARE the audit
          // identifiers, and a prettified label would not match the log.
          labelOf: (action) => action,
          onChanged: (value) =>
              setFilter(filter.copyWith(action: value).resetToFirstPage()),
        ),
        _AuditDateField(
          fieldKey: const Key('audit-from'),
          label: l10n.adminAuditFrom,
          value: filter.from,
          onChanged: (value) =>
              setFilter(filter.copyWith(from: value).resetToFirstPage()),
        ),
        _AuditDateField(
          fieldKey: const Key('audit-to'),
          label: l10n.adminAuditTo,
          value: filter.to,
          // The server treats the range as INCLUSIVE, so an end date is pushed
          // to the end of that day — otherwise "to 2026-06-28" would drop
          // everything that happened on the 28th.
          endOfDay: true,
          onChanged: (value) =>
              setFilter(filter.copyWith(to: value).resetToFirstPage()),
        ),
      ],
    );

    final Widget body;
    if (feed.isLoading) {
      body = const Padding(
        padding: EdgeInsets.only(top: RestoflowSpacing.xl),
        child: ConsoleLoading(),
      );
    } else if (feed.isEmpty && feed.error != null) {
      body = Padding(
        padding: const EdgeInsets.only(top: RestoflowSpacing.xl),
        child: ConsoleErrorView(
          error: feed.error!,
          onRetry: () => ref.read(auditFeedProvider.notifier).refresh(),
        ),
      );
    } else if (feed.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.only(top: RestoflowSpacing.xl),
        child: ConsoleEmpty(
          stateKey: const Key('audit-empty'),
          message: l10n.adminNoAuditEvents,
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RestoflowSectionCard(
            key: const Key('audit-card'),
            children: [
              for (final event in feed.events)
                _AuditTile(event: event, l10n: l10n),
            ],
          ),
          // A failed "load more" keeps the rows already on screen and reports
          // the failure beside them: throwing away a page the operator is
          // reading is a worse answer than a partial list.
          if (feed.error != null) ...[
            const SizedBox(height: RestoflowSpacing.md),
            RestoflowNoticeBanner(
              key: const Key('audit-load-more-failed'),
              tone: RestoflowTone.danger,
              body: l10n.adminError,
            ),
          ],
          if (feed.hasMore) ...[
            const SizedBox(height: RestoflowSpacing.md),
            Center(
              child: OutlinedButton.icon(
                key: const Key('audit-load-more'),
                onPressed: feed.isLoadingMore
                    ? null
                    : () => ref.read(auditFeedProvider.notifier).loadMore(),
                icon: feed.isLoadingMore
                    ? const SizedBox(
                        width: RestoflowIconSizes.sm,
                        height: RestoflowIconSizes.sm,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.expand_more,
                        size: RestoflowIconSizes.sm,
                      ),
                label: Text(l10n.adminLoadMore),
              ),
            ),
          ],
        ],
      );
    }

    return ConsolePage(
      title: l10n.adminNavAuditLog,
      subtitle: l10n.adminConsoleReadOnly,
      icon: Icons.receipt_long_outlined,
      children: [
        filters,
        const SizedBox(height: RestoflowSpacing.lg),
        body,
      ],
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.event, required this.l10n});

  final AuditEvent event;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final target = event.targetShortId;
    return ConsoleListRow(
      key: Key('audit-row-${event.id}'),
      // The operator-authored reason leads: it is the human-readable half of
      // the row. The raw action key is de-emphasized into a pill beside it.
      title: event.reason,
      meta: [
        event.occurredAtLabel,
        '${l10n.adminAuditActorLabel}: ${event.actorShortId}',
        target == null
            ? l10n.adminAuditPlatformWide
            : '${l10n.adminAuditTargetLabel}: $target',
      ],
      trailing: [RestoflowStatusPill(label: event.action)],
    );
  }
}

/// A plain `YYYY-MM-DD` bound for the audit range.
///
/// A text field, not a date picker: the operator is filtering a log by day, the
/// value round-trips to the server as an ISO instant, and a picker would add a
/// dependency and a locale-calendar problem for no gain. An unparseable value
/// simply clears the bound rather than sending something the server would
/// reject with 22023.
class _AuditDateField extends StatefulWidget {
  const _AuditDateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.fieldKey,
    this.endOfDay = false,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final Key? fieldKey;

  /// True for the inclusive upper bound (pushes to `T23:59:59Z`).
  final bool endOfDay;

  @override
  State<_AuditDateField> createState() => _AuditDateFieldState();
}

class _AuditDateFieldState extends State<_AuditDateField> {
  late final TextEditingController _controller = TextEditingController(
    text: _dayOf(widget.value),
  );

  static String _dayOf(String? iso) =>
      iso != null && iso.length >= 10 ? iso.substring(0, 10) : '';

  @override
  void didUpdateWidget(covariant _AuditDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = _dayOf(widget.value);
    if (incoming != _dayOf(oldWidget.value) && incoming != _controller.text) {
      _controller.text = incoming;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || DateTime.tryParse(text) == null) {
      widget.onChanged(null);
      return;
    }
    widget.onChanged(
      widget.endOfDay ? '${text}T23:59:59Z' : '${text}T00:00:00Z',
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: TextField(
        key: widget.fieldKey,
        controller: _controller,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        onEditingComplete: _submit,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: 'YYYY-MM-DD',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}
