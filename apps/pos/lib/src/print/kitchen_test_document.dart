import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// KITCHEN-MODE-001B: builds the LOCALIZED money-free kitchen-ticket TEST
/// document and runs it through the SHARED PRINT-RTL-001 raster path.
///
/// With the app-injected rasterizer (the real Android build) Arabic/Hebrew
/// sample lines render as a bitmap exactly like production tickets; without
/// one (web/tests) the ESC/POS text document is returned unchanged (the same
/// documented fallback as every other print path — never a crash). The
/// document itself is STRUCTURALLY money-free (see
/// [pp.escPosKitchenTestDocument]) and creates/reads no order or customer
/// data.
Future<pp.PrintDocument> buildPosKitchenTestDocument(
  WidgetRef ref,
  AppLocalizations l10n, {
  String? printerName,
  String? deviceLabel,
}) async {
  final doc = pp.escPosKitchenTestDocument(
    testBanner: l10n.posKitchenTestBanner,
    title: l10n.posKitchenTestTitle,
    sampleLines: [
      l10n.posKitchenTestSampleItem,
      l10n.posKitchenTestSampleModifier,
      l10n.posKitchenTestSampleNote,
    ],
    printerName: printerName,
    deviceLabel: deviceLabel,
  );
  final rasterizer = ref.read(nativePrintRasterizerProvider);
  if (rasterizer == null) return doc;
  try {
    return await pp.maybeRasterizeForRtl(
      doc,
      rasterizer: rasterizer,
      widthDots: pp.kNativeRasterWidthDots,
    );
  } catch (_) {
    // Raster failure falls back to the text document (documented behavior).
    return doc;
  }
}
