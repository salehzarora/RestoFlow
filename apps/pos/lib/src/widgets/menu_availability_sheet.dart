import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_menu.dart';
import '../data/menu_availability_repository.dart';
import '../state/menu_availability_controller.dart';
import '../state/pos_menu_provider.dart';

/// PILOT-OPERATIONS-CORRECTIONS-001 — the POS cashier availability management sheet.
///
/// Opened by a DELIBERATE long-press on a menu tile, ONLY for an operator with
/// `manage_menu_availability`. Shows the item, its CURRENT authoritative state, and
/// the three targets (Available / Sold out / Paused). A deliberate choice submits
/// the `menu.availability_set` operation (online-required); success reconciles the
/// menu from the server; a typed denial or an offline failure keeps the previous
/// state and shows a localized message — never a fake success.
class MenuAvailabilitySheet extends ConsumerStatefulWidget {
  const MenuAvailabilitySheet({required this.item, super.key});

  final DemoMenuItem item;

  static Future<void> show(BuildContext context, {required DemoMenuItem item}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MenuAvailabilitySheet(item: item),
    );
  }

  @override
  ConsumerState<MenuAvailabilitySheet> createState() =>
      _MenuAvailabilitySheetState();
}

class _MenuAvailabilitySheetState extends ConsumerState<MenuAvailabilitySheet> {
  bool _submitting = false;
  String? _errorCode;

  Future<void> _choose(String availability, String? reason) async {
    if (_submitting) return; // disable duplicate confirmation while running
    // No-op if it already matches the current authoritative state.
    final current = widget.item.availability;
    final currentReason = widget.item.availabilityReason;
    if (availability == current &&
        (availability == 'available' || reason == currentReason)) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _submitting = true;
      _errorCode = null;
    });
    try {
      await ref
          .read(menuAvailabilityRepositoryProvider)
          .setAvailability(
            menuItemId: widget.item.id,
            availability: availability,
            reason: reason,
          );
      // Reconcile the tile from the authoritative read model. In demo the overlay
      // already updated the provider; invalidating re-runs the fetch in real mode.
      ref.invalidate(posMenuProvider);
      if (mounted) Navigator.of(context).maybePop();
    } on MenuAvailabilityException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorCode = e.code;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorCode = 'rejected';
      });
    }
  }

  String _errorMessage(AppLocalizations l10n, String code) => switch (code) {
    'offline' => l10n.posMenuAvailabilityOffline,
    'permission_denied' => l10n.posMenuAvailabilityDenied,
    'not_found' => l10n.posMenuAvailabilityFailed,
    _ => l10n.posMenuAvailabilityFailed,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final item = widget.item;
    final isAvailable = item.availability == 'available';
    final isSoldOut = item.isUnavailable && item.availabilityReason != 'paused';
    final isPaused = item.isUnavailable && item.availabilityReason == 'paused';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.posMenuChangeAvailability,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.xxs),
            Text(
              item.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            _OptionTile(
              key: const Key('availability-option-available'),
              icon: Icons.check_circle_outline,
              tone: RestoflowTone.success,
              label: l10n.posMenuAvailAvailable,
              selected: isAvailable,
              enabled: !_submitting,
              onTap: () => _choose('available', null),
            ),
            _OptionTile(
              key: const Key('availability-option-sold-out'),
              icon: Icons.do_not_disturb_on_outlined,
              tone: RestoflowTone.danger,
              label: l10n.posMenuItemSoldOut,
              selected: isSoldOut,
              enabled: !_submitting,
              onTap: () => _choose('unavailable', 'sold_out'),
            ),
            _OptionTile(
              key: const Key('availability-option-paused'),
              icon: Icons.pause_circle_outline,
              tone: RestoflowTone.warning,
              label: l10n.posMenuItemPaused,
              selected: isPaused,
              enabled: !_submitting,
              onTap: () => _choose('unavailable', 'paused'),
            ),
            if (_submitting)
              const Padding(
                key: Key('availability-submitting'),
                padding: EdgeInsets.only(top: RestoflowSpacing.sm),
                child: LinearProgressIndicator(),
              ),
            if (_errorCode != null)
              Padding(
                padding: const EdgeInsets.only(top: RestoflowSpacing.sm),
                child: RestoflowNoticeBanner(
                  key: const Key('availability-error'),
                  tone: RestoflowTone.danger,
                  icon: Icons.error_outline,
                  body: _errorMessage(l10n, _errorCode!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.tone,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final RestoflowTone tone;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: tone.styleOf(theme).accent),
      title: Text(label),
      trailing: selected
          ? Icon(Icons.radio_button_checked, color: theme.colorScheme.primary)
          : const Icon(Icons.radio_button_unchecked),
      enabled: enabled,
      onTap: enabled ? onTap : null,
    );
  }
}
