import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// PRINT-BRANDING-LOGO-001 (§5) — the transport result must distinguish a
/// failure BEFORE the send began (nothing printed) from a failure AFTER it began
/// (partial print possible), so the receipt layer never auto-resends the latter.
void main() {
  test('success is ok and marks the send as started', () {
    const r = PrintResult.success();
    expect(r.ok, isTrue);
    expect(r.sendStarted, isTrue);
  });

  test('a pre-send failure did not start the send', () {
    const r = PrintResult.failure(PrinterErrorCategory.unreachable, 'refused');
    expect(r.ok, isFalse);
    expect(r.sendStarted, isFalse);
    expect(r.bytesSent, isNull);
  });

  test('a post-send failure marks sendStarted + carries bytesSent', () {
    const r = PrintResult.failureAfterSend(
      PrinterErrorCategory.writeFailed,
      message: 'dropped',
      bytesSent: 256,
    );
    expect(r.ok, isFalse);
    expect(r.sendStarted, isTrue);
    expect(r.bytesSent, 256);
    expect(r.category, PrinterErrorCategory.writeFailed);
  });
}
