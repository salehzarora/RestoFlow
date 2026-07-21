@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/spool/kitchen_dispatch_drain_coordinator.dart';
import 'package:restoflow_pos/src/spool/kitchen_print_worker.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_capability.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_composition_native.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_runtime.dart';

/// KITCHEN-MODE-001C2C — the typed operational capability derivation:
/// safe scalars in, one closed enum value out; failed runs never read as
/// operational success.
KitchenSpoolRunWorked _worked({
  int accepted = 0,
  int failedRetryable = 0,
  int transportUnavailable = 0,
  int possiblyPrinted = 0,
  int blocked = 0,
  int ackTerminal = 0,
  int recoveredStale = 0,
  int drainBlocked = 0,
  int runTerminal = 0,
  int drainTerminal = 0,
}) => KitchenSpoolRunWorked(
  'worked',
  drain: KitchenDispatchDrainReport(
    stoppedReason: KitchenDrainStopReason.complete,
    rowsBlockedConfiguration: drainBlocked,
    acknowledgementsTerminal: drainTerminal,
  ),
  worker: KitchenWorkerRunReport(
    stoppedReason: KitchenWorkerStopReason.complete,
    accepted: accepted,
    failedRetryable: failedRetryable,
    transportUnavailable: transportUnavailable,
    possiblyPrinted: possiblyPrinted,
    blockedConfiguration: blocked,
    ackTerminal: ackTerminal,
  ),
  recoveredStale: recoveredStale,
  voidSuperseded: 0,
  voidLinks: 0,
  acked: 0,
  retriesScheduled: 0,
  terminal: runTerminal,
);

void main() {
  test('priority ladder: terminal > review > blocked > transport > retry > '
      'idle', () {
    expect(
      deriveKitchenSpoolCapability(_worked(accepted: 3)),
      PosKitchenSpoolCapability.idle,
    );
    expect(
      deriveKitchenSpoolCapability(_worked(failedRetryable: 1)),
      PosKitchenSpoolCapability.waitingRetry,
    );
    expect(
      deriveKitchenSpoolCapability(
        _worked(failedRetryable: 1, transportUnavailable: 1),
      ),
      PosKitchenSpoolCapability.transportUnavailable,
    );
    expect(
      deriveKitchenSpoolCapability(_worked(blocked: 1, failedRetryable: 1)),
      PosKitchenSpoolCapability.blockedConfiguration,
    );
    expect(
      deriveKitchenSpoolCapability(_worked(drainBlocked: 1)),
      PosKitchenSpoolCapability.blockedConfiguration,
    );
    expect(
      deriveKitchenSpoolCapability(_worked(possiblyPrinted: 1, blocked: 1)),
      PosKitchenSpoolCapability.possiblyPrintedReviewRequired,
    );
    expect(
      deriveKitchenSpoolCapability(_worked(recoveredStale: 1)),
      PosKitchenSpoolCapability.possiblyPrintedReviewRequired,
    );
    expect(
      deriveKitchenSpoolCapability(_worked(ackTerminal: 1, possiblyPrinted: 1)),
      PosKitchenSpoolCapability.terminalOwnershipConflict,
    );
  });

  test('REVIEW NOTE F1: RUN-LEVEL terminal verdicts (pre/post pending-ack '
      'flush) map to terminalOwnershipConflict even when the worker saw '
      'none', () {
    // Worked run: worker.ackTerminal 0, but the run-level flush hit one.
    expect(
      deriveKitchenSpoolCapability(_worked(runTerminal: 1)),
      PosKitchenSpoolCapability.terminalOwnershipConflict,
    );
    // The drain's own immediate-ack terminal counts too.
    expect(
      deriveKitchenSpoolCapability(_worked(drainTerminal: 1)),
      PosKitchenSpoolCapability.terminalOwnershipConflict,
    );
    // Terminal beats every lower-priority signal.
    expect(
      deriveKitchenSpoolCapability(
        _worked(
          runTerminal: 1,
          possiblyPrinted: 2,
          blocked: 3,
          failedRetryable: 4,
          transportUnavailable: 1,
        ),
      ),
      PosKitchenSpoolCapability.terminalOwnershipConflict,
    );
    // A RECONCILED run (kds existing-spool flush) with a terminal verdict.
    expect(
      deriveKitchenSpoolCapability(
        const KitchenSpoolRunReconciled(
          'reconciled',
          acked: 0,
          retriesScheduled: 0,
          terminal: 1,
        ),
      ),
      PosKitchenSpoolCapability.terminalOwnershipConflict,
    );
    // A DRAINED run whose pending-ack flush hit a terminal verdict.
    expect(
      deriveKitchenSpoolCapability(
        const KitchenSpoolRunDrained(
          'drained',
          drain: KitchenDispatchDrainReport(
            stoppedReason: KitchenDrainStopReason.complete,
          ),
          acked: 0,
          retriesScheduled: 0,
          terminal: 1,
        ),
      ),
      PosKitchenSpoolCapability.terminalOwnershipConflict,
    );
    // Zero terminals everywhere: behavior unchanged.
    expect(
      deriveKitchenSpoolCapability(_worked(accepted: 2)),
      PosKitchenSpoolCapability.idle,
    );
  });

  test('blocked/failed runs map to their typed causes and never claim '
      'success', () {
    expect(
      deriveKitchenSpoolCapability(
        const KitchenSpoolRunBlocked('unexpected_failure'),
      ),
      PosKitchenSpoolCapability.unexpectedFailure,
    );
    expect(
      deriveKitchenSpoolCapability(
        const KitchenSpoolRunBlocked('KitchenSpoolKeyMissingWithRows'),
      ),
      PosKitchenSpoolCapability.keyUnavailable,
    );
    expect(
      deriveKitchenSpoolCapability(
        const KitchenSpoolRunBlocked('KitchenSpoolKeyCorrupted'),
      ),
      PosKitchenSpoolCapability.keyUnavailable,
    );
    expect(
      deriveKitchenSpoolCapability(
        const KitchenSpoolRunBlocked('spool_database_open_failed'),
      ),
      PosKitchenSpoolCapability.databaseUnavailable,
    );
    expect(
      deriveKitchenSpoolCapability(
        const KitchenSpoolRunBlocked('kitchen_destination_unresolvable'),
      ),
      PosKitchenSpoolCapability.destinationUnsupported,
    );
    expect(
      deriveKitchenSpoolCapability(
        const KitchenSpoolRunBlocked('anything_unknown'),
      ),
      PosKitchenSpoolCapability.unexpectedFailure,
      reason: 'unknown blocked details never read as success',
    );
  });

  test('idle-class reports (skips, kds reconcile, dormant drain) map to '
      'idle', () {
    expect(
      deriveKitchenSpoolCapability(
        const KitchenSpoolRunSkipped('kds_no_spool_footprint'),
      ),
      PosKitchenSpoolCapability.idle,
    );
    expect(
      deriveKitchenSpoolCapability(
        const KitchenSpoolRunReconciled(
          'reconciled',
          acked: 1,
          retriesScheduled: 0,
          terminal: 0,
        ),
      ),
      PosKitchenSpoolCapability.idle,
    );
  });
}
