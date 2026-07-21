import 'dart:async';

/// KITCHEN-MODE-001C2C (LOCKED DECISION 3) — one in-process FIFO send gate
/// per PHYSICAL printer destination.
///
/// The same physical printer may serve BOTH customer receipts and kitchen
/// tickets, so a kitchen-only mutex is insufficient: every physical send —
/// receipt or kitchen — for one canonical endpoint must pass through the
/// SAME gate instance, serialized FIFO. Different endpoints proceed
/// concurrently.
///
/// Contract:
///  * the gate is held ONLY around the physical transport operation — never
///    around payload construction, rasterization, or decryption;
///  * an exception inside the guarded send releases the gate (the failure
///    propagates to the caller, the next waiter proceeds);
///  * a hung send cannot deadlock a key forever ONLY because every wrapped
///    transport is itself timeout-bounded — the gate adds no timeout of its
///    own;
///  * gate keys are canonical routing strings and are NEVER logged or
///    exposed in errors by the callers (the gate itself emits nothing).
final class PrinterDestinationSendGate {
  final Map<String, Future<void>> _tails = {};

  /// Canonical key for a network endpoint (trimmed, lowercased host).
  static String networkKey(String host, int port) =>
      'net|${host.trim().toLowerCase()}|$port';

  /// Canonical key for a Bluetooth endpoint (trimmed, lowercased address).
  static String bluetoothKey(String address) =>
      'bt|${address.trim().toLowerCase()}';

  /// Runs [send] once every earlier send for [destinationKey] has finished
  /// (FIFO). The returned future completes with [send]'s result or error.
  Future<T> withDestination<T>(
    String destinationKey,
    Future<T> Function() send,
  ) {
    final previous = _tails[destinationKey] ?? Future<void>.value();
    final release = Completer<void>();
    _tails[destinationKey] = release.future;
    return previous.then((_) async {
      try {
        return await send();
      } finally {
        release.complete();
        // Drop the tail entry once no later sender chained behind us.
        if (identical(_tails[destinationKey], release.future)) {
          _tails.remove(destinationKey);
        }
      }
    });
  }
}
