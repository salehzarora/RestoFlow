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
class ReadyNotificationBell extends ConsumerWidget {
  const ReadyNotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final unread = ref.watch(
      posReadyNotificationsControllerProvider.select((s) => s.unreadCount),
    );
    final icon = IconButton(
      key: const Key('ready-bell-button'),
      tooltip: l10n.posReadyBellTooltip,
      icon: const Icon(Icons.notifications_outlined),
      onPressed: () => ReadyNotificationsSheet.show(context),
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
