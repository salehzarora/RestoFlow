import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/cash_drawer_manual_repository.dart';
import '../state/cash_drawer_manual_controller.dart';
import '../state/pos_session.dart';

/// POS-CASH-DRAWER-MANUAL-OPEN-001 — the app-bar MANUAL ("no-sale") cash-drawer
/// button.
///
/// One tap opens the drawer once the button is unlocked for the current PIN
/// session; while LOCKED it shows a small lock badge and the tap asks for the
/// employee's own PIN first (and then opens). A long press locks it again. It
/// renders NOTHING unless this till can actually pulse a drawer (native build,
/// a receipt printer with a drawer port, a PIN session) and the employee is not
/// known to lack the permission — so web tills, KDS-style setups and demo mode
/// see an unchanged app bar.
///
/// Below [kPosDrawerInlineMinWidth] the bar keeps its existing cluster and the
/// same action lives in the ⋮ device menu instead ([cashDrawerMenuItems]).
class CashDrawerButton extends ConsumerWidget {
  const CashDrawerButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched BEFORE any early return: the controller (and with it the journal
    // of offline opens it re-sends) lives as long as the POS screen does —
    // whoever is signed in, whatever the bar width.
    final drawer = ref.watch(posCashDrawerManualControllerProvider);
    if (!ref.watch(posManualDrawerVisibleProvider)) {
      return const SizedBox.shrink();
    }
    if (MediaQuery.sizeOf(context).width < kPosDrawerInlineMinWidth) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final session = ref.watch(posSyncSessionProvider);
    final unlocked = drawer.isUnlockedFor(session?.pinSessionId);
    const glyph = Icon(Icons.inbox_outlined);
    return IconButton(
      key: const Key('cash-drawer-button'),
      tooltip: unlocked
          ? l10n.posCashDrawerManualUnlockedTooltip
          : l10n.posCashDrawerManualLockedTooltip,
      icon: unlocked
          ? glyph
          : Badge(
              key: const Key('cash-drawer-lock-badge'),
              padding: const EdgeInsets.all(1),
              backgroundColor: scheme.error,
              label: Icon(Icons.lock, size: 10, color: scheme.onError),
              child: glyph,
            ),
      onPressed: drawer.busy ? null : () => runManualDrawerOpen(context, ref),
      onLongPress: unlocked ? () => lockManualDrawer(context, ref) : null,
    );
  }
}

/// The bar width from which the drawer button sits in the app bar. Narrower
/// bars keep the existing cluster: measured on PosMenuScreen (en/ar/he), an
/// extra 48 px action below ~560 px squeezes the BIZBOT symbol out of the bar
/// entirely, so there the action lives in the ⋮ menu.
const double kPosDrawerInlineMinWidth = 600;

/// The ⋮ menu entries for the same action on a narrower bar: "Open cash drawer"
/// and, once unlocked, "Lock the cash drawer button". Empty when the button
/// would not render on a wide bar either, or when the bar is wide enough for
/// the app-bar button (which owns the action there).
List<PopupMenuEntry<T>> cashDrawerMenuItems<T>({
  required BuildContext context,
  required WidgetRef ref,
  required T openValue,
  required T lockValue,
}) {
  if (!ref.read(posManualDrawerVisibleProvider)) return const [];
  if (MediaQuery.sizeOf(context).width >= kPosDrawerInlineMinWidth) {
    return const [];
  }
  final l10n = AppLocalizations.of(context);
  final unlocked = ref
      .read(posCashDrawerManualControllerProvider)
      .isUnlockedFor(ref.read(posSyncSessionProvider)?.pinSessionId);
  final ink = Theme.of(context).colorScheme.onSurfaceVariant;
  return [
    PopupMenuItem<T>(
      key: const Key('cash-drawer-menu-item'),
      value: openValue,
      child: Row(
        children: [
          Icon(
            unlocked ? Icons.inbox_outlined : Icons.lock_outline,
            size: 20,
            color: ink,
          ),
          const SizedBox(width: 12),
          Flexible(child: Text(l10n.posCashDrawerManualOpen)),
        ],
      ),
    ),
    if (unlocked)
      PopupMenuItem<T>(
        key: const Key('cash-drawer-lock-menu-item'),
        value: lockValue,
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 20, color: ink),
            const SizedBox(width: 12),
            Flexible(child: Text(l10n.posCashDrawerLockAction)),
          ],
        ),
      ),
  ];
}

/// Locks the button and says so.
void lockManualDrawer(BuildContext context, WidgetRef ref) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context);
  ref.read(posCashDrawerManualControllerProvider.notifier).lock();
  messenger?.showSnackBar(
    SnackBar(content: Text(l10n.posCashDrawerLockedNotice)),
  );
}

