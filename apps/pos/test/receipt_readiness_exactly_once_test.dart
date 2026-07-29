import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_printing/restoflow_printing.dart'
    show BridgeSubmitResult;
import 'package:restoflow_pos/src/print/print_document.dart';
import 'package:restoflow_pos/src/print/receipt_logo_asset.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';

/// PRINT-STARTUP-REPRINT-001 (Defect 1) — the paid customer receipt must never
/// be silently dropped while printer state and branding are still resolving.
///
/// Root cause: the payment listener read every async printer source with
/// `.valueOrNull` and returned early while they were unresolved, so on a cold
/// start NO job was created — no status row, no retry, and the payment edge
/// never fires again for that order. Separately the logo controller's `null` was
/// ambiguous (unresolved vs definitively none), so the first receipt that did
/// get through could print without the configured logo.
///
/// These drive the REAL [ReceiptPrintController] and its real dispatch path with
/// a recording bridge; readiness and logo resolution are injected exactly as the
/// widget injects them in production.

/// A bridge that records every submitted document and confirms the write.
class _RecordingBridge {
  final List<PrintDocument> sent = <PrintDocument>[];
  int get count => sent.length;

  Future<BridgeSubmitResult> submit(PrintDocument document) async {
    sent.add(document);
    return const BridgeSubmitResult.sentToPrinter();
  }
}

PrintDocument _doc({bool withLogo = false}) => PrintDocument(
  title: 'RECEIPT',
  lines: [
    if (withLogo) PrintLine.headerImage(_logo),
    PrintLine.title('RESTOFLOW'),
  ],
);

final _logo = ReceiptLogoAsset(
  sourceBytes: Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47]),
  sourceMime: 'image/png',
);

/// True when the built document actually carries the branding image.
bool _hasLogo(PrintDocument d) =>
    d.lines.any((l) => l.kind == PrintLineKind.headerImage && l.logo != null);

ProviderContainer _c() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

ReceiptPrintController _controller(ProviderContainer c) =>
    c.read(receiptPrintControllerProvider.notifier);

const _key = 'order-1';

