import 'dart:async';
import 'dart:typed_data';

import 'kitchen_network_sender_stub.dart'
    if (dart.library.io) 'kitchen_network_sender_io.dart'
    as platform;
import 'kitchen_transport_outcome.dart';

/// KITCHEN-MODE-001C2C — the PHASE-AWARE kitchen network sender.
///
/// The existing receipt sender (`sendEscPosOverTcp`) collapses every failure
/// into one retry-shaped category, which is unusable for kitchen tickets: a
/// flush timeout means the CONNECT SUCCEEDED and bytes may already be on the
/// printer. This sender classifies by phase instead:
///
///   * malformed destination                  -> unsupported (before connect)
///   * connector absent (web)                 -> unsupported
///   * connect refused / failed               -> definitelyNotSent
///   * connect timeout                        -> timeoutBeforeWrite
///   * THE POINT OF NO SAFE RETRY: `socket.add(bytes)`
///   * any error at/after add                 -> ambiguous
///   * flush timeout after add                -> timeoutAfterPossibleWrite
///   * flush completed                        -> accepted (bytes handed to
///     the OS — NEVER a physical paper claim)
///
/// NO automatic resend of any kind lives here. Classification is fully
/// deterministic under the injectable [KitchenSocketConnector] seam; the
/// real `dart:io` connector is linked only where `dart.library.io` exists,
/// so this file stays importable from web compilation units.
abstract interface class KitchenSendSocket {
  /// Hands [bytes] to the transport buffer (the point of no safe retry).
  void add(List<int> bytes);

  /// Completes when the buffered bytes were handed to the OS.
  Future<void> flush();

  /// Polite close; failures after a successful flush are non-fatal.
  Future<void> close();

  /// Hard teardown; must never throw.
  void destroy();
}

/// Opens a socket to `host:port`, bounded by [timeout]. Contract: a connect
/// timeout surfaces as [TimeoutException]; every other connect failure as
/// any other thrown object.
typedef KitchenSocketConnector =
    Future<KitchenSendSocket> Function(String host, int port, Duration timeout);

/// Sends already-encoded ESC/POS [bytes] to a network kitchen printer with
/// phase-aware classification. Never throws; never resends.
Future<KitchenTransportOutcome> sendKitchenBytesOverTcp({
  required String host,
  required int port,
  required Uint8List bytes,
  Duration timeout = const Duration(seconds: 6),
  KitchenSocketConnector? connect,
}) async {
  final watch = Stopwatch()..start();
  KitchenTransportOutcome done(KitchenTransportOutcomeKind kind, String code) =>
      KitchenTransportOutcome(kind, code, elapsed: watch.elapsed);

  // Before any connection: a destination this sender can NEVER serve.
  if (host.trim().isEmpty || port < 1 || port > 65535) {
    return done(
      KitchenTransportOutcomeKind.unsupported,
      'malformed_destination',
    );
  }
  final connector = connect ?? platform.platformKitchenSocketConnector();
  if (connector == null) {
    return done(KitchenTransportOutcomeKind.unsupported, 'web_unsupported');
  }

  final KitchenSendSocket socket;
  try {
    socket = await connector(host, port, timeout);
  } on TimeoutException {
    return done(
      KitchenTransportOutcomeKind.timeoutBeforeWrite,
      'connect_timeout',
    );
  } on Object {
    // Refused / unreachable / any connect-phase failure: PROVABLY no byte
    // was handed over.
    return done(
      KitchenTransportOutcomeKind.definitelyNotSent,
      'connect_failed',
    );
  }

  try {
    try {
      // THE point of no safe retry: from here on, nothing may claim the
      // bytes were not sent.
      socket.add(bytes);
    } on Object {
      return done(
        KitchenTransportOutcomeKind.ambiguous,
        'socket_error_at_write',
      );
    }
    try {
      await socket.flush().timeout(timeout);
    } on TimeoutException {
      return done(
        KitchenTransportOutcomeKind.timeoutAfterPossibleWrite,
        'flush_timeout',
      );
    } on Object {
      return done(
        KitchenTransportOutcomeKind.ambiguous,
        'socket_error_after_write',
      );
    }
    // Delivery is decided by the flush; a slow/rude close must not turn a
    // delivered print into a false failure.
    try {
      await socket.close().timeout(const Duration(seconds: 2));
    } on Object {
      // ignore: bytes were already flushed.
    }
    return done(KitchenTransportOutcomeKind.accepted, 'flushed');
  } finally {
    socket.destroy();
  }
}
