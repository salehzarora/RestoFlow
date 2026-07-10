import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import 'bluetooth_printer.dart';

/// Native (`dart:io`) Bluetooth connector (PRINT-BLUETOOTH-RECOVERY-001).
/// Android drives the [ChannelBluetoothConnector] over the host app's IN-HOUSE
/// `restoflow.native_printing/bluetooth` MethodChannel (implemented by the POS
/// and KDS `MainActivity`): one atomic, stateless SPP print job per call with a
/// secure→insecure connect fallback, a native watchdog timeout, exact-byte
/// chunked writes, and typed result codes. The previously used
/// `print_bluetooth_thermal` plugin was removed — its Android side prepended a
/// rogue `\n` to every write (corrupting chunked raster streams), kept broken
/// global socket state, hung the channel when the permission was missing, and
/// only ever tried the secure RFCOMM socket. Other native platforms
/// (iOS/desktop) report unsupported for this Android-focused MVP. Web never
/// links this file.
BluetoothPrinterConnector createBluetoothPrinterConnector() =>
    defaultTargetPlatform == TargetPlatform.android
    ? ChannelBluetoothConnector(api: const MethodChannelBluetoothPrintApi())
    : const _UnsupportedNativeConnector();

/// The real [BluetoothPrintApi]: the host app's Kotlin channel for
/// check/list/print + `permission_handler` for the runtime CONNECT request.
/// Thin pass-through: NO retry/mapping logic lives here (that is the
/// plugin-free [ChannelBluetoothConnector], so it stays unit-testable). Every
/// method is best-effort and swallows platform errors into a typed result so
/// control flow never depends on an exception.
class MethodChannelBluetoothPrintApi implements BluetoothPrintApi {
  const MethodChannelBluetoothPrintApi({this.channel = _defaultChannel});

  /// The host-app channel (see the POS/KDS `MainActivity`).
  static const MethodChannel _defaultChannel = MethodChannel(
    'restoflow.native_printing/bluetooth',
  );

  final MethodChannel channel;

  @override
  Future<bool> permissionsGranted() async {
    try {
      return await channel.invokeMethod<bool>('permissionsGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      // Android 12+ runtime dialog. CONNECT ONLY — the app never scans
      // (bonded devices only), so a denied SCAN permission must never block
      // printing. Below Android 12 this reports granted without a dialog.
      final status = await Permission.bluetoothConnect.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isEnabled() async {
    try {
      return await channel.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<BluetoothPairedNative> pairedDevices() async {
    try {
      final raw = await channel.invokeMethod<Map<Object?, Object?>>(
        'pairedDevices',
      );
      if (raw == null) {
        return const BluetoothPairedNative.failed(BluetoothJobCode.unknown);
      }
      if (raw['ok'] != true) {
        return BluetoothPairedNative.failed(_codeFrom(raw['code']));
      }
      final devices = <BluetoothDeviceInfo>[
        for (final entry in (raw['devices'] as List<Object?>? ?? const []))
          if (entry is Map)
            BluetoothDeviceInfo(
              address: '${entry['address'] ?? ''}',
              name: '${entry['name'] ?? ''}',
              majorClass: switch (entry['majorClass']) {
                final int value when value >= 0 => value,
                _ => null,
              },
            ),
      ];
      return BluetoothPairedNative.ok(devices);
    } on MissingPluginException {
      return const BluetoothPairedNative.failed(BluetoothJobCode.unsupported);
    } catch (_) {
      return const BluetoothPairedNative.failed(BluetoothJobCode.unknown);
    }
  }

  @override
  Future<BluetoothJobResult> printBytes({
    required String address,
    required Uint8List bytes,
    required Duration timeout,
    int chunkBytes = kBluetoothChunkBytes,
    Duration chunkDelay = kBluetoothChunkDelay,
    Duration drainDelay = kBluetoothDrainDelay,
  }) async {
    try {
      final raw = await channel
          .invokeMethod<Map<Object?, Object?>>('printBytes', <String, Object>{
            'address': address,
            'bytes': bytes,
            'timeoutMs': timeout.inMilliseconds,
            'chunkBytes': chunkBytes,
            'chunkDelayMs': chunkDelay.inMilliseconds,
            'drainMs': drainDelay.inMilliseconds,
          });
      if (raw == null) {
        return const BluetoothJobResult(
          code: BluetoothJobCode.unknown,
          detail: 'empty native result',
        );
      }
      return BluetoothJobResult(
        code: raw['ok'] == true ? BluetoothJobCode.ok : _codeFrom(raw['code']),
        detail: raw['detail'] == null ? null : '${raw['detail']}',
        bytesSent: switch (raw['bytesSent']) {
          final int value => value,
          _ => 0,
        },
        chunks: switch (raw['chunks']) {
          final int value => value,
          _ => 0,
        },
      );
    } on MissingPluginException {
      return const BluetoothJobResult(
        code: BluetoothJobCode.unsupported,
        detail:
            'the bluetooth print channel is not registered by this host app',
      );
    } on PlatformException catch (e) {
      return BluetoothJobResult(
        code: BluetoothJobCode.unknown,
        detail: 'platform error: ${e.code} ${e.message ?? ''}',
      );
    } catch (e) {
      return BluetoothJobResult(code: BluetoothJobCode.unknown, detail: '$e');
    }
  }

  /// Maps a wire code string to the typed enum (unknown-safe).
  static BluetoothJobCode _codeFrom(Object? raw) => switch ('$raw') {
    'ok' => BluetoothJobCode.ok,
    'permission' => BluetoothJobCode.permission,
    'bluetoothOff' => BluetoothJobCode.bluetoothOff,
    'notBonded' => BluetoothJobCode.notBonded,
    'connectFailed' => BluetoothJobCode.connectFailed,
    'timeout' => BluetoothJobCode.timeout,
    'writeFailed' => BluetoothJobCode.writeFailed,
    'unsupported' => BluetoothJobCode.unsupported,
    _ => BluetoothJobCode.unknown,
  };
}

/// iOS / desktop native: Bluetooth Classic printing is not offered in this
/// Android-focused MVP.
class _UnsupportedNativeConnector implements BluetoothPrinterConnector {
  const _UnsupportedNativeConnector();

  @override
  bool get isSupported => false;

  @override
  Future<bool> ensurePermissions() async => false;

  @override
  Future<BluetoothPairedResult> pairedDevices() async =>
      const BluetoothPairedResult.failed(BluetoothPrinterError.unsupported);

  @override
  Future<pp.PrintResult> send({
    required String address,
    required Uint8List bytes,
    Duration timeout = kBluetoothPrintTimeout,
  }) async => const pp.PrintResult.failure(
    pp.PrinterErrorCategory.unsupported,
    'Bluetooth printing is only implemented on Android.',
  );
}
