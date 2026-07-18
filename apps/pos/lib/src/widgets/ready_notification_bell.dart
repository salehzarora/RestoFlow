import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../state/ready_notifications_controller.dart';
import 'ready_notifications_sheet.dart';

/// PSC-001A — the POS app-bar READY-NOTIFICATION bell.
///
/// The exact [RecentOrdersButton] pattern: an icon button with a localized
/// tooltip, wrapped in a count badge that HIDES at zero. The badge shows the
/// UNREAD count (persisted local state — the backend stores readiness, not
/// read state), formatted `99+` beyond two digits. Semantics carry the unread
/// count so a screen reader hears one honest label, not an icon + a number.
///
/// TAPPING THE BELL IS THE ACKNOWLEDGEMENT: it marks every notification this
/// device currently retains as read — persistence first, badge after — and
/// then opens the history sheet. A failed persist keeps the honest unread
/// badge and still opens the sheet (quietly degraded). The tap is
/// single-flight: re-taps while marking or while the sheet is up do nothing,
/// so no overlapping writes and never a second sheet. Notifications arriving
/// AFTER the tap stay unread and alert normally.
class ReadyNotificationBell extends ConsumerStatefulWidget {
  const ReadyNotificationBell({super.key});

  @override
  ConsumerState<ReadyNotificationBell> createState() =>
      _ReadyNotificationBellState();
}

class _ReadyNotificationBellState extends ConsumerState<ReadyNotificationBell> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    try {
      // Serialize the mark-all-current-read and WAIT for the durable result
      // before presenting: success clears the badge, failure leaves it
      // truthful — either way the sheet opens exactly once.
      await ref
          .read(posReadyNotificationsControllerProvider.notifier)
          .markAllCurrentRead();
      if (!mounted) return;
      await ReadyNotificationsSheet.show(context);
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unread = ref.watch(
      posReadyNotificationsControllerProvider.select((s) => s.unreadCount),
    );
    final icon = IconButton(
      key: const Key('ready-bell-button'),
      tooltip: l10n.posReadyBellTooltip,
      icon: const Icon(Icons.notifications_outlined),
      onPressed: _open,
    );
    final child = unread == 0
        ? icon
        : Badge(label: Text(unread > 99 ? '99+' : '$unread'), child: icon);
    return Semantics(
      button: true,
      label: unread == 0
          ? l10n.posReadyBellTooltip
          : '${l10n.posReadyBellTooltip}. $unread ${l10n.posReadyUnreadLabel}',
      child: ExcludeSemantics(child: child),
    );
  }
}
