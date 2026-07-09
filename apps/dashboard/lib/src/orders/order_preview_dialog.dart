/// The reprint-center preview dialog (ORDERS-HISTORY-001).
///
/// Renders a [PrintDocument] (receipt OR money-free kitchen ticket) on screen and
/// offers "Print from browser" (a real browser print of ONLY this document — the
/// Dashboard has no hardware printer path, so it is honest about pointing
/// hardware reprint to the POS/KDS device). It NEVER records a payment, creates
/// an order, or mutates a kitchen job — it re-renders stored data.
library;

import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../print/browser_print.dart';
import '../print/print_document.dart';

/// Shows the preview dialog for [doc]. [hint] is the honest hardware-reprint note
/// (use the POS or KDS device). [previewKey] tags the rendered document for tests.
Future<void> showOrderPreviewDialog(
  BuildContext context, {
  required PrintDocument doc,
  required String hint,
  required Key previewKey,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        OrderPreviewDialog(doc: doc, hint: hint, previewKey: previewKey),
  );
}

class OrderPreviewDialog extends StatelessWidget {
  const OrderPreviewDialog({
    required this.doc,
    required this.hint,
    required this.previewKey,
    super.key,
  });

  final PrintDocument doc;
  final String hint;
  final Key previewKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(RestoflowSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(doc.title, style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    key: const Key('order-preview-close'),
                    tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(RestoflowSpacing.lg),
                child: Center(
                  child: Container(
                    key: previewKey,
                    constraints: const BoxConstraints(maxWidth: 300),
                    padding: const EdgeInsets.all(RestoflowSpacing.md),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: kRestoflowHairline),
                      borderRadius: BorderRadius.circular(RestoflowRadii.sm),
                    ),
                    child: _PrintDocumentView(doc: doc),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(RestoflowSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: RestoflowIconSizes.sm,
                        color: kRestoflowInk3,
                      ),
                      const SizedBox(width: RestoflowSpacing.xs),
                      Expanded(
                        child: Text(
                          hint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: kRestoflowInk3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: RestoflowSpacing.md),
                  FilledButton.icon(
                    key: const Key('order-preview-print'),
                    onPressed: () =>
                        printHtmlDocument(documentToHtml(doc), doc.title),
                    icon: const Icon(Icons.print_outlined),
                    label: Text(l10n.ordersPrintFromBrowser),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a [PrintDocument] as an on-screen narrow monospace receipt preview.
class _PrintDocumentView extends StatelessWidget {
  const _PrintDocumentView({required this.doc});

  final PrintDocument doc;

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      color: Colors.black,
    );
    final rows = <Widget>[];
    for (final line in doc.lines) {
      switch (line.kind) {
        case PrintLineKind.title:
          rows.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                line.left ?? '',
                textAlign: TextAlign.center,
                style: mono.copyWith(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
          );
        case PrintLineKind.center:
          rows.add(
            Text(
              line.left ?? '',
              textAlign: TextAlign.center,
              style: mono.copyWith(fontWeight: FontWeight.w700),
            ),
          );
        case PrintLineKind.keyValue:
        case PrintLineKind.item:
          rows.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(line.left ?? '', style: mono)),
                  if ((line.right ?? '').isNotEmpty)
                    Text(
                      line.right!,
                      style: mono.copyWith(
                        fontWeight: line.emphasised
                            ? FontWeight.w900
                            : FontWeight.normal,
                      ),
                    ),
                ],
              ),
            ),
          );
        case PrintLineKind.sub:
          rows.add(
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 12,
                top: 1,
                bottom: 1,
              ),
              child: Text(
                line.left ?? '',
                style: mono.copyWith(fontSize: 11, color: Colors.black54),
              ),
            ),
          );
        case PrintLineKind.note:
          rows.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                line.left ?? '',
                textAlign: TextAlign.center,
                style: mono.copyWith(fontSize: 11, color: Colors.black54),
              ),
            ),
          );
        case PrintLineKind.rule:
          rows.add(
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: DottedHairline(),
            ),
          );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// A thin dashed hairline for the on-screen receipt preview.
class DottedHairline extends StatelessWidget {
  const DottedHairline({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 1,
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black26)),
      ),
    ),
  );
}
