import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

// Web-safe connector selection: the stub (browsers have no Bluetooth Classic +
// no dart:io) is the default; the native plugin-backed connector is linked only
// where `dart.library.io` exists. This file itself never imports the Bluetooth
// plugin, so this package stays importable from the web build.
import 'bluetooth_connector_stub.dart'
    if (dart.library.io) 'bluetooth_connector_native.dart';

/// A bonded/paired Bluetooth device (ANDROID-003).
class BluetoothDeviceInfo {
  const BluetoothDeviceInfo({required this.address, required this.name});

  /// The device's Bluetooth address (MAC).
  final String address;

  /// The device's advertised name (may be empty).
  final String name;
}

/// Why a Bluetooth print/list attempt could not proceed (maps to localized UI).
enum BluetoothPrinterError {
  /// Bluetooth printing is not available on this build/platform (e.g. web).
  unsupported,

  /// The runtime BLUETOOTH_CONNECT/SCAN permission was denied.
  permissionDenied,

  /// The Bluetooth adapter is off.
  bluetoothOff,

  /// Could not connect to the printer (out of range / powered off / not bonded).
  connectFailed,

  /// Connected but writing the bytes failed.
  writeFailed,

  /// The operation timed out.
  timeout,
}

/// The result of listing paired devices - the devices OR a typed error.
class BluetoothPairedResult {
  const BluetoothPairedResult.ok(this.devices) : error = null;
  const BluetoothPairedResult.failed(this.error) : devices = const [];

  final List<BluetoothDeviceInfo> devices;
  final BluetoothPrinterError? error;

  bool get ok => error == null;
}

/// The seam over the platform Bluetooth Classic (SPP) stack (ANDROID-003).
///
/// Behind an interface so widget/unit tests inject a fake and never touch real
/// Bluetooth. The default implementation is chosen by a conditional import
/// (native plugin vs. web stub) so the web build never links native code.
abstract class BluetoothPrinterConnector {
  /// Whether Bluetooth printing is possible on this build/platform.
  bool get isSupported;

  /// Ensures the runtime BLUETOOTH_CONNECT/SCAN permissions (Android 12+).
  /// Returns whether they are granted.
  Future<bool> ensurePermissions();

  /// The bonded/paired devices (empty on failure - see [BluetoothPairedResult]).
  Future<BluetoothPairedResult> pairedDevices();

  /// Connects to [address], writes [bytes], and disconnects. Best-effort - a
  /// [pp.PrintResult] that NEVER throws and NEVER hangs (bounded by [timeout]).
  Future<pp.PrintResult> send({
    required String address,
    required Uint8List bytes,
    Duration timeout,
  });
}

/// PRINT-STABILITY-001: the conservative Bluetooth write chunk size (bytes). A
/// raster receipt/ticket is large; many SPP printers drop or truncate a single
/// huge `writeBytes`, so the bytes are streamed in small chunks. Easy to tune.
const int kBluetoothChunkBytes = 512;

/// PRINT-STABILITY-001: a small pause between chunks to let the printer's SPP
/// buffer drain (prevents overrun under pressure printing). Set to zero to disable.
const Duration kBluetoothChunkDelay = Duration(milliseconds: 20);

/// PRINT-STABILITY-001: the low-level Bluetooth Classic (SPP) operations the
/// reliability logic drives, behind a seam so the reconnect/retry/chunked-write
/// behaviour is unit-testable WITHOUT a device or the platform plugin. The real
/// implementation (plugin-backed) lives in `bluetooth_connector_native.dart`
/// (behind the conditional import, so the web build never links it); tests inject
/// a fake. Every method is best-effort and must not throw for control flow.
abstract class BluetoothThermalApi {
  /// Ensures the Android 12+ runtime BLUETOOTH_CONNECT/SCAN permissions.
  Future<bool> ensurePermissions();

  /// Whether the Bluetooth adapter is currently on.
  Future<bool> get isEnabled;

  /// Whether the plugin currently holds an open connection (used to detect + drop
  /// a stale/half-open socket left by a prior job before reconnecting).
  Future<bool> get isConnected;

  /// The bonded/paired devices.
  Future<List<BluetoothDeviceInfo>> pairedDevices();

  /// Opens a connection to the bonded printer at [address]. Returns success.
  Future<bool> connect(String address);

  /// Writes one chunk of bytes to the open connection. Returns success.
  Future<bool> writeBytes(List<int> bytes);

  /// Closes the current connection (best-effort).
  Future<bool> disconnect();
}

/// PRINT-STABILITY-001: the reliability-hardened Bluetooth connector. Plugin-free
/// (drives a [BluetoothThermalApi] seam) so its behaviour is fully testable:
///
///  * **Fresh-socket connect** — a stale/half-open connection from a prior job is
///    the usual cause of "printer is connected but the write fails"; before every
///    connect it drops any existing connection so it never writes to a dead socket.
///  * **Chunked writes** — a large raster image is streamed in [chunkBytes]-sized
///    chunks with a [chunkDelay] pause, so it is not dropped by the SPP buffer.
///  * **One automatic reconnect + retry** — if the first attempt fails it force-
///    resets the connection and retries once, so the operator recovers without
///    restarting the app.
///  * **Bounded + typed** — connect + each chunk are bounded by the caller's
///    timeout; every failure maps to an honest [pp.PrintResult] and NEVER throws.
class BluetoothThermalConnector implements BluetoothPrinterConnector {
  BluetoothThermalConnector({
    required this.api,
    this.chunkBytes = kBluetoothChunkBytes,
    this.chunkDelay = kBluetoothChunkDelay,
  });

