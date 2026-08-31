/// Shared chrome for the Platform Console pages (ADMIN-125C.2).
///
/// The console is a DENSE, read-only operator surface: every page is a header,
/// an optional filter bar, a list of rows, and a pager. Keeping that skeleton in
/// one place is why the four pages look like one product, and why "there are no
/// write controls" is a property of the shared widgets rather than a promise
/// repeated on each page — nothing here builds a button that mutates anything.
library;

import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/platform_admin_repository.dart';

/// Maps a raw wire status to a localized label, falling back to the RAW value
/// for anything unrecognized.
///
/// The fallback is the point: statuses are a closed vocabulary WE define, so
/// translating them is right — but if the platform ever grows a status this
/// build has never heard of, showing the wire value is honest, whereas mapping
/// it to "unknown" (or dropping it) would hide a real state from the operator.
String localizedStatus(AppLocalizations l10n, String wire) => switch (wire) {
  'active' => l10n.adminOrgStatusActive,
  'suspended' => l10n.adminOrgStatusSuspended,
  'trialing' => l10n.adminSubStatusTrialing,
  'past_due' => l10n.adminSubStatusPastDue,
  'canceled' => l10n.adminSubStatusCanceled,
  _ => wire,
};

/// The tone a status pill carries. `active`/`trialing` read as healthy,
/// `past_due`/`suspended`/`canceled` as needing attention.
RestoflowTone statusTone(String wire) => switch (wire) {
  'active' => RestoflowTone.success,
  'trialing' => RestoflowTone.info,
  'past_due' => RestoflowTone.warning,
  'suspended' || 'canceled' => RestoflowTone.danger,
  _ => RestoflowTone.neutral,
};

/// A localized, tone-aware status pill.
class ConsoleStatusPill extends StatelessWidget {
  const ConsoleStatusPill({required this.status, this.icon, super.key});

  final String status;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RestoflowStatusPill(
      label: localizedStatus(l10n, status),
      tone: statusTone(status),
      icon: icon,
    );
  }
}

/// A labelled read-only fact (`Default currency  ILS`). The value is DATA and is
/// never translated; the label is chrome and always is.
class ConsoleFact extends StatelessWidget {
  const ConsoleFact({
    required this.label,
    required this.value,
    this.valueWidget,
    super.key,
  });

  final String label;
  final String value;

