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

/// PRINT-BRANDING-LOGO-001 (§4): the PHYSICAL dispatch stage of a print attempt —
/// the single fact the customer-receipt layer needs to decide whether an
/// automatic resend is SAFE. It is about the printer payload, not the method
/// call: a Bluetooth connect that failed invoked the native method but PROVED no
/// bytes reached the printer, so it is [failedBeforeDispatch] (safe to retry),
/// whereas a lost response AFTER the write began is [partialOrUnknownAfterDispatch]
/// (a partial print may exist — never auto-resend).
enum PrintPhysicalOutcome {
  /// No print payload was ever handed toward the device (nothing attempted).
  notStarted,

  /// The transport reported the bytes were delivered (best-effort success).
  completed,

  /// The attempt failed BEFORE any payload byte could reach the printer
  /// (permission / pairing / adapter / connect). Zero payload dispatch is
  /// proven, so an automatic retry is safe where the failure could succeed later.
  failedBeforeDispatch,

  /// The payload send BEGAN (or the outcome is unknown after dispatch): a
  /// partial or complete physical print may exist. NEVER auto-resend.
  partialOrUnknownAfterDispatch,
}

/// The result of attempting to send bytes to a printer.
///
/// PRINT-BRANDING-LOGO-001 (§4/§5): a failure carries whether the transport had
/// already begun handing bytes to the OS/device ([sendStarted] / [physicalOutcome])
/// and, when the transport can tell, how many bytes it wrote ([bytesSent],
/// null == unknown, never a misleading 0). A failure with
/// [partialOrUnknownAfterDispatch] is NOT safely distinguishable from a partial
/// physical print, so the customer-receipt layer must never auto-resend after it.
class PrintResult {
  const PrintResult._({
    required this.ok,
    required this.physicalOutcome,
    this.category,
    this.message,
    this.sendStarted = false,
    this.bytesSent,
  });

  /// A successful (best-effort) send.
  const PrintResult.success()
    : this._(
        ok: true,
        sendStarted: true,
        physicalOutcome: PrintPhysicalOutcome.completed,
      );

  /// A failed send carrying a human-mappable [category] (RF-071 maps these to
  /// retry/abandon) and an optional diagnostic [message] (never UI chrome).
  /// Use this for a failure BEFORE the transport began sending (connect/setup),
  /// where no bytes reached the device.
  const PrintResult.failure(PrinterErrorCategory category, [String? message])
    : this._(
        ok: false,
        category: category,
        message: message,
        physicalOutcome: PrintPhysicalOutcome.failedBeforeDispatch,
      );

  /// A failure AFTER the transport began handing bytes to the OS/device — the
  /// physical outcome is UNKNOWN (a partial print may have occurred). The caller
  /// MUST NOT automatically resend. [bytesSent] is provided only when the
  /// transport can count it (e.g. Bluetooth chunked writes); it stays null when
  /// the count is unknown (a timeout may prevent ever learning it) — never 0.
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
         physicalOutcome: PrintPhysicalOutcome.partialOrUnknownAfterDispatch,
       );

  /// Whether the send succeeded.
  final bool ok;

  /// The structured failure category when [ok] is false.
  final PrinterErrorCategory? category;

  /// A developer-facing diagnostic (optional).
  final String? message;

  /// Whether the transport had begun handing bytes to the OS/device. True for a
  /// success (bytes were sent) and for any failure that occurred after the send
  /// began; false for a pure pre-send (connect/setup) failure. Equivalent to
  /// [physicalOutcome] being [PrintPhysicalOutcome.partialOrUnknownAfterDispatch]
  /// (or [PrintPhysicalOutcome.completed]).
  final bool sendStarted;

  /// The number of bytes the transport is known to have written, when it can
  /// count them (else null / unknown — never a misleading 0).
  final int? bytesSent;

  /// PRINT-BRANDING-LOGO-001 (§4): the physical dispatch stage — the resend-safety
  /// signal that survives every layer (transport → bridge → receipt controller).
  final PrintPhysicalOutcome physicalOutcome;

  @override
  String toString() => ok
      ? 'PrintResult.success'
      : 'PrintResult.failure($category, outcome: ${physicalOutcome.name}, '
            'sendStarted: $sendStarted, bytesSent: $bytesSent, $message)';
}