/// The one tap path shared by the app-bar button and the compact menu item:
/// unlock with the PIN when needed (that unlock opens the drawer at once), then
/// open, then say what happened.
Future<void> runManualDrawerOpen(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context);
  final controller = ref.read(posCashDrawerManualControllerProvider.notifier);
  if (!controller.isUnlocked) {
    final unlocked = await showCashDrawerUnlockDialog(context);
    if (unlocked != true) return;
  }
  final outcome = await controller.open();
  final message = manualDrawerOutcomeMessage(l10n, outcome);
  if (message != null) {
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The one message per outcome (null = say nothing).
String? manualDrawerOutcomeMessage(
  AppLocalizations l10n,
  ManualDrawerOpenOutcome outcome,
) => switch (outcome) {
  ManualDrawerOpenOutcome.opened => l10n.posCashDrawerOpened,
  ManualDrawerOpenOutcome.sendFailed => l10n.posCashDrawerManualOpenFailed,
  ManualDrawerOpenOutcome.noPrinter => l10n.posCashDrawerManualOpenFailed,
  ManualDrawerOpenOutcome.denied => l10n.posCashDrawerNoPermission,
  ManualDrawerOpenOutcome.sessionEnded => l10n.posCashDrawerSessionEnded,
  ManualDrawerOpenOutcome.cannotRecord => l10n.posCashDrawerCannotRecord,
  ManualDrawerOpenOutcome.needsUnlock => null,
  ManualDrawerOpenOutcome.ignored => null,
};

/// Shows the PIN dialog. Resolves true once the button is unlocked for the
/// current session, false/null when cancelled or refused.
Future<bool?> showCashDrawerUnlockDialog(BuildContext context) =>
    showDialog<bool>(
      context: context,
      builder: (_) => const CashDrawerUnlockDialog(),
    );

/// The PIN dialog: the same obscured field + touch keypad the PIN sign-in uses,
/// asking for the signed-in employee's OWN PIN (verified by the server).
class CashDrawerUnlockDialog extends ConsumerStatefulWidget {
  const CashDrawerUnlockDialog({super.key});

  @override
  ConsumerState<CashDrawerUnlockDialog> createState() =>
      _CashDrawerUnlockDialogState();
}

class _CashDrawerUnlockDialogState
    extends ConsumerState<CashDrawerUnlockDialog> {
  static const int _maxPinLength = 8;
  static final RegExp _pinShape = RegExp(r'^[0-9]{4,8}$');

  final TextEditingController _pin = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _locked = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _digit(String d) {
    if (_busy || _pin.text.length >= _maxPinLength) return;
    _pin.text = '${_pin.text}$d';
    if (_error != null) setState(() => _error = null);
  }

  void _backspace() {
    if (_busy || _pin.text.isEmpty) return;
    _pin.text = _pin.text.substring(0, _pin.text.length - 1);
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final pin = _pin.text.trim();
    if (_busy || _locked) return;
    if (!_pinShape.hasMatch(pin)) {
      setState(() => _error = l10n.pinLoginWrongPin);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(posCashDrawerManualControllerProvider.notifier)
        .unlock(pin);
    if (!mounted) return;
    if (result == DrawerUnlockResult.unlocked) {
      Navigator.of(context).pop(true);
      return;
    }
    _pin.clear();
    setState(() {
      _busy = false;
      _locked = result == DrawerUnlockResult.pinLocked;
      _error = switch (result) {
        DrawerUnlockResult.wrongPin => l10n.pinLoginWrongPin,
        DrawerUnlockResult.pinLocked => l10n.pinLoginLocked,
        DrawerUnlockResult.permissionDenied => l10n.posCashDrawerNoPermission,
        DrawerUnlockResult.sessionInvalid => l10n.posCashDrawerSessionEnded,
        DrawerUnlockResult.offline => l10n.posCashDrawerNeedsConnection,
        DrawerUnlockResult.unavailable => l10n.pinLoginUnavailable,
        DrawerUnlockResult.unlocked => null,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = ref.watch(posSignedInStaffNameProvider);
    // While the server checks the PIN the dialog cannot be dismissed (barrier,
    // back): its result decides whether the drawer opens.
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(RestoflowSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 32,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: RestoflowSpacing.sm),
                Text(
                  l10n.posCashDrawerUnlockTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                if (name != null) ...[
                  const SizedBox(height: RestoflowSpacing.xs),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall,
                  ),
                ],
                const SizedBox(height: RestoflowSpacing.xs),
                Text(
                  l10n.posCashDrawerUnlockBody,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: RestoflowSpacing.lg),
                TextField(
                  key: const Key('cash-drawer-pin-input'),
                  controller: _pin,
                  autofocus: true,
                  enabled: !_busy && !_locked,
                  obscureText: true,
                  // The dialog carries its own keypad; the soft keyboard stays
                  // down (a hardware keyboard and tests still type).
                  keyboardType: TextInputType.none,
                  maxLength: _maxPinLength,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: l10n.pinFieldLabel,
                    counterText: '',
                    errorText: _error,
                    errorMaxLines: 3,
                  ),
                ),
                const SizedBox(height: RestoflowSpacing.md),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: RestoflowNumericKeypad(
                      onDigit: _digit,
                      onBackspace: _backspace,
                      enabled: !_busy && !_locked,
                      buttonHeight: 48,
                    ),
                  ),
                ),
                const SizedBox(height: RestoflowSpacing.lg),
                FilledButton(
                  key: const Key('cash-drawer-unlock-submit'),
                  onPressed: (_busy || _locked) ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _busy
                      ? const RestoflowInlineSpinner()
                      : Text(l10n.posCashDrawerUnlockSubmit),
                ),
                const SizedBox(height: RestoflowSpacing.sm),
                TextButton(
                  key: const Key('cash-drawer-unlock-cancel'),
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: Text(l10n.posShiftCancelAction),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
