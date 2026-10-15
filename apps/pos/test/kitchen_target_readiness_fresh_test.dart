import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/spool/kitchen_readiness_coordinator.dart';
import 'package:restoflow_pos/src/spool/kitchen_readiness_evidence.dart';
import 'package:restoflow_pos/src/spool/kitchen_spool_readiness_probe.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_composition_native.dart';

void main() {
  test(
    'target initialization waits old probe then publishes a fresh real sample',
    () async {
      final oldReport = Completer<void>();
      final oldSampleTaken = Completer<void>();
      final sent = <KitchenReadinessReport>[];
      var initialized = false, probes = 0;
      final heartbeat = KitchenReadinessHeartbeat(
        deviceContext: () => const DeviceContext(
          organizationId: 'org',
          restaurantId: 'rest',
          branchId: 'branch',
          deviceId: 'device',
        ),
        fetchMode: () async => KitchenModePrinterOnlyWithRevision(
          verifiedAt: DateTime.utc(2026),
          revision: 1,
        ),
        printerEvidence: () async => const ReadyKitchenPrinterEvidence(
          printerAssignmentId: 'assignment',
          transportKind: KitchenReadinessTransportKind.bluetooth,
          paperWidth: KitchenReadinessPaperWidth.mm80,
          printerFingerprint:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
        probeSpool: ({required deviceId, required branchId}) async {
          probes++;
          final sample = KitchenSpoolReadinessProbeResult(
            secureSpoolAvailable: initialized,
            unresolvedLocalJobs: 0,
            spoolCountState: initialized
                ? KitchenSpoolCountState.counted
                : KitchenSpoolCountState.absent,
          );
          if (probes == 1) {
            oldSampleTaken.complete();
            await oldReport.future;
          }
          return sample;
        },
        sendStatus: (_) async => const KitchenPosStatusAccepted(),
        sendReport: (report) async {
          sent.add(report);
          return KitchenReadinessAccepted(
            activationReady: report.secureSpoolAvailable,
          );
        },
        invalidateModeCache: () async {},
      );
      final before = heartbeat.reportNow(trigger: 'startup');
      await oldSampleTaken.future;
      initialized = true;
      final after = reportFreshTargetSpoolReadiness(heartbeat);
      oldReport.complete();
      await before;
      await after;
      expect(probes, 2);
      expect(sent.map((r) => r.secureSpoolAvailable), [false, true]);
      heartbeat.dispose();
    },
  );
}