  /// Replaces the plain value text (e.g. with a status pill).
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: RestoflowSpacing.md),
          Flexible(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child:
                  valueWidget ??
                  Text(
                    value,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One tappable console list row: a title, a muted meta line that WRAPS, and a
/// trailing cluster that can give ground.
///
/// Both the meta line and the trailing cluster are wrap-capable on purpose. The
/// pre-125C.2 admin rows overflowed at 390 because a non-flex trailing pair
/// measured its full intrinsic width no matter how little the row had left; the
/// same mistake here would paint a striped bar across a tenant's status.
class ConsoleListRow extends StatelessWidget {
  const ConsoleListRow({
    required this.title,
    this.meta = const <String>[],
    this.trailing = const <Widget>[],
    this.onTap,
    super.key,
  });

  /// Tenant-entered display name — data, never translated.
  final String title;

  /// Muted `key: value` fragments, joined with a separator and wrapped.
  final List<String> meta;

  /// Pills/labels shown at the reading end.
  final List<Widget> trailing;

  /// Null for a non-interactive row. A row NEVER mutates: at most it opens a
  /// read-only detail.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Padding(
      padding: const EdgeInsets.symmetric(
        vertical: RestoflowSpacing.md,
        horizontal: RestoflowSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: RestoflowSpacing.xxs),
                  Wrap(
                    spacing: RestoflowSpacing.sm,
                    runSpacing: RestoflowSpacing.xxs,
                    children: [
                      for (final fragment in meta)
                        Text(
                          fragment,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (trailing.isNotEmpty) ...[
            const SizedBox(width: RestoflowSpacing.md),
            Flexible(
              child: Wrap(
                // Keyed because this row has TWO Wraps: the meta line inside
                // the label column, and this trailing cluster. A positional
                // finder measures the wrong one, which is how a layout guard
                // ends up asserting something it never intended.
                key: const Key('console-row-trailing'),
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: RestoflowSpacing.sm,
                runSpacing: RestoflowSpacing.xs,
                children: trailing,
              ),
            ),
          ],
          if (onTap != null) ...[
            const SizedBox(width: RestoflowSpacing.xs),
            Icon(
              // Directional so the affordance points the reading way in RTL.
              Icons.chevron_right,
              size: RestoflowIconSizes.md,
              color: theme.colorScheme.onSurfaceVariant,
              textDirection: Directionality.of(context),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RestoflowRadii.sm),
      child: body,
    );
  }
}

/// A labelled dropdown filter whose null option means "no filter".
class ConsoleFilterDropdown<T> extends StatelessWidget {
  const ConsoleFilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.allLabel,
    super.key,
  });

  final String label;
  final T? value;
  final List<T> options;
  final String Function(T value) labelOf;
  final ValueChanged<T?> onChanged;

  /// The "no filter" entry's label (defaults to the shared "All").
  final String? allLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: _kFilterWidth,
      child: DropdownButtonFormField<T?>(
        // `initialValue`, not `value`: the deprecated `value` on a form field
        // fights the field's own state when the query is reset externally.
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          DropdownMenuItem<T?>(child: Text(allLabel ?? l10n.adminFilterAll)),
          for (final option in options)
            DropdownMenuItem<T?>(
              value: option,
              child: Text(labelOf(option), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// A debounce-free search box that commits on submit or on the search action.
///
/// Deliberately NOT search-as-you-type: every keystroke would be an AUDITED
/// server read, and an operator typing a tenant name would litter the platform
/// audit log with a dozen rows for one lookup.
class ConsoleSearchField extends StatefulWidget {
  const ConsoleSearchField({
    required this.value,
    required this.onSubmitted,
    this.fieldKey,
    super.key,
  });

  final String? value;
  final ValueChanged<String?> onSubmitted;
  final Key? fieldKey;

  @override
  State<ConsoleSearchField> createState() => _ConsoleSearchFieldState();
}

class _ConsoleSearchFieldState extends State<ConsoleSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value ?? '',
  );

  @override
  void didUpdateWidget(covariant ConsoleSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow an EXTERNAL reset (e.g. "clear filters") without stomping on what
    // the operator is currently typing.
    final incoming = widget.value ?? '';
    if (incoming != (oldWidget.value ?? '') && incoming != _controller.text) {
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
    widget.onSubmitted(text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: _kSearchWidth,
      child: TextField(
        key: widget.fieldKey,
        controller: _controller,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: l10n.adminSearchLabel,
          border: const OutlineInputBorder(),
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: RestoflowIconSizes.md),
          suffixIcon: IconButton(
            key: const Key('console-search-submit'),
            tooltip: l10n.adminSearchLabel,
            icon: const Icon(Icons.arrow_forward, size: RestoflowIconSizes.sm),
            onPressed: _submit,
          ),
        ),
      ),
    );
  }
}

/// The filter row: search + filters + sort + clear, wrapped so it reflows from
/// one line on a desktop to a stack on a phone.
class ConsoleFilterBar extends StatelessWidget {
  const ConsoleFilterBar({
    required this.children,
    required this.onClear,
    this.isFiltered = false,
    super.key,
  });

  final List<Widget> children;
  final VoidCallback onClear;

  /// Whether any filter is currently narrowing the result set (enables Clear).
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: RestoflowSpacing.md,
      runSpacing: RestoflowSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...children,
        TextButton.icon(
          key: const Key('console-clear-filters'),
          onPressed: isFiltered ? onClear : null,
          icon: const Icon(Icons.filter_alt_off, size: RestoflowIconSizes.sm),
          label: Text(l10n.adminClearFilters),
        ),
      ],
    );
  }
}

/// The offset pager: "Showing 1-25 of 137" with Previous / Next.
class ConsolePaginationBar extends StatelessWidget {
  const ConsolePaginationBar({
    required this.firstRowNumber,
    required this.lastRowNumber,
    required this.totalCount,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  final int firstRowNumber;
  final int lastRowNumber;

  /// The FILTERED total, so the range describes what the operator is looking at.
  final int totalCount;

  /// Null disables the button (already on the first / last page).
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: RestoflowSpacing.md),
      child: Wrap(
        spacing: RestoflowSpacing.md,
        runSpacing: RestoflowSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l10n.adminShowingRange(firstRowNumber, lastRowNumber, totalCount),
            key: const Key('console-showing-range'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          OutlinedButton.icon(
            key: const Key('console-previous-page'),
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left, size: RestoflowIconSizes.sm),
            label: Text(l10n.adminPrevious),
          ),
          OutlinedButton.icon(
            key: const Key('console-next-page'),
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right, size: RestoflowIconSizes.sm),
            label: Text(l10n.adminNext),
          ),
        ],
      ),
    );
  }
}

/// The console loading state. Exactly ONE spinner (the loading-state contract
/// the admin tests have always held).
class ConsoleLoading extends StatelessWidget {
  const ConsoleLoading({this.stateKey, super.key});

  final Key? stateKey;

