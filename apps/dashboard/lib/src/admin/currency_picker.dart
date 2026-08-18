/// A searchable operating-currency picker for Dashboard Settings
/// (MENU-ADMIN-CURRENCY-SIMPLIFICATION-OPS-043 Phase 1, D1/D2).
///
/// D2's target is FULL ISO-4217, so the control has to survive a catalog of
/// ~150 codes. A plain dropdown does not: it becomes an unscannable wall on a
/// tablet, and only the codes near the current one are even reachable without
/// dragging. This mirrors [TimezonePickerField], which solved the identical
/// "global catalog in a settings row" problem: a labelled field showing the
/// current value, opening a searchable dialog.
///
/// What is OFFERED comes from the shared currency module, never from here:
/// `selectableCurrencies()` applies the Phase gate (exponent-2 only until
/// Phase 2 replaces the hardcoded 2-decimal sites). This widget only renders
/// what it is given.
library;

import 'package:flutter/material.dart';
import 'package:restoflow_currency/restoflow_currency.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// The field. [currentCode] is the restaurant's operating currency as the
/// server has it (null when unknown — then the field says so rather than
/// guessing). [isInherited] drives the provenance line: inherited from the
/// organization default, or set on this restaurant.
class CurrencyPickerField extends StatelessWidget {
  const CurrencyPickerField({
    required this.l10n,
    required this.currentCode,
    required this.isInherited,
    required this.onPicked,
    this.enabled = true,
    this.busy = false,
    super.key,
  });

  final AppLocalizations l10n;
  final String? currentCode;
  final bool isInherited;
  final ValueChanged<String> onPicked;
  final bool enabled;

  /// A write is in flight: the field is inert and says so.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = currentCode == null
        ? '—'
        : currencySelectorLabel(currentCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const Key('settings-operating-currency'),
          onTap: enabled && !busy ? () => _open(context) : null,
          borderRadius: BorderRadius.circular(RestoflowRadii.sm),
          child: InputDecorator(
            isEmpty: false,
            decoration: InputDecoration(
              labelText: l10n.dashboardSettingsOperatingCurrency,
              helperText: l10n.dashboardSettingsOperatingCurrencyHint,
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: busy
                  ? const Padding(
                      padding: EdgeInsets.all(RestoflowSpacing.sm),
                      child: SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Icon(Icons.payments_outlined),
              enabled: enabled,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: theme.textTheme.bodyLarge),
                Text(
                  isInherited
                      ? l10n.dashboardSettingsCurrencyInherited
                      : l10n.dashboardSettingsCurrencyOverridden,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: kRestoflowInk3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: RestoflowSpacing.xs),
        // The server applies `currency_override = coalesce(v_cur, ...)`, so it
        // can SET an override and can never CLEAR one. Saying that beats
        // offering an "inherit" choice that would silently do nothing.
        Text(
          l10n.dashboardSettingsCurrencyOverrideNote,
          style: theme.textTheme.bodySmall?.copyWith(color: kRestoflowInk3),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) =>
          _CurrencyPickerDialog(l10n: l10n, selected: currentCode),
    );
    if (picked != null) onPicked(picked);
  }
}

/// The searchable dialog over the SELECTABLE catalog.
class _CurrencyPickerDialog extends StatefulWidget {
  const _CurrencyPickerDialog({required this.l10n, required this.selected});

  final AppLocalizations l10n;
  final String? selected;

  @override
  State<_CurrencyPickerDialog> createState() => _CurrencyPickerDialogState();
}

class _CurrencyPickerDialogState extends State<_CurrencyPickerDialog> {
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
    final query = _query.trim().toUpperCase();
    final filtered = selectableCurrencies()
        .where(
          (c) =>
              query.isEmpty ||
              c.code.contains(query) ||
              (c.symbol?.contains(_query.trim()) ?? false),
        )
        .toList(growable: false);
    return Dialog(
      key: const Key('currency-picker-dialog'),
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
                          l10n.dashboardSettingsOperatingCurrency,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        key: const Key('currency-picker-close'),
                        tooltip: l10n.activityLogClose,
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: RestoflowSpacing.sm),
                  TextField(
                    key: const Key('currency-search'),
                    controller: _search,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      // The code IS the search key: an ISO code is what a
                      // restaurant owner knows, and translating ~150 currency
                      // NAMES into three languages would be a maintenance
                      // liability with no payoff.
                      hintText: l10n.dashboardSettingsCurrencySearchHint,
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
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(RestoflowSpacing.xl),
                      child: Center(
                        child: Text(
                          l10n.timezonePickerNoResults,
                          key: const Key('currency-no-results'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: kRestoflowInk3,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final info = filtered[index];
                        return ListTile(
                          key: Key('settings-currency-${info.code}'),
                          dense: true,
                          selected: info.code == widget.selected,
                          leading: const Icon(
                            Icons.payments_outlined,
                            size: RestoflowIconSizes.sm,
                          ),
                          title: Text(currencySelectorLabel(info.code)),
                          onTap: () => Navigator.of(context).pop(info.code),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
