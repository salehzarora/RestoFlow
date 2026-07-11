/// A searchable global IANA timezone picker for Dashboard Settings
/// (TIMEZONE-GLOBAL-001).
///
/// Replaces the hard-coded 3/4-option dropdown. The field SHOWS the branch's
/// current zone (so an unset/UTC pilot branch is visible) and opens a searchable
/// dialog over the full `list_timezones` catalog — searchable by country, city,
/// or IANA id, with localized labels for a curated common set. Selecting a zone
/// reports its canonical IANA id; "leave unchanged" reports null (the existing
/// save semantics). RTL-safe, keyboard-accessible, responsive.
library;

import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'timezone_catalog.dart';

/// The result of the picker dialog: null = cancelled (no change); a value with a
/// null [id] = "leave unchanged"; a value with an [id] = pick that zone.
class _TimezonePick {
  const _TimezonePick(this.id);
  final String? id;
}

/// A labelled, tappable field that shows the current/selected timezone and opens
/// the search dialog. [currentTimezone] is the branch's stored zone; [selected]
/// is the pending pick (null = leave unchanged). [onChanged] receives the picked
/// IANA id, or null for "leave unchanged".
class TimezonePickerField extends StatelessWidget {
  const TimezonePickerField({
    required this.l10n,
    required this.options,
    required this.currentTimezone,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final AppLocalizations l10n;
  final List<TimezoneOption> options;
  final String? currentTimezone;
  final String? selected;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The effective zone shown: the pending pick, else the current stored zone.
    final effective = selected ?? currentTimezone;
    final primary = effective == null
        ? l10n.timezonePickerNotSet
        : timezoneLabel(l10n, effective);
    // A helpful subtitle: the canonical IANA id + (for a pending pick) a hint.
    final subtitleParts = <String>[
      if (effective != null) effective,
      if (selected != null) l10n.timezonePickerWillChange,
    ];

    return InkWell(
      key: const Key('settings-branch-timezone'),
      onTap: enabled ? () => _open(context) : null,
      borderRadius: BorderRadius.circular(RestoflowRadii.sm),
      child: InputDecorator(
        isEmpty: false,
        decoration: InputDecoration(
          labelText: l10n.dashboardSettingsTimezoneLabel,
          helperText: l10n.dashboardSettingsTimezoneHint,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: const Icon(Icons.public),
          enabled: enabled,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(primary, style: theme.textTheme.bodyLarge),
            if (subtitleParts.isNotEmpty)
              Text(
                subtitleParts.join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: kRestoflowInk3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final pick = await showDialog<_TimezonePick>(
      context: context,
      builder: (context) => _TimezonePickerDialog(
        l10n: l10n,
        options: options,
        selected: selected ?? currentTimezone,
      ),
    );
    if (pick != null) onChanged(pick.id);
  }
}

/// The searchable dialog. A search box filters the full catalog; the first row
/// is "leave unchanged"; the pilot default is highlighted.
class _TimezonePickerDialog extends StatefulWidget {
  const _TimezonePickerDialog({
    required this.l10n,
    required this.options,
    required this.selected,
  });

  final AppLocalizations l10n;
  final List<TimezoneOption> options;
  final String? selected;

  @override
  State<_TimezonePickerDialog> createState() => _TimezonePickerDialogState();
}

class _TimezonePickerDialogState extends State<_TimezonePickerDialog> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    final filtered = widget.options
        .where((o) => timezoneMatches(l10n, o, _query))
        .toList(growable: false);
    return Dialog(
      key: const Key('timezone-picker-dialog'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(RestoflowSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.timezonePickerTitle,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        key: const Key('timezone-picker-close'),
                        tooltip: l10n.activityLogClose,
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: RestoflowSpacing.sm),
                  TextField(
                    key: const Key('timezone-search'),
                    controller: _search,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: l10n.timezonePickerSearchHint,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    key: const Key('timezone-leave-unchanged'),
                    leading: const Icon(Icons.remove_circle_outline),
                    title: Text(l10n.dashboardSettingsTimezoneKeep),
                    onTap: () =>
                        Navigator.of(context).pop(const _TimezonePick(null)),
                  ),
                  const Divider(height: 1),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(RestoflowSpacing.xl),
                      child: Center(
                        child: Text(
                          l10n.timezonePickerNoResults,
                          key: const Key('timezone-no-results'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: kRestoflowInk3,
                          ),
                        ),
                      ),
                    )
                  else
                    for (final o in filtered)
                      ListTile(
                        key: Key('timezone-option-${o.id}'),
                        dense: true,
                        selected: o.id == widget.selected,
                        leading: o.id == kPilotDefaultTimezone
                            ? const Icon(
                                Icons.star,
                                size: RestoflowIconSizes.sm,
                              )
                            : const Icon(
                                Icons.schedule,
                                size: RestoflowIconSizes.sm,
                              ),
                        title: Text(timezoneLabel(l10n, o.id)),
                        subtitle: Text(
                          '${o.id}  ·  ${formatTimezoneOffset(o.offsetMinutes)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () =>
                            Navigator.of(context).pop(_TimezonePick(o.id)),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
