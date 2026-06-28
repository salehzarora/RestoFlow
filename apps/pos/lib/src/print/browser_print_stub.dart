/// Isolated browser-print launcher — non-web target (RF-118).
///
/// On every non-web platform (Windows / macOS / Linux / mobile) and in tests
/// there is no browser, so this is a safe no-op — the on-screen preview still
/// renders. The web variant ([browser_print_web.dart]) opens the document in an
/// isolated window and prints only it. Selected via the conditional export in
/// `browser_print.dart`.
void printHtmlDocument(String htmlContent, String title) {
  // No browser on this target — nothing to print here.
}
