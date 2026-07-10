import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

// Web-safe connector selection: the stub (browsers have no Bluetooth Classic +
// no dart:io) is the default; the native channel-backed connector is linked only
// where `dart.library.io` exists. This file itself never imports the platform
// channel, so this package stays importable from the web build.
import 'bluetooth_connector_stub.dart'
    if (dart.library.io) 'bluetooth_connector_native.dart';

/// The Android Bluetooth "imaging" major device class (printers/scanners) —
/// presentation hint only (sort likely printers first); never a filter.
const int kBluetoothImagingMajorClass = 0x0600;

/// A bonded/paired Bluetooth device (ANDROID-003).
class BluetoothDeviceInfo {
  const BluetoothDeviceInfo({
    required this.address,
    required this.name,
    this.majorClass,
  });

  /// The device's Bluetooth address (MAC).
  final String address;

  /// The device's advertised name (may be empty).
  final String name;

  /// The Android Bluetooth major device class
  /// (PRINT-BLUETOOTH-RECOVERY-001; imaging = 0x0600 for printers), or null
  /// when unknown. A presentation hint ONLY — likely printers sort first, but
  /// every bonded device stays selectable (cheap printers often misreport it).
  final int? majorClass;

  /// Whether the class says "imaging" (printer/scanner). False when unknown.
  bool get looksLikePrinter => majorClass == kBluetoothImagingMajorClass;
}

/// Why a Bluetooth print/list attempt could not proceed (maps to localized UI).
enum BluetoothPrinterError {
  /// Bluetooth printing is not available on this build/platform (e.g. web).
  unsupported,

  /// The runtime BLUETOOTH_CONNECT permission was denied.
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
/// (native channel vs. web stub) so the web build never links native code.
abstract class BluetoothPrinterConnector {
  /// Whether Bluetooth printing is possible on this build/platform.
  bool get isSupported;

  /// Ensures the runtime BLUETOOTH_CONNECT permission (Android 12+).
  /// Returns whether it is granted.
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
/// huge write, so the bytes are streamed in small chunks. Easy to tune.
const int kBluetoothChunkBytes = 512;

/// PRINT-STABILITY-001: a small pause between chunks to let the printer's SPP
/// buffer drain (prevents overrun under pressure printing). Zero disables it.
const Duration kBluetoothChunkDelay = Duration(milliseconds: 20);

/// PRINT-BLUETOOTH-RECOVERY-001: how long the printer is given to drain its
/// buffer AFTER the last byte before the socket closes. Closing immediately
/// after the final write truncates the tail of the print on many cheap SPP
/// printers (the bytes are still in the Bluetooth/printer buffer).
const Duration kBluetoothDrainDelay = Duration(milliseconds: 300);

/// PRINT-BLUETOOTH-RECOVERY-001: the typed outcome codes of ONE native
/// Bluetooth print job — the exact wire codes the host app's Kotlin channel
/// returns, so nothing is lost between the native layer and the UI message.
enum BluetoothJobCode {
  /// The whole job (connect + write + drain) succeeded.
  ok,

  /// BLUETOOTH_CONNECT is not granted (Android 12+).
  permission,

  /// The Bluetooth adapter is off (or the device has none).
  bluetoothOff,

  /// The target device is not paired/bonded in Android settings.
  notBonded,

  /// Both the secure and insecure RFCOMM connect attempts failed.
  connectFailed,

  /// The connect attempt hit the native watchdog timeout.
  timeout,

  /// Connected, but writing the bytes failed mid-stream.
  writeFailed,

  /// The platform channel is not available (web/iOS, or the host app does not
  /// register the Bluetooth channel).
  unsupported,

  /// An unclassified failure.
  unknown,
}

/// The result of one native Bluetooth print job (mirrors the Kotlin result map).
class BluetoothJobResult {
  const BluetoothJobResult({
    required this.code,
    this.detail,
    this.bytesSent = 0,
    this.chunks = 0,
  });

  final BluetoothJobCode code;

  /// A developer-facing diagnostic (adapter state, attempt breakdown, byte
  /// counts). Never UI chrome, never printed on paper.
  final String? detail;

  /// Bytes actually written before success/failure (diagnostics).
  final int bytesSent;

  /// Chunks written (diagnostics).
  final int chunks;

  bool get ok => code == BluetoothJobCode.ok;
}

/// The paired-device listing from the native channel: devices OR a typed code.
class BluetoothPairedNative {
  const BluetoothPairedNative.ok(this.devices) : code = BluetoothJobCode.ok;
  const BluetoothPairedNative.failed(this.code) : devices = const [];

  final List<BluetoothDeviceInfo> devices;
  final BluetoothJobCode code;