void main() {
  group('A. cold start no longer drops the paid receipt', () {
    test(
      'the job EXISTS immediately in waitingForPrinter, then dispatches once',
      () async {
        final c = _c();
        final bridge = _RecordingBridge();
        final readiness = Completer<ReceiptReadiness>();

        final flow = _controller(c).requestReceipt(
          orderKey: _key,
          resolveReadiness: () => readiness.future,
          buildDocument: _doc,
          submitToBridge: bridge.submit,
        );

        // The defining assertion: the job is present and honest BEFORE any
        // readiness resolves. Pre-fix there was no job at all.
        await Future<void>.delayed(Duration.zero);
        final waiting = _controller(c).jobFor(_key);
        expect(waiting, isNotNull, reason: 'a paid receipt is never dropped');
        expect(waiting!.status, PrintJobStatus.waitingForPrinter);
        expect(bridge.count, 0, reason: 'nothing is sent while waiting');

        readiness.complete(ReceiptReadiness.configured);
        await flow;

        expect(
          _controller(c).jobFor(_key)!.status,
          PrintJobStatus.sentToPrinter,
        );
        expect(bridge.count, 1, reason: 'dispatched exactly once');
      },
    );
  });

  group('B. first receipt waits for the first definitive logo outcome', () {
    test(
      'no dispatch before logo resolution; first receipt carries the logo',
      () async {
        final c = _c();
        final bridge = _RecordingBridge();
        final logo = Completer<void>();
        var logoResolved = false;

        final flow = _controller(c).requestReceipt(
          orderKey: _key,
          resolveReadiness: () async => ReceiptReadiness.configured,
          awaitLogoReady: () => logo.future,
          buildDocument: () => _doc(withLogo: logoResolved),
          submitToBridge: bridge.submit,
        );

        await Future<void>.delayed(Duration.zero);
        expect(
          bridge.count,
          0,
          reason: 'must not print before the logo resolves',
        );
        expect(
          _controller(c).jobFor(_key)!.status,
          PrintJobStatus.waitingForPrinter,
        );

        logoResolved = true;
        logo.complete();
        await flow;

        expect(bridge.count, 1);
        expect(
          _hasLogo(bridge.sent.single),
          isTrue,
          reason: 'the FIRST receipt carries the configured logo',
        );
      },
    );
  });

  group('C. definitive no-logo still prints', () {
    test('resolves without hanging and uses the logo-less layout', () async {
      final c = _c();
      final bridge = _RecordingBridge();

      await _controller(c).requestReceipt(
        orderKey: _key,
        resolveReadiness: () async => ReceiptReadiness.configured,
        awaitLogoReady: () async {}, // definitively none, resolved
        buildDocument: () => _doc(),
        submitToBridge: bridge.submit,
      );

      expect(bridge.count, 1);
      expect(_hasLogo(bridge.sent.single), isFalse);
      expect(_controller(c).jobFor(_key)!.status, PrintJobStatus.sentToPrinter);
    });

    test('a logo waiter that THROWS never blocks the receipt', () async {
      final c = _c();
      final bridge = _RecordingBridge();

      await _controller(c).requestReceipt(
        orderKey: _key,
        resolveReadiness: () async => ReceiptReadiness.configured,
        awaitLogoReady: () async => throw StateError('logo blew up'),
        buildDocument: () => _doc(),
        submitToBridge: bridge.submit,
      );

      expect(bridge.count, 1, reason: 'text-only fallback still prints');
    });
  });

  group('D. definitively not configured', () {
    test('stays visible and actionable, and sends nothing', () async {
      final c = _c();
      final bridge = _RecordingBridge();

      await _controller(c).requestReceipt(
        orderKey: _key,
        resolveReadiness: () async => ReceiptReadiness.notConfigured,
        buildDocument: _doc,
        submitToBridge: bridge.submit,
      );

      final job = _controller(c).jobFor(_key);
      expect(job, isNotNull, reason: 'the job is never silently removed');
      expect(job!.status, PrintJobStatus.notConfigured);
      expect(bridge.count, 0);
    });
  });

  group('E. readiness failure is visible and retryable', () {
    test(
      'a throwing resolver fails visibly; Retry re-resolves and sends once',
      () async {
        final c = _c();
        final bridge = _RecordingBridge();
        var attempt = 0;
        Future<ReceiptReadiness> resolver() async {
          attempt++;
          if (attempt == 1) throw StateError('assignment load failed');
          return ReceiptReadiness.configured;
        }

        await _controller(c).requestReceipt(
          orderKey: _key,
          resolveReadiness: resolver,
          buildDocument: _doc,
          submitToBridge: bridge.submit,
        );
        expect(_controller(c).jobFor(_key)!.status, PrintJobStatus.failed);
        expect(bridge.count, 0);

        await _controller(c).retryReceipt(
          orderKey: _key,
          resolveReadiness: resolver,
          buildDocument: _doc,
          submitToBridge: bridge.submit,
        );

        expect(attempt, 2, reason: 'Retry RE-RESOLVES readiness');
        expect(
          _controller(c).jobFor(_key)!.status,
          PrintJobStatus.sentToPrinter,
        );
        expect(
          bridge.count,
          1,
          reason: 'exactly one send across both attempts',
        );
      },
    );

    test('loadFailed is reported distinctly from notConfigured', () async {
      final c = _c();
      await _controller(c).requestReceipt(
        orderKey: _key,
        resolveReadiness: () async => ReceiptReadiness.loadFailed,
        buildDocument: _doc,
      );
      expect(_controller(c).jobFor(_key)!.status, PrintJobStatus.failed);
    });
  });

  group('F/G. exactly-once under repeated signals', () {
    test(
      'repeated requests during the wait create ONE job and ONE send',
      () async {
        final c = _c();
        final bridge = _RecordingBridge();
        final readiness = Completer<ReceiptReadiness>();

        // Simulates provider rebuilds, device-context republication and repeated
        // payment notifications all re-entering the trigger.
        final flows = [
          for (var i = 0; i < 5; i++)
            _controller(c).requestReceipt(
              orderKey: _key,
              resolveReadiness: () => readiness.future,
              buildDocument: _doc,
              submitToBridge: bridge.submit,
            ),
        ];
        await Future<void>.delayed(Duration.zero);
        expect(
          _controller(c).jobFor(_key)!.status,
          PrintJobStatus.waitingForPrinter,
        );

        readiness.complete(ReceiptReadiness.configured);
        await Future.wait(flows);

        expect(bridge.count, 1, reason: 'no duplicate transport send');
        expect(
          c.read(receiptPrintControllerProvider).length,
          1,
          reason: 'exactly one job for the order',
        );
      },
    );

    test(
      'a Retry pressed DURING an active flow cannot open a second send',
      () async {
        final c = _c();
        final bridge = _RecordingBridge();
        final readiness = Completer<ReceiptReadiness>();

        final flow = _controller(c).requestReceipt(
          orderKey: _key,
          resolveReadiness: () => readiness.future,
          buildDocument: _doc,
          submitToBridge: bridge.submit,
        );
        await Future<void>.delayed(Duration.zero);

        await _controller(c).retryReceipt(
          orderKey: _key,
          resolveReadiness: () async => ReceiptReadiness.configured,
          buildDocument: _doc,
          submitToBridge: bridge.submit,
        );

        readiness.complete(ReceiptReadiness.configured);
        await flow;
        expect(bridge.count, 1);
      },
    );

    test(
      'retry NEVER re-sends after a transport may have accepted bytes',
      () async {
        final c = _c();
        final bridge = _RecordingBridge();
        await _controller(c).requestReceipt(
          orderKey: _key,
          resolveReadiness: () async => ReceiptReadiness.configured,
          buildDocument: _doc,
          submitToBridge: bridge.submit,
        );
        expect(bridge.count, 1);

        await _controller(c).retryReceipt(
          orderKey: _key,
          resolveReadiness: () async => ReceiptReadiness.configured,
          buildDocument: _doc,
          submitToBridge: bridge.submit,
        );
        expect(bridge.count, 1, reason: 'sentToPrinter is not re-sendable');
      },
    );

    test(
      'a second order does NOT initialize the first order\'s printing',
      () async {
        final c = _c();
        final bridge = _RecordingBridge();
        await _controller(c).requestReceipt(
          orderKey: 'order-A',
          resolveReadiness: () async => ReceiptReadiness.configured,
          buildDocument: _doc,
          submitToBridge: bridge.submit,
        );
        await _controller(c).requestReceipt(
          orderKey: 'order-B',
          resolveReadiness: () async => ReceiptReadiness.configured,
          buildDocument: _doc,
          submitToBridge: bridge.submit,
        );
        expect(bridge.count, 2, reason: 'each order gets its OWN receipt');
        expect(
          _controller(c).jobFor('order-A')!.status,
          PrintJobStatus.sentToPrinter,
        );
      },
    );
  });

  group('H. steady state is unchanged', () {
    test(
      'everything already resolved dispatches through the normal path',
      () async {
        final c = _c();
        final bridge = _RecordingBridge();
        await _controller(c).requestReceipt(
          orderKey: _key,
          resolveReadiness: () async => ReceiptReadiness.configured,
          awaitLogoReady: () async {},
          buildDocument: () => _doc(withLogo: true),
          submitToBridge: bridge.submit,
        );
        final job = _controller(c).jobFor(_key)!;
        expect(job.status, PrintJobStatus.sentToPrinter);
        expect(job.document, isNotNull);
        expect(_hasLogo(bridge.sent.single), isTrue);
      },
    );

    test('no bridge wired leaves the job honestly prepared', () async {
      final c = _c();
      await _controller(c).requestReceipt(
        orderKey: _key,
        resolveReadiness: () async => ReceiptReadiness.configured,
        buildDocument: _doc,
      );
      expect(_controller(c).jobFor(_key)!.status, PrintJobStatus.prepared);
    });
  });
}
