import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'browser_print.dart';
import 'print_document.dart';

/// The print seam (RF-118 fix): prints a [PrintDocument] as an ISOLATED
/// document, never the Flutter KDS board page. Mockable via [printServiceProvider]
/// so tests capture the document and never open a real print dialog. Not a
/// hardware-printer integration.
abstract class PrintService {
  void printDocument(PrintDocument document);
}

/// Default service: renders the document to HTML and prints it in an isolated
/// browser window (web), or no-ops on non-web targets.
class DefaultPrintService implements PrintService {
  const DefaultPrintService();

  @override
  void printDocument(PrintDocument document) =>
      printHtmlDocument(documentToHtml(document), document.title);
}

final printServiceProvider = Provider<PrintService>(
  (ref) => const DefaultPrintService(),
);
