import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'storefront_models.dart';

/// Picks a wall-clock time; returns `HH:MM` (24 h) or null when dismissed.
typedef StorefrontTimePicker =
    Future<String?> Function(BuildContext context, String initial);

/// Picks a calendar date; returns `YYYY-MM-DD` or null when dismissed.
typedef StorefrontDatePicker =
    Future<String?> Function(BuildContext context, String? initial);

String _two(int n) => n.toString().padLeft(2, '0');

/// The default [StorefrontTimePicker]: the Material time picker, forced to a
/// 24-hour dial so the result maps 1:1 onto the validator's `HH:MM`.
Future<String?> showStorefrontTimePicker(
  BuildContext context,
  String initial,
) async {
  final parts = initial.split(':');
  final hour = parts.length == 2 ? int.tryParse(parts[0]) : null;
  final minute = parts.length == 2 ? int.tryParse(parts[1]) : null;
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: hour ?? 9, minute: minute ?? 0),
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
  if (picked == null) return null;
  return '${_two(picked.hour)}:${_two(picked.minute)}';
}

/// The default [StorefrontDatePicker]: the Material date picker.
Future<String?> showStorefrontDatePicker(
  BuildContext context,
  String? initial,
) async {
  final now = DateTime.now();
  final seed = initial == null ? null : DateTime.tryParse(initial);
  final first = DateTime(now.year - 1);
  final last = DateTime(now.year + 2, 12, 31);
  var start = seed ?? DateTime(now.year, now.month, now.day);
  if (start.isBefore(first)) start = first;
  if (start.isAfter(last)) start = last;
  final picked = await showDatePicker(
    context: context,
    initialDate: start,
    firstDate: first,
    lastDate: last,
  );
  if (picked == null) return null;
  return '${picked.year.toString().padLeft(4, '0')}-${_two(picked.month)}-'
      '${_two(picked.day)}';
}

/// STOREFRONT-PUBLISH-001 — the storefront's opening hours editor.
///
/// A PURE model editor: it renders [value] and reports every edit as a new
/// [OpeningHours] through [onChanged]; it never saves anything itself. Per
/// weekday (Sunday = 0 .. Saturday = 6) up to [OpeningHours.maxWindowsPerDay]
/// windows; a day without a window is "closed". A close time EARLIER than the
/// open time crosses midnight (said so next to the window); open == close is
/// flagged here and blocks saving (the validator refuses it). Duplicate or
/// overlapping windows of a day, and an overnight window running into the
/// next day's window, get an ADVISORY warning only (the validator accepts
/// them, so saving is not blocked). "Add hours" never seeds an exact copy of
/// a window the day already has. Exception dates are "closed all day" or ONE
/// window, capped at [OpeningHours.maxExceptions].
///
/// The times are wall-clock times in the storefront branch's [timezone]
/// (shown; "no time zone yet" when null). The server stays authoritative: its
/// `opening_hours_invalid` refusal is shown by the section.
class OpeningHoursEditor extends StatefulWidget {
  const OpeningHoursEditor({
    required this.value,
    required this.onChanged,
    this.timezone,
    this.enabled = true,
    this.pickTime,
    this.pickDate,
    super.key,
  });

  final OpeningHours value;
  final ValueChanged<OpeningHours> onChanged;

  /// The IANA timezone the times are interpreted in (null = none yet).
  final String? timezone;
  final bool enabled;

  /// Test seams for the pickers (default: the Material pickers).
  final StorefrontTimePicker? pickTime;
  final StorefrontDatePicker? pickDate;

  @override
  State<OpeningHoursEditor> createState() => _OpeningHoursEditorState();
}

class _OpeningHoursEditorState extends State<OpeningHoursEditor> {
  /// A transient note after a refused exception date (duplicate).
  bool _duplicateDate = false;

  StorefrontTimePicker get _pickTime =>
      widget.pickTime ?? showStorefrontTimePicker;
  StorefrontDatePicker get _pickDate =>
      widget.pickDate ?? showStorefrontDatePicker;

  OpeningHours get _v => widget.value;

