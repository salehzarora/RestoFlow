/// Paper width (RF-070). Both MUST stay supported (PRINTERS spec §4); 80mm is
/// the default for legibility, 58mm for compact/portable.
enum PaperWidth { mm58, mm80 }

/// An ESC/POS code page selectable via `ESC t n` (RF-070, approved A6).
///
/// CP437/PC437 is the deterministic default for golden tests. The pilot code
/// page and the Arabic/Hebrew strategy are NOT frozen here (OPEN QUESTION
/// Q-015); ar/he go through the raster path (RF-073), not a code page.
enum CodePage {
  /// PC437 (USA / standard Europe) — ESC/POS table 0. Default.
  cp437(0),

  /// PC850 (multilingual Latin-1) — table 2.
  cp850(2),

  /// PC858 (Latin-1 + Euro) — table 19.
  cp858(19);

  const CodePage(this.escPosTableId);

  /// The numeric table id used by `ESC t n`.
  final int escPosTableId;
}

/// Per-model capabilities (RF-070). Captures the ESC/POS variation (RISK R-001)
/// the adapter must respect: an unsupported command is omitted, not emitted.
class PrinterCapabilities {
  const PrinterCapabilities({
    this.supportsCut = true,
    this.supportsDrawerKick = true,
    this.supportsRaster = true,
  });

  final bool supportsCut;
  final bool supportsDrawerKick;
  final bool supportsRaster;
}

/// A printer profile: paper width, logical column count, capabilities, and the
/// selected code page (RF-070, PRINTERS spec §13.3). The document is authored in
/// logical columns; the adapter maps them to this profile.
class PrinterProfile {
  const PrinterProfile({
    required this.paperWidth,
    required this.columns,
    this.capabilities = const PrinterCapabilities(),
    this.codePage = CodePage.cp437,
  });

  final PaperWidth paperWidth;

  /// Logical character columns (Font A): ~32 for 58mm, ~48 for 80mm (§4).
  final int columns;

  final PrinterCapabilities capabilities;
  final CodePage codePage;

  /// Deterministic default 80mm profile (the spec default, §4).
  static const PrinterProfile escPos80mm = PrinterProfile(
    paperWidth: PaperWidth.mm80,
    columns: 48,
  );

  /// Deterministic default 58mm profile (compact/portable; MUST stay supported).
  static const PrinterProfile escPos58mm = PrinterProfile(
    paperWidth: PaperWidth.mm58,
    columns: 32,
  );

  PrinterProfile copyWith({
    PaperWidth? paperWidth,
    int? columns,
    PrinterCapabilities? capabilities,
    CodePage? codePage,
  }) {
    return PrinterProfile(
      paperWidth: paperWidth ?? this.paperWidth,
      columns: columns ?? this.columns,
      capabilities: capabilities ?? this.capabilities,
      codePage: codePage ?? this.codePage,
    );
  }
}