  bool get ok => code == BluetoothJobCode.ok;
}

/// PRINT-BLUETOOTH-RECOVERY-001: the seam over the HOST APP's in-house native
/// Bluetooth SPP channel + the runtime-permission request.
///
/// The previous implementation drove the `print_bluetooth_thermal` plugin,
/// whose Android side had defects that broke real printing: it prepended a
/// rogue `\n` byte to EVERY write (corrupting a chunked ESC/POS raster stream),
/// returned `false` from `connect` whenever a stale global socket existed,
/// never answered the channel at all when the permission was missing (hanging
/// the Dart future), used only the SECURE RFCOMM socket (the classic cause of
/// flaky connects with cheap SPP printers), and ran `connect` un-timed on a
/// `GlobalScope` coroutine (a Dart-side timeout could not abort it, so the
/// retry collided with the still-running first attempt).
///
/// The replacement is a small, in-house MethodChannel implemented by the POS
/// and KDS `MainActivity` (`restoflow.native_printing/bluetooth`): one
/// ATOMIC, stateless print job per call (connect → chunked exact-byte write →
/// drain → close) with a native watchdog timeout and typed result codes.
/// Behind this seam so the retry/mapping logic is unit-testable without a
/// device. Every method is best-effort and must not throw for control flow.
abstract class BluetoothPrintApi {
  /// Whether the runtime BLUETOOTH_CONNECT permission is currently granted
  /// (always true below Android 12). Check only — never shows a dialog.
  Future<bool> permissionsGranted();

  /// Requests the runtime BLUETOOTH_CONNECT permission (Android 12+ dialog).
  /// CONNECT ONLY — the app never scans (bonded devices only), so a denied
  /// SCAN permission must never block printing. Returns whether granted.
  Future<bool> requestPermissions();

  /// Whether the Bluetooth adapter is currently on.
  Future<bool> isEnabled();

  /// The bonded/paired devices, or a typed failure code.
  Future<BluetoothPairedNative> pairedDevices();

  /// Runs ONE self-contained native print job: cancel discovery → bond check →
  /// connect (secure, then insecure fallback; each bounded by [timeout] via a
  /// native watchdog that closes the socket) → write [bytes] EXACTLY (no
  /// framing/extra bytes) in [chunkBytes]-sized chunks with [chunkDelay]
  /// pauses → wait [drainDelay] → close. Never throws for control flow.
  Future<BluetoothJobResult> printBytes({
    required String address,
    required Uint8List bytes,
    required Duration timeout,
    int chunkBytes,
    Duration chunkDelay,
    Duration drainDelay,
  });
}

/// PRINT-BLUETOOTH-RECOVERY-001: the reliability logic over the in-house
/// native channel — plugin-free and fully unit-testable via [BluetoothPrintApi]:
///
///  * **Permission-first** — checks, then REQUESTS, the Android 12+
///    BLUETOOTH_CONNECT permission (connect only; scan never gates printing).
///  * **One clean retry** — the native job is stateless (fresh socket every
///    time), so a failed connect/write is retried exactly once; permission /
///    adapter-off / not-bonded failures are NOT retried (they cannot succeed).
///  * **Typed, honest mapping** — every native code maps to a distinct
///    [pp.PrinterErrorCategory] so the UI can say exactly what went wrong.
///  * **Bounded** — the native watchdog bounds the connect; an outer safety
///    timeout here guarantees the Dart future can never hang even if the
///    platform side misbehaves.
class ChannelBluetoothConnector implements BluetoothPrinterConnector {
  ChannelBluetoothConnector({
    required this.api,
    this.chunkBytes = kBluetoothChunkBytes,
    this.chunkDelay = kBluetoothChunkDelay,
    this.drainDelay = kBluetoothDrainDelay,
    this.outerTimeoutMargin = const Duration(seconds: 30),
  });

  final BluetoothPrintApi api;
  final int chunkBytes;
  final Duration chunkDelay;
  final Duration drainDelay;

  /// Added to the per-attempt [timeout] to bound the WHOLE native job (two
  /// connect attempts + chunked write + drain) as a never-hang backstop.
  final Duration outerTimeoutMargin;

  @override
  bool get isSupported => true;

