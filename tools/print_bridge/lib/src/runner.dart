import 'dart:async';

import 'bridge_server.dart';

/// Runs [server] until an interrupt arrives on [interrupts] (Ctrl+C in
/// production), then shuts the server down cleanly and RETURNS. Testable: a test
/// passes a controllable stream instead of the real OS signal, fires it, and
/// awaits — proving the shutdown path completes (does not hang) and cancels its
/// own subscription.
///
/// The subscription is cancelled inside the shutdown so it cannot keep the
/// isolate alive after the server closes (the RF-115 Ctrl+C-hang bug). A second
/// interrupt while shutting down is a no-op.
Future<void> runBridge(
  BridgeServer server, {
  required Stream<void> interrupts,
  void Function(String message)? onLog,
}) async {
  final done = Completer<void>();
  var stopping = false;
  late final StreamSubscription<void> sub;

  Future<void> shutdown() async {
    if (stopping) return;
    stopping = true;
    onLog?.call('print_bridge: shutting down...');
    await sub.cancel();
    await server.stop();
    if (!done.isCompleted) done.complete();
  }

  sub = interrupts.listen((_) => shutdown());
  await done.future;
}