  /// Rebuilds the weekly list grouped by weekday (0..6), each day's windows in
  /// their current order, with [dayWindows] replacing day [dow].
  void _emitDay(int dow, List<WeeklyWindow> dayWindows) {
    final weekly = <WeeklyWindow>[
      for (var d = 0; d < 7; d++) ...(d == dow ? dayWindows : _v.windowsFor(d)),
    ];
    widget.onChanged(
      OpeningHours(
        weekly: List.unmodifiable(weekly),
        exceptions: _v.exceptions,
      ),
    );
  }

  void _emitExceptions(List<HoursException> exceptions) {
    widget.onChanged(
      OpeningHours(
        weekly: _v.weekly,
        exceptions: List.unmodifiable(exceptions),
      ),
    );
  }

  void _addWindow(int dow) {
    final day = _v.windowsFor(dow);
    if (day.length >= OpeningHours.maxWindowsPerDay ||
        _v.weekly.length >= OpeningHours.maxWeekly) {
      return;
    }
    // DASH-2: never an identical copy of a window the day already has — the
    // seed follows the day's last close (see OpeningHours.suggestWindow).
    _emitDay(dow, [...day, _v.suggestWindow(dow)]);
  }

  void _removeWindow(int dow, int index) {
    final day = [..._v.windowsFor(dow)]..removeAt(index);
    _emitDay(dow, day);
  }

  Future<void> _editWindow(int dow, int index, {required bool open}) async {
    final day = _v.windowsFor(dow);
    final w = day[index];
    final picked = await _pickTime(context, open ? w.open : w.close);
    if (picked == null || !mounted || !isStorefrontHhmm(picked)) return;
    final next = [...day];
    next[index] = WeeklyWindow(
      dow: dow,
      open: open ? picked : w.open,
      close: open ? w.close : picked,
    );
    _emitDay(dow, next);
  }

  Future<void> _addException() async {
    if (_v.exceptions.length >= OpeningHours.maxExceptions) return;
    final date = await _pickDate(context, null);
    if (date == null || !mounted || !isStorefrontDate(date)) return;
    if (_v.exceptions.any((e) => e.date == date)) {
      setState(() => _duplicateDate = true);
      return;
    }
    setState(() => _duplicateDate = false);
    final next = [..._v.exceptions, HoursException.closed(date)]
      ..sort((a, b) => a.date.compareTo(b.date));
    _emitExceptions(next);
  }

  void _removeException(int index) {
    setState(() => _duplicateDate = false);
    _emitExceptions([..._v.exceptions]..removeAt(index));
  }

  void _setExceptionClosed(int index, bool closed) {
    final e = _v.exceptions[index];
    if (e.closed == closed) return;
    final next = [..._v.exceptions];
    next[index] = closed
        ? HoursException.closed(e.date)
        : HoursException.window(date: e.date, open: '09:00', close: '17:00');
    _emitExceptions(next);
  }

  Future<void> _editExceptionTime(int index, {required bool open}) async {
    final e = _v.exceptions[index];
    if (e.closed) return;
    final picked = await _pickTime(context, (open ? e.open : e.close)!);
    if (picked == null || !mounted || !isStorefrontHhmm(picked)) return;
    final next = [..._v.exceptions];
    next[index] = HoursException.window(
      date: e.date,
      open: open ? picked : e.open!,
      close: open ? e.close! : picked,
    );
    _emitExceptions(next);
  }

