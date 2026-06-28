/// Browser-print launcher — non-web target (RF-118).
///
/// On every non-web platform (Windows / macOS / Linux / mobile) and in tests
/// there is no browser print dialog, so this is a safe no-op. The web variant
/// ([browser_print_web.dart]) calls `window.print()`. Selected via the
/// conditional import in `browser_print.dart`.
void launchBrowserPrint() {
  // No browser on this target — nothing to print. The print-preview UI still
  // renders; the user can use the OS print path if available.
}
