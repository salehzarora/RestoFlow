/// ADMIN-126B — the marker the Dashboard reads to know it is being viewed by a
/// platform support operator rather than by the tenant.
///
/// It lives in its own file so the shell can depend on the FACT of support mode
/// without depending on the support gate, its repository, or its RPCs.
///
/// This flag governs presentation only. Everything it hides is already refused
/// by the server for a support session; nothing it shows is thereby permitted.
/// Deleting it would make the UI misleading, not insecure.
library;

import 'package:flutter/widgets.dart';

class SupportModeScope extends InheritedWidget {
  const SupportModeScope({
    required this.active,
    required super.child,
    super.key,
  });

  final bool active;

  /// False when there is no scope above — the ordinary tenant Dashboard, which
  /// is the overwhelming majority of the time.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SupportModeScope>()?.active ??
      false;

  @override
  bool updateShouldNotify(SupportModeScope oldWidget) =>
      oldWidget.active != active;
}