  String _dayName(AppLocalizations l10n, int dow) => switch (dow) {
    0 => l10n.storefrontHoursSunday,
    1 => l10n.storefrontHoursMonday,
    2 => l10n.storefrontHoursTuesday,
    3 => l10n.storefrontHoursWednesday,
    4 => l10n.storefrontHoursThursday,
    5 => l10n.storefrontHoursFriday,
    _ => l10n.storefrontHoursSaturday,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final timezone = widget.timezone;
    // DASH-2 / OQ-2: ADVISORY only — the server accepts overlapping windows
    // and Save stays enabled; the warnings say why they mislead visitors.
    final overlaps = _v.overlaps();
    // Q-038: touching windows are an ERROR (Save and Publish stay disabled);
    // the manager merges them — the editor never merges them itself.
    final touching = _v.touchingWindows();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          timezone == null
              ? l10n.storefrontHoursNoTimezone
              : l10n.storefrontHoursTimezone(timezone),
          key: const Key('storefront-hours-timezone'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        for (var dow = 0; dow < 7; dow++)
          _day(l10n, theme, dow, overlaps, touching),
        const Divider(height: RestoflowSpacing.xl),
        Text(
          l10n.storefrontHoursExceptionsTitle,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: RestoflowSpacing.xs),
        if (_v.exceptions.isEmpty)
          Text(
            l10n.storefrontHoursExceptionsEmpty,
            style: theme.textTheme.bodySmall,
          ),
        for (var i = 0; i < _v.exceptions.length; i++)
          _exception(l10n, theme, i),
        const SizedBox(height: RestoflowSpacing.xs),
        Wrap(
          spacing: RestoflowSpacing.sm,
          runSpacing: RestoflowSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              key: const Key('storefront-hours-add-exception'),
              onPressed:
                  widget.enabled &&
                      _v.exceptions.length < OpeningHours.maxExceptions
                  ? _addException
                  : null,
              icon: const Icon(Icons.event_outlined),
              label: Text(l10n.storefrontHoursAddException),
            ),
            if (_v.exceptions.length >= OpeningHours.maxExceptions)
              Text(
                l10n.storefrontHoursExceptionsCap(OpeningHours.maxExceptions),
                key: const Key('storefront-hours-exceptions-cap'),
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        if (_duplicateDate)
          Text(
            l10n.storefrontHoursExceptionDuplicate,
            key: const Key('storefront-hours-exception-duplicate'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
      ],
    );
  }

  Widget _day(
    AppLocalizations l10n,
    ThemeData theme,
    int dow,
    List<OpeningHoursOverlap> overlaps,
    List<OpeningHoursOverlap> touching,
  ) {
    final windows = _v.windowsFor(dow);
    final full =
        windows.length >= OpeningHours.maxWindowsPerDay ||
        _v.weekly.length >= OpeningHours.maxWeekly;
    final here = [
      for (final o in overlaps)
        if (o.dow == dow) o.kind,
    ];
    final warning = theme.textTheme.bodySmall?.copyWith(
      color: RestoflowTone.warning.styleOf(theme).accent,
    );
    return Padding(
      key: Key('storefront-hours-day-$dow'),
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: RestoflowSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(_dayName(l10n, dow), style: theme.textTheme.labelLarge),
              if (windows.isEmpty)
                Text(
                  l10n.storefrontHoursClosed,
                  key: Key('storefront-hours-closed-$dow'),
                  style: theme.textTheme.bodySmall,
                ),
              TextButton.icon(
                key: Key('storefront-hours-add-$dow'),
                onPressed: widget.enabled && !full
                    ? () => _addWindow(dow)
                    : null,
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.storefrontHoursAddWindow),
              ),
              if (windows.length >= OpeningHours.maxWindowsPerDay)
                Text(
                  l10n.storefrontHoursDayCap(OpeningHours.maxWindowsPerDay),
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
          for (var i = 0; i < windows.length; i++)
            _windowRow(
              l10n,
              theme,
              id: '$dow-$i',
              open: windows[i].open,
              close: windows[i].close,
              crossesMidnight: windows[i].crossesMidnight,
              onOpen: () => _editWindow(dow, i, open: true),
              onClose: () => _editWindow(dow, i, open: false),
              onRemove: () => _removeWindow(dow, i),
            ),
          if (here.contains(OpeningHoursOverlapKind.duplicate))
            _advisory(
              l10n.storefrontHoursDuplicateWarning,
              Key('storefront-hours-duplicate-$dow'),
              warning,
            ),
          if (here.contains(OpeningHoursOverlapKind.sameDay))
            _advisory(
              l10n.storefrontHoursOverlapWarning,
              Key('storefront-hours-overlap-$dow'),
              warning,
            ),
          if (touching.any((t) => t.dow == dow || t.otherDow == dow))
            _advisory(
              l10n.storefrontHoursTouchingError,
              Key('storefront-hours-touching-$dow'),
              theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          if (here.contains(OpeningHoursOverlapKind.overnightSpill))
            _advisory(
              l10n.storefrontHoursSpillWarning(_dayName(l10n, (dow + 1) % 7)),
              Key('storefront-hours-spill-$dow'),
              warning,
            ),
        ],
      ),
    );
  }

  Widget _advisory(String text, Key key, TextStyle? style) => Padding(
    padding: const EdgeInsetsDirectional.only(
      start: RestoflowSpacing.md,
      top: RestoflowSpacing.xxs,
    ),
    child: Text(text, key: key, style: style),
  );

  Widget _exception(AppLocalizations l10n, ThemeData theme, int index) {
    final e = _v.exceptions[index];
    return Padding(
      key: Key('storefront-hours-exception-$index'),
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: RestoflowSpacing.sm,
            runSpacing: RestoflowSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // The date is an LTR island in ar/he.
              Text(
                e.date,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.labelLarge,
              ),
              ChoiceChip(
                key: Key('storefront-hours-exception-closed-$index'),
                label: Text(l10n.storefrontHoursExceptionClosed),
                selected: e.closed,
                onSelected: widget.enabled
                    ? (_) => _setExceptionClosed(index, true)
                    : null,
              ),
              ChoiceChip(
                key: Key('storefront-hours-exception-window-$index'),
                label: Text(l10n.storefrontHoursExceptionWindow),
                selected: !e.closed,
                onSelected: widget.enabled
                    ? (_) => _setExceptionClosed(index, false)
                    : null,
              ),
              IconButton(
                key: Key('storefront-hours-exception-remove-$index'),
                tooltip: l10n.storefrontHoursRemove,
                onPressed: widget.enabled
                    ? () => _removeException(index)
                    : null,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (!e.closed)
            _windowRow(
              l10n,
              theme,
              id: 'x$index',
              open: e.open!,
              close: e.close!,
              crossesMidnight: e.crossesMidnight,
              onOpen: () => _editExceptionTime(index, open: true),
              onClose: () => _editExceptionTime(index, open: false),
            ),
        ],
      ),
    );
  }

