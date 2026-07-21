import 'dart:async';
import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:restoflow_printing/src/transport/kitchen_network_sender_stub.dart'
    as web_stub;
import 'package:test/test.dart';

/// KITCHEN-MODE-001C2C — phase-aware kitchen network classification. Every
/// case is deterministic through the injectable socket seam; the point of no
/// safe retry is `socket.add(bytes)`.
class _FakeSocket implements KitchenSendSocket {
  _FakeSocket({
    this.throwOnAdd,
    this.flushError,
    this.flushHangs = false,
    this.closeError,
  });

  final Object? throwOnAdd;
  final Object? flushError;
  final bool flushHangs;
  final Object? closeError;

  final List<List<int>> added = [];
  var destroyed = false;

  @override
  void add(List<int> bytes) {
    final error = throwOnAdd;
    if (error != null) throw error;
    added.add(List.of(bytes));
  }

  @override
  Future<void> flush() {
    if (flushHangs) return Completer<void>().future;
    final error = flushError;
    if (error != null) return Future.error(error);
    return Future.value();
  }

  @override
  Future<void> close() {
    final error = closeError;
    if (error != null) return Future.error(error);
    return Future.value();
  }

  @override
  void destroy() => destroyed = true;
}

void main() {
  final bytes = Uint8List.fromList([1, 2, 3, 4]);

  KitchenSocketConnector connectorFor(
    _FakeSocket socket, {
    List<int>? connectCalls,
  }) => (host, port, timeout) async {
    connectCalls?.add(1);
    return socket;
  };

  group('sendKitchenBytesOverTcp classification', () {
    test('malformed destination -> unsupported, BEFORE any connect', () async {
      var connects = 0;
      Future<KitchenSendSocket> connect(String h, int p, Duration t) async {
        connects++;
        return _FakeSocket();
      }

      for (final (host, port) in [
        ('', 9100),
        ('  ', 9100),
        ('h', 0),
        ('h', 70000),
      ]) {
        final outcome = await sendKitchenBytesOverTcp(
          host: host,
          port: port,
          bytes: bytes,
          connect: connect,
        );
        expect(outcome.kind, KitchenTransportOutcomeKind.unsupported);
        expect(outcome.reasonCode, 'malformed_destination');
      }
      expect(connects, 0);
    });

    test('connection refused -> definitelyNotSent (safe to retry)', () async {
      final outcome = await sendKitchenBytesOverTcp(
        host: '10.9.9.9',
        port: 9100,
        bytes: bytes,
        connect: (h, p, t) => throw StateError('refused'),
      );
      expect(outcome.kind, KitchenTransportOutcomeKind.definitelyNotSent);
      expect(outcome.reasonCode, 'connect_failed');
      expect(outcome.isSafeToRetry, isTrue);
    });

    test('connection timeout -> timeoutBeforeWrite (safe to retry)', () async {
      final outcome = await sendKitchenBytesOverTcp(
        host: '10.9.9.9',
        port: 9100,
        bytes: bytes,
        connect: (h, p, t) => throw TimeoutException('connect'),
      );
      expect(outcome.kind, KitchenTransportOutcomeKind.timeoutBeforeWrite);
      expect(outcome.reasonCode, 'connect_timeout');
      expect(outcome.isSafeToRetry, isTrue);
    });

    test('successful add + flush -> accepted; socket torn down', () async {
      final socket = _FakeSocket();
      final outcome = await sendKitchenBytesOverTcp(
        host: '10.9.9.9',
        port: 9100,
        bytes: bytes,
        connect: connectorFor(socket),
      );
      expect(outcome.kind, KitchenTransportOutcomeKind.accepted);
      expect(outcome.reasonCode, 'flushed');
      expect(
        outcome.isSafeToRetry,
        isFalse,
        reason: 'accepted is never a retry candidate',
      );
      expect(socket.added.single, bytes);
      expect(socket.destroyed, isTrue);
    });

    test(
      'exception AT add -> ambiguous (the point of no safe retry)',
      () async {
        final socket = _FakeSocket(throwOnAdd: StateError('write refused'));
        final outcome = await sendKitchenBytesOverTcp(
          host: '10.9.9.9',
          port: 9100,
          bytes: bytes,
          connect: connectorFor(socket),
        );
        expect(outcome.kind, KitchenTransportOutcomeKind.ambiguous);
        expect(outcome.reasonCode, 'socket_error_at_write');
        expect(outcome.isSafeToRetry, isFalse);
      },
    );

    test(
      'exception AFTER add (during flush) -> ambiguous, never retryable',
      () async {
        final socket = _FakeSocket(flushError: StateError('conn reset'));
        final outcome = await sendKitchenBytesOverTcp(
          host: '10.9.9.9',
          port: 9100,
          bytes: bytes,
          connect: connectorFor(socket),
        );
        expect(outcome.kind, KitchenTransportOutcomeKind.ambiguous);
        expect(outcome.reasonCode, 'socket_error_after_write');
        expect(outcome.isSafeToRetry, isFalse);
      },
    );

    test('flush timeout after add -> timeoutAfterPossibleWrite, never '
        'retryable (bytes may be on the printer)', () async {
      final socket = _FakeSocket(flushHangs: true);
      final outcome = await sendKitchenBytesOverTcp(
        host: '10.9.9.9',
        port: 9100,
        bytes: bytes,
        timeout: const Duration(milliseconds: 40),
        connect: connectorFor(socket),
      );
      expect(
        outcome.kind,
        KitchenTransportOutcomeKind.timeoutAfterPossibleWrite,
      );
      expect(outcome.reasonCode, 'flush_timeout');
      expect(outcome.isSafeToRetry, isFalse);
      expect(socket.destroyed, isTrue);
    });

    test('a rude close after a successful flush stays ACCEPTED', () async {
      final socket = _FakeSocket(closeError: StateError('rude close'));
      final outcome = await sendKitchenBytesOverTcp(
        host: '10.9.9.9',
        port: 9100,
        bytes: bytes,
        connect: connectorFor(socket),
      );
      expect(outcome.kind, KitchenTransportOutcomeKind.accepted);
    });

    test(
      'NO automatic resend: exactly one connect, one add, per call',
      () async {
        final calls = <int>[];
        final socket = _FakeSocket(flushError: StateError('reset'));
        await sendKitchenBytesOverTcp(
          host: '10.9.9.9',
          port: 9100,
          bytes: bytes,
          connect: connectorFor(socket, connectCalls: calls),
        );
        expect(calls, hasLength(1));
        expect(socket.added, hasLength(1));
      },
    );

    test('privacy: outcomes never carry the endpoint or payload', () async {
      final socket = _FakeSocket(flushError: StateError('secret 10.9.9.9'));
      final outcome = await sendKitchenBytesOverTcp(
        host: '10.9.9.9',
        port: 9107,
        bytes: bytes,
        connect: connectorFor(socket),
      );
      final rendered = outcome.toString();
      expect(rendered, isNot(contains('10.9.9.9')));
      expect(rendered, isNot(contains('9107')));
      expect(rendered, isNot(contains('secret')));
    });
  });

  group('web boundary', () {
    test('the web stub provides NO connector (unsupported, fail closed)', () {
      expect(web_stub.platformKitchenSocketConnector(), isNull);
    });
  });

  group('kitchenPrintRetryPolicy (LOCKED DECISION 4)', () {
    test('deterministic 2s × 2^n capped at 5 minutes, no jitter', () {
      expect(kitchenPrintRetryPolicy.jitter, isFalse);
      expect(kitchenPrintRetryPolicy.backoffFor(1), const Duration(seconds: 2));
      expect(kitchenPrintRetryPolicy.backoffFor(2), const Duration(seconds: 4));
      expect(
        kitchenPrintRetryPolicy.backoffFor(5),
        const Duration(seconds: 32),
      );
      expect(
        kitchenPrintRetryPolicy.backoffFor(9),
        const Duration(minutes: 5),
        reason: 'capped',
      );
      expect(
        kitchenPrintRetryPolicy.backoffFor(40),
        const Duration(minutes: 5),
        reason: 'stays capped indefinitely (no max-attempt parking)',
      );
    });

    test('the worker outcome mapping is pinned', () {
      // accepted -> transportAccepted; definitelyNotSent/timeoutBeforeWrite/
      // unavailable -> failedRetryable; unsupported -> blockedConfiguration;
      // ambiguous/timeoutAfterPossibleWrite -> possiblyPrinted. The
      // retry-safety split is the machine-checkable half of that table:
      const retryable = {
        KitchenTransportOutcomeKind.definitelyNotSent,
        KitchenTransportOutcomeKind.timeoutBeforeWrite,
        KitchenTransportOutcomeKind.unavailable,
      };
      for (final kind in KitchenTransportOutcomeKind.values) {
        expect(
          KitchenTransportOutcome(kind, 'probe').isSafeToRetry,
          retryable.contains(kind),
          reason: kind.name,
        );
      }
    });
  });
}