  @override
  Widget build(BuildContext context) => RestoflowStateView(
    key: stateKey ?? const Key('platform-loading'),
    showSpinner: true,
    message: AppLocalizations.of(context).adminLoading,
  );
}

/// The console empty state.
class ConsoleEmpty extends StatelessWidget {
  const ConsoleEmpty({required this.message, this.stateKey, super.key});

  final String message;
  final Key? stateKey;

  @override
  Widget build(BuildContext context) => RestoflowStateView(
    key: stateKey ?? const Key('platform-empty'),
    icon: Icons.inbox_outlined,
    title: message,
  );
}

/// The failure state, dispatching on [PlatformAdminException.kind] to render an
/// honest, specific safe state (RF-134):
///   * [PlatformAdminErrorKind.notConfigured] — real mode is selected but the
///     Supabase connection is missing/invalid; no retry (config is needed).
///   * [PlatformAdminErrorKind.accessDenied] — the backend refused the read
///     (missing grant / aal2 MFA, or an unknown tenant); no retry.
///   * everything else — the generic, retryable error.
/// The developer-facing exception message is never shown to the user.
class ConsoleErrorView extends StatelessWidget {
  const ConsoleErrorView({
    required this.error,
    required this.onRetry,
    super.key,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kind = error is PlatformAdminException
        ? (error as PlatformAdminException).kind
        : PlatformAdminErrorKind.unexpected;

    switch (kind) {
      case PlatformAdminErrorKind.notConfigured:
        return RestoflowStateView(
          key: const Key('platform-not-configured'),
          icon: Icons.cloud_off_outlined,
          tone: RestoflowTone.neutral,
          title: l10n.adminNotConfiguredTitle,
          message: l10n.adminNotConfiguredBody,
        );
      case PlatformAdminErrorKind.accessDenied:
        return RestoflowStateView(
          key: const Key('platform-access-denied'),
          icon: Icons.lock_outline,
          tone: RestoflowTone.danger,
          title: l10n.adminAccessDeniedTitle,
          message: l10n.adminAccessDeniedBody,
        );
      case PlatformAdminErrorKind.unexpected:
        return RestoflowStateView(
          key: const Key('platform-error'),
          icon: Icons.error_outline,
          tone: RestoflowTone.danger,
          title: l10n.adminError,
          actions: [
            FilledButton.icon(
              key: const Key('platform-retry-button'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.adminRetry),
            ),
          ],
        );
    }
  }
}

/// The standard page body: a page header, then content, in a scrollable column
/// that is width-capped on very wide screens so lines stay readable.
class ConsolePage extends StatelessWidget {
  const ConsolePage({
    required this.title,
    required this.children,
    this.subtitle,
    this.icon,
    this.leading,
    this.padding,
    this.headerKey,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  /// An optional widget above the header (e.g. a Back action on a detail page).
  final Widget? leading;

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  /// Keys the page heading so a test can assert "still the real page, not a
  /// degraded fallback" without matching on translated text.
  final Key? headerKey;

  @override
  Widget build(BuildContext context) {
    final lead = leading;
    return ListView(
      padding: padding ?? const EdgeInsets.all(RestoflowSpacing.lg),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: kConsoleMaxContentWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (lead != null) ...[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: lead,
                  ),
                  const SizedBox(height: RestoflowSpacing.sm),
                ],
                RestoflowPageHeader(
                  key: headerKey,
                  title: title,
                  subtitle: subtitle,
                  icon: icon,
                ),
                const SizedBox(height: RestoflowSpacing.lg),
                ...children,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Lays metric cards out in a responsive grid (4 / 2 / 1 columns).
class ConsoleMetricGrid extends StatelessWidget {
  const ConsoleMetricGrid({required this.cards, super.key});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= RestoflowBreakpoints.wide
            ? 4
            : (constraints.maxWidth >= RestoflowBreakpoints.compact ? 2 : 1);
        const gap = RestoflowSpacing.md;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

/// Interleaves a vertical gap between stacked section cards, so a conditionally
/// empty section list lays out without dangling gaps.
List<Widget> withSectionGaps(List<Widget> widgets) {
  final out = <Widget>[];
  for (var i = 0; i < widgets.length; i++) {
    if (i > 0) out.add(const SizedBox(height: RestoflowSpacing.lg));
    out.add(widgets[i]);
  }
  return out;
}

/// Caps console content width on very wide monitors. The pre-125C.2 overview
/// stretched a three-card row across a 2560px screen, leaving a band of empty
/// space between the label and its number; a reading measure fixes that without
/// a redesign.
const double kConsoleMaxContentWidth = 1180;

const double _kFilterWidth = 210;
const double _kSearchWidth = 260;