  final BluetoothThermalApi api;
  final int chunkBytes;
  final Duration chunkDelay;

  @override
  bool get isSupported => true;

  @override
  Future<bool> ensurePermissions() => api.ensurePermissions();

  @override
  Future<BluetoothPairedResult> pairedDevices() async {
    if (!await api.ensurePermissions()) {
      return const BluetoothPairedResult.failed(
        BluetoothPrinterError.permissionDenied,
      );
    }
    try {
      if (!await api.isEnabled) {
        return const BluetoothPairedResult.failed(
          BluetoothPrinterError.bluetoothOff,
        );
      }
      return BluetoothPairedResult.ok(await api.pairedDevices());
    } catch (_) {
      return const BluetoothPairedResult.failed(
        BluetoothPrinterError.connectFailed,
      );
    }
  }

  @override
  Future<pp.PrintResult> send({
    required String address,
    required Uint8List bytes,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!await api.ensurePermissions()) {
      return const pp.PrintResult.failure(
        pp.PrinterErrorCategory.unsupported,
        'bluetooth permission denied',
      );
    }
    // First attempt; on ANY failure do ONE clean reconnect + retry — this
    // recovers a stale/half-open SPP socket without the operator closing the app.
    final first = await _attempt(address, bytes, timeout, forceReset: false);
    if (first.ok) return first;
    return _attempt(address, bytes, timeout, forceReset: true);
  }

  Future<pp.PrintResult> _attempt(
    String address,
    Uint8List bytes,
    Duration timeout, {
    required bool forceReset,
  }) async {
    try {
      // Always start from a clean socket: on a retry (forceReset) or when the
      // plugin reports a lingering connection, drop it first.
      if (forceReset || await _isConnectedQuietly()) {
        await _disconnectQuietly();
      }
      final connected = await api.connect(address).timeout(timeout);
      if (!connected) {
        return const pp.PrintResult.failure(
          pp.PrinterErrorCategory.unreachable,
          'bluetooth connect failed (printer off / out of range / not bonded)',
        );
      }
      try {
        final wrote = await _writeChunked(bytes, timeout);
        if (!wrote) {
          return const pp.PrintResult.failure(
            pp.PrinterErrorCategory.unknown,
            'bluetooth write failed',
          );
        }
        return const pp.PrintResult.success();
      } finally {
        await _disconnectQuietly();
      }
    } on TimeoutException {
      await _disconnectQuietly();
      return pp.PrintResult.failure(
        pp.PrinterErrorCategory.unreachable,
        'timed out after ${timeout.inMilliseconds}ms',
      );
    } catch (e) {
      await _disconnectQuietly();
      return pp.PrintResult.failure(pp.PrinterErrorCategory.unknown, '$e');
    }
  }

  /// Streams [bytes] in [chunkBytes]-sized chunks, each bounded by [timeout],
  /// with a [chunkDelay] pause between them. Returns false on the first failed
  /// chunk. An empty document is a trivial success.
  Future<bool> _writeChunked(Uint8List bytes, Duration timeout) async {
    if (bytes.isEmpty) return true;
    for (var i = 0; i < bytes.length; i += chunkBytes) {
      final end = i + chunkBytes < bytes.length ? i + chunkBytes : bytes.length;
      final ok = await api.writeBytes(bytes.sublist(i, end)).timeout(timeout);
      if (!ok) return false;
      if (end < bytes.length && chunkDelay > Duration.zero) {
        await Future<void>.delayed(chunkDelay);
      }
    }
    return true;
  }

  Future<bool> _isConnectedQuietly() async {
    try {
      return await api.isConnected;
    } catch (_) {
      return false;
    }
  }

  Future<void> _disconnectQuietly() async {
    try {
      await api.disconnect().timeout(const Duration(seconds: 2));
    } catch (_) {
      // best-effort cleanup
    }
  }
}

/// A [pp.PrintTransport] that delivers ESC/POS bytes to a bonded Bluetooth
/// Classic (SPP) thermal printer via a [BluetoothPrinterConnector]
/// (ANDROID-003). Web-safe: the connector's default impl fails clearly on web.
class BluetoothClassicPrintTransport implements pp.PrintTransport {
  BluetoothClassicPrintTransport({
    required this.connector,
    required this.address,
    this.timeout = const Duration(seconds: 8),
  });

  final BluetoothPrinterConnector connector;

  /// The bonded printer's Bluetooth address (MAC).
  final String address;

  /// Bound for connect + write so an unreachable printer can't hang the UI.
  final Duration timeout;

  @override
  Future<pp.PrintResult> send(Uint8List bytes) =>
      connector.send(address: address, bytes: bytes, timeout: timeout);

  @override
  Future<void> dispose() async {}
}

/// The active Bluetooth connector. The default is platform-resolved (native
/// plugin / web stub); tests override with a fake.
final bluetoothPrinterConnectorProvider = Provider<BluetoothPrinterConnector>(
  (ref) => createBluetoothPrinterConnector(),
);