  @override
  Future<bool> ensurePermissions() async {
    try {
      if (await api.permissionsGranted()) return true;
      return await api.requestPermissions();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<BluetoothPairedResult> pairedDevices() async {
    if (!await ensurePermissions()) {
      return const BluetoothPairedResult.failed(
        BluetoothPrinterError.permissionDenied,
      );
    }
    try {
      final result = await api.pairedDevices();
      if (!result.ok) {
        return BluetoothPairedResult.failed(switch (result.code) {
          BluetoothJobCode.permission => BluetoothPrinterError.permissionDenied,
          BluetoothJobCode.bluetoothOff => BluetoothPrinterError.bluetoothOff,
          BluetoothJobCode.unsupported => BluetoothPrinterError.unsupported,
          _ => BluetoothPrinterError.connectFailed,
        });
      }
      // Presentation order: devices whose class says "imaging" (printers)
      // first, everything else after, each group stable by name. NEVER hides a
      // device — cheap printers often report a bogus class.
      final sorted = [...result.devices]
        ..sort((a, b) {
          if (a.looksLikePrinter != b.looksLikePrinter) {
            return a.looksLikePrinter ? -1 : 1;
          }
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      return BluetoothPairedResult.ok(sorted);
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
    Duration timeout = kBluetoothPrintTimeout,
  }) async {
    if (!await ensurePermissions()) {
      return const pp.PrintResult.failure(
        pp.PrinterErrorCategory.permissionDenied,
        'BLUETOOTH_CONNECT permission is not granted',
      );
    }
    // First attempt; the native job is stateless (fresh socket per job), so on
    // a RETRYABLE failure do exactly ONE clean retry. Permission / adapter-off
    // / not-bonded can never succeed on a retry and fail fast instead.
    var attempt = await _job(address, bytes, timeout);
    if (!attempt.ok && _retryable(attempt.code)) {
      attempt = await _job(address, bytes, timeout);
    }
    return _toPrintResult(attempt);
  }

  static bool _retryable(BluetoothJobCode code) => switch (code) {
    BluetoothJobCode.connectFailed ||
    BluetoothJobCode.timeout ||
    BluetoothJobCode.writeFailed ||
    BluetoothJobCode.unknown => true,
    _ => false,
  };

  Future<BluetoothJobResult> _job(
    String address,
    Uint8List bytes,
    Duration timeout,
  ) async {
    // Outer never-hang backstop: two native connect attempts (secure +
    // insecure) plus the whole chunked write + drain must fit comfortably.
    final outer = timeout * 2 + outerTimeoutMargin;
    try {
      return await api
          .printBytes(
            address: address,
            bytes: bytes,
            timeout: timeout,
            chunkBytes: chunkBytes,
            chunkDelay: chunkDelay,
            drainDelay: drainDelay,
          )
          .timeout(outer);
    } on TimeoutException {
      return BluetoothJobResult(
        code: BluetoothJobCode.timeout,
        detail:
            'no response from the native bluetooth job after '
            '${outer.inMilliseconds}ms',
      );
    } catch (e) {
      return BluetoothJobResult(code: BluetoothJobCode.unknown, detail: '$e');
    }
  }

  static pp.PrintResult _toPrintResult(BluetoothJobResult job) {
    if (job.ok) return const pp.PrintResult.success();
    final category = switch (job.code) {
      BluetoothJobCode.permission => pp.PrinterErrorCategory.permissionDenied,
      BluetoothJobCode.bluetoothOff => pp.PrinterErrorCategory.bluetoothOff,
      BluetoothJobCode.notBonded => pp.PrinterErrorCategory.notPaired,
      BluetoothJobCode.connectFailed ||
      BluetoothJobCode.timeout => pp.PrinterErrorCategory.unreachable,
      BluetoothJobCode.writeFailed => pp.PrinterErrorCategory.writeFailed,
      BluetoothJobCode.unsupported => pp.PrinterErrorCategory.unsupported,
      BluetoothJobCode.ok ||
      BluetoothJobCode.unknown => pp.PrinterErrorCategory.unknown,
    };
    return pp.PrintResult.failure(category, job.detail);
  }
}

/// A [pp.PrintTransport] that delivers ESC/POS bytes to a bonded Bluetooth
/// Classic (SPP) thermal printer via a [BluetoothPrinterConnector]
/// (ANDROID-003). Web-safe: the connector's default impl fails clearly on web.
class BluetoothClassicPrintTransport implements pp.PrintTransport {
  BluetoothClassicPrintTransport({
    required this.connector,
    required this.address,
    this.timeout = kBluetoothPrintTimeout,
  });

  final BluetoothPrinterConnector connector;

  /// The bonded printer's Bluetooth address (MAC).
  final String address;

  /// Per-connect-attempt bound so an unreachable printer can't hang the UI.
  final Duration timeout;

  @override
  Future<pp.PrintResult> send(Uint8List bytes) =>
      connector.send(address: address, bytes: bytes, timeout: timeout);

  @override
  Future<void> dispose() async {}
}

/// PRINT-BLUETOOTH-RECOVERY-001: the per-connect-attempt Bluetooth budget. A
/// cold SPP connect to a sleeping thermal printer regularly needs more than the
/// old 5s Wi-Fi-style budget (a too-short bound was aborting connects that
/// would have succeeded, and the immediate retry then collided with them).
/// The native watchdog closes the socket at this bound, so it is a REAL limit.
const Duration kBluetoothPrintTimeout = Duration(seconds: 10);

/// The active Bluetooth connector. The default is platform-resolved (native
/// channel / web stub); tests override with a fake.
final bluetoothPrinterConnectorProvider = Provider<BluetoothPrinterConnector>(
  (ref) => createBluetoothPrinterConnector(),
);
