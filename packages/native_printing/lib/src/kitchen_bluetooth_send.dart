import 'dart:async';
import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart'
    show KitchenTransportOutcome, KitchenTransportOutcomeKind;

import 'bluetooth_printer.dart';

/// KITCHEN-MODE-001C2C — the SINGLE-ATTEMPT kitchen Bluetooth seam.
///
/// The receipt-oriented [ChannelBluetoothConnector.send] performs ONE clean
/// automatic retry after a retryable failure — including a FULL resend after
/// a PARTIAL write. That is acceptable for customer receipts and a
/// double-ticket hazard for the kitchen. This seam executes EXACTLY one
/// native dispatch, never resends, never prompts for permissions (the
/// native job re-checks and reports `permission` itself — a background
/// worker must not raise UI), and preserves the RAW byte-count evidence the
/// receipt mapping discards.
final class KitchenBluetoothSendAttempt {
  const KitchenBluetoothSendAttempt({
    required this.result,
    required this.nativeResponded,
  });

  /// The native job result. Meaningful ONLY when [nativeResponded] is true.
  final BluetoothJobResult result;

  /// Whether the platform channel actually answered. `false` means the
  /// result was LOST after dispatch (outer backstop fired / channel threw)
  /// — bytes may be mid-write, so nothing may claim they were not sent.
  final bool nativeResponded;
}

extension KitchenBluetoothSingleAttempt on ChannelBluetoothConnector {
  /// EXACTLY ONE native dispatch attempt. No automatic resend of any kind.
  Future<KitchenBluetoothSendAttempt> sendOnceForKitchen({
    required String address,
    required Uint8List bytes,
    Duration timeout = kBluetoothPrintTimeout,
  }) async {
    final outer = timeout * 2 + outerTimeoutMargin;
    try {
      final result = await api
          .printBytes(
            address: address,
            bytes: bytes,
            timeout: timeout,
            chunkBytes: chunkBytes,
            chunkDelay: chunkDelay,
            drainDelay: drainDelay,
          )
          .timeout(outer);
      return KitchenBluetoothSendAttempt(result: result, nativeResponded: true);
    } on TimeoutException {
      return const KitchenBluetoothSendAttempt(
        result: BluetoothJobResult(
          code: BluetoothJobCode.timeout,
          detail: 'channel_result_lost',
        ),
        nativeResponded: false,
      );
    } on Object {
      // The channel call itself failed; whether the native job started is
      // unknowable from here.
      return const KitchenBluetoothSendAttempt(
        result: BluetoothJobResult(
          code: BluetoothJobCode.unknown,
          detail: 'channel_call_failed',
        ),
        nativeResponded: false,
      );
    }
  }
}

/// Classifies one single-attempt Bluetooth result into the closed kitchen
/// transport outcome (KITCHEN-MODE-001C2C):
///
///  * lost/absent native result after dispatch  -> timeoutAfterPossibleWrite
///  * `ok` (all chunks flushed + drain elapsed) -> accepted
///  * permission / adapter off                  -> unavailable (temporary)
///  * not bonded / channel unsupported          -> unsupported (permanent)
///  * connect failed, zero bytes                -> definitelyNotSent
///  * native timeout, zero bytes (connect)      -> timeoutBeforeWrite
///  * write failed, ZERO bytes                  -> definitelyNotSent
///  * write failed, PARTIAL bytes               -> ambiguous (NEVER resent)
///  * anything unproven                         -> ambiguous
///
/// bytesSent is the NATIVE evidence: only a zero count can prove no byte
/// left the process. There is no catch-all retryable branch.
KitchenTransportOutcome classifyKitchenBluetoothAttempt(
  KitchenBluetoothSendAttempt attempt,
) {
  if (!attempt.nativeResponded) {
    return const KitchenTransportOutcome(
      KitchenTransportOutcomeKind.timeoutAfterPossibleWrite,
      'channel_result_lost',
    );
  }
  final result = attempt.result;
  final zeroBytes = result.bytesSent == 0;
  return switch (result.code) {
    BluetoothJobCode.ok => const KitchenTransportOutcome(
      KitchenTransportOutcomeKind.accepted,
      'native_flushed_drained',
    ),
    BluetoothJobCode.permission => const KitchenTransportOutcome(
      KitchenTransportOutcomeKind.unavailable,
      'bluetooth_permission',
    ),
    BluetoothJobCode.bluetoothOff => const KitchenTransportOutcome(
      KitchenTransportOutcomeKind.unavailable,
      'bluetooth_off',
    ),
    BluetoothJobCode.notBonded => const KitchenTransportOutcome(
      KitchenTransportOutcomeKind.unsupported,
      'not_bonded',
    ),
    BluetoothJobCode.unsupported => const KitchenTransportOutcome(
      KitchenTransportOutcomeKind.unsupported,
      'channel_missing',
    ),
    BluetoothJobCode.connectFailed =>
      zeroBytes
          ? const KitchenTransportOutcome(
              KitchenTransportOutcomeKind.definitelyNotSent,
              'connect_failed',
            )
          : const KitchenTransportOutcome(
              KitchenTransportOutcomeKind.ambiguous,
              'connect_failed_after_write',
            ),
    BluetoothJobCode.timeout =>
      zeroBytes
          ? const KitchenTransportOutcome(
              KitchenTransportOutcomeKind.timeoutBeforeWrite,
              'native_connect_timeout',
            )
          : const KitchenTransportOutcome(
              KitchenTransportOutcomeKind.ambiguous,
              'native_timeout_after_write',
            ),
    BluetoothJobCode.writeFailed =>
      zeroBytes
          ? const KitchenTransportOutcome(
              KitchenTransportOutcomeKind.definitelyNotSent,
              'write_failed_zero_bytes',
            )
          : const KitchenTransportOutcome(
              KitchenTransportOutcomeKind.ambiguous,
              'partial_write',
            ),
    BluetoothJobCode.unknown => const KitchenTransportOutcome(
      KitchenTransportOutcomeKind.ambiguous,
      'native_unknown',
    ),
  };
}
