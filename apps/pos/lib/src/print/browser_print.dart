import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'browser_print_stub.dart'
    if (dart.library.html) 'browser_print_web.dart';

/// The browser-print action (RF-118), behind a mockable Riverpod provider.
///
/// The default action calls the platform launcher: `window.print()` on web (a
/// real browser print of the page, showing the print-preview overlay), and a
/// safe no-op on every other target and in tests. Tests override this provider
/// with a spy so they never open an OS/browser print dialog. This is NOT a
/// hardware-printer integration.
final printActionProvider = Provider<void Function()>(
  (ref) => launchBrowserPrint,
);
