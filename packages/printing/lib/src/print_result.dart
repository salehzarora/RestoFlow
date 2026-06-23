/// The outcome of a print/transport attempt (RF-070).
///
/// Self-contained (no dependency on restoflow_core) — printing is a leaf,
/// hardware-free package. Job identity, retry, and persistence are NOT modelled
/// here (that is the RF-071 spool); this is a single best-effort result.
enum PrinterErrorCategory {
  /// The requested transport/capability is not implemented (e.g. network/USB/BT
  /// in RF-070, or a profile lacking cut/drawer/raster).
  unsupported,

  /// The printer could not be reached (network down, cable unplugged).
  unreachable,

  /// The printer is out of paper.
  paperOut,

  /// The printer cover/lid is open.
  coverOpen,

  /// An unclassified failure.
  unknown,
}

/// The result of attempting to send bytes to a printer.
class PrintResult {
  const PrintResult._({required this.ok, this.category, this.message});

  /// A successful (best-effort) send.
  const PrintResult.success() : this._(ok: true);

  /// A failed send carrying a human-mappable [category] (RF-071 maps these to
  /// retry/abandon) and an optional diagnostic [message] (never UI chrome).
  const PrintResult.failure(PrinterErrorCategory category, [String? message])
    : this._(ok: false, category: category, message: message);

  /// Whether the send succeeded.
  final bool ok;

  /// The structured failure category when [ok] is false.
  final PrinterErrorCategory? category;

  /// A developer-facing diagnostic (optional).
  final String? message;

  @override
  String toString() =>
      ok ? 'PrintResult.success' : 'PrintResult.failure($category, $message)';
}
