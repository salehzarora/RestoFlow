/// The outcome of a print/transport attempt (RF-070).
///
/// Self-contained (no dependency on restoflow_core) — printing is a leaf,
/// hardware-free package. Job identity, retry, and persistence are NOT modelled
/// here (that is the RF-071 spool); this is a single best-effort result.
enum PrinterErrorCategory {
  /// The requested transport/capability is not implemented (e.g. network/USB/BT
  /// in RF-070, or a profile lacking cut/drawer/raster).
  unsupported,

  /// The printer could not be reached (network down, cable unplugged, or a
  /// Bluetooth connect failure/timeout — printer off / out of range).
  unreachable,

  /// The printer is out of paper.
  paperOut,

  /// The printer cover/lid is open.
  coverOpen,

  /// PRINT-BLUETOOTH-RECOVERY-001: the runtime permission the transport needs
  /// (Android 12+ BLUETOOTH_CONNECT) is not granted — the operator must grant
  /// it; retrying without it can never succeed.
  permissionDenied,

  /// PRINT-BLUETOOTH-RECOVERY-001: the device's Bluetooth adapter is off.
  bluetoothOff,

  /// PRINT-BLUETOOTH-RECOVERY-001: the target Bluetooth device is not
  /// paired/bonded in the OS settings — pair it there first.
  notPaired,

  /// PRINT-BLUETOOTH-RECOVERY-001: the connection opened but sending the
  /// print data failed mid-write (printer dropped the link / buffer error).
  writeFailed,

  /// An unclassified failure.
  unknown,
}

/// The result of attempting to send bytes to a printer.
///
/// PRINT-BRANDING-LOGO-001 (§5): a failure carries whether the transport had
/// already begun handing bytes to the OS/device ([sendStarted]) and, when the
/// transport can tell, how many bytes it wrote ([bytesSent]). A failure with
/// [sendStarted] true is NOT safely distinguishable from a partial physical
/// print, so the customer-receipt layer must never auto-resend after it.
class PrintResult {
  const PrintResult._({
    required this.ok,
    this.category,
    this.message,
    this.sendStarted = false,
    this.bytesSent,
  });

  /// A successful (best-effort) send.
  const PrintResult.success() : this._(ok: true, sendStarted: true);

  /// A failed send carrying a human-mappable [category] (RF-071 maps these to
  /// retry/abandon) and an optional diagnostic [message] (never UI chrome).
  /// Use this for a failure BEFORE the transport began sending (connect/setup),
  /// where no bytes reached the device.
  const PrintResult.failure(PrinterErrorCategory category, [String? message])
    : this._(ok: false, category: category, message: message);

  /// A failure AFTER the transport began handing bytes to the OS/device — the
  /// physical outcome is UNKNOWN (a partial print may have occurred). The caller
  /// MUST NOT automatically resend. [bytesSent] is provided only when the
  /// transport can count it (e.g. Bluetooth chunked writes).
  const PrintResult.failureAfterSend(
    PrinterErrorCategory category, {
    String? message,
    int? bytesSent,
  }) : this._(
         ok: false,
         category: category,
         message: message,
         sendStarted: true,
         bytesSent: bytesSent,
       );

  /// Whether the send succeeded.
  final bool ok;

  /// The structured failure category when [ok] is false.
  final PrinterErrorCategory? category;

  /// A developer-facing diagnostic (optional).
  final String? message;

  /// Whether the transport had begun handing bytes to the OS/device. True for a
  /// success (bytes were sent) and for any failure that occurred after the send
  /// began; false for a pure pre-send (connect/setup) failure.
  final bool sendStarted;

  /// The number of bytes the transport is known to have written, when it can
  /// count them (else null / unknown).
  final int? bytesSent;

  @override
  String toString() => ok
      ? 'PrintResult.success'
      : 'PrintResult.failure($category, sendStarted: $sendStarted, '
            'bytesSent: $bytesSent, $message)';
}
