/// The kitchen-ticket print-document model now lives in the shared
/// `restoflow_feature_kitchen` package (KITCHEN-PRINT-DUAL-001B), so the POS
/// direct kitchen print and the KDS share ONE model + layout builder. This file
/// stays as a stable re-export so every existing KDS `import '../print/
/// print_document.dart'` keeps resolving the same [PrintDocument] / [PrintLine]
/// / [PrintLineKind] / [documentToHtml] — unchanged behavior.
export 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show PrintDocument, PrintLine, PrintLineKind, documentToHtml;