  /// One window: Opens / Closes buttons (times as LTR islands), an optional
  /// remove button, the "closes the next day" note and the open == close
  /// error. [id] is `<dow>-<i>` for weekly windows, `x<i>` for exceptions.
  Widget _windowRow(
    AppLocalizations l10n,
    ThemeData theme, {
    required String id,
    required String open,
    required String close,
    required bool crossesMidnight,
    required VoidCallback onOpen,
    required VoidCallback onClose,
    VoidCallback? onRemove,
  }) {
    final equal = open == close;
    Widget time(String keyName, String label, String value, VoidCallback cb) =>
        OutlinedButton(
          key: Key('storefront-hours-$keyName-$id'),
          onPressed: widget.enabled ? cb : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              const SizedBox(width: RestoflowSpacing.xs),
              Text(value, textDirection: TextDirection.ltr),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: RestoflowSpacing.md,
        top: RestoflowSpacing.xxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: RestoflowSpacing.sm,
            runSpacing: RestoflowSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              time('open', l10n.storefrontHoursOpens, open, onOpen),
              time('close', l10n.storefrontHoursCloses, close, onClose),
              if (onRemove != null)
                IconButton(
                  key: Key('storefront-hours-remove-$id'),
                  tooltip: l10n.storefrontHoursRemove,
                  onPressed: widget.enabled ? onRemove : null,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          if (crossesMidnight && !equal)
            Text(
              l10n.storefrontHoursOvernight,
              key: Key('storefront-hours-overnight-$id'),
              style: theme.textTheme.bodySmall,
            ),
          if (equal)
            Text(
              l10n.storefrontHoursOpenEqualsClose,
              key: Key('storefront-hours-error-$id'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}
