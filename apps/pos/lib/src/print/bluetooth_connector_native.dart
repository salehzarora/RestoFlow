import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import 'bluetooth_printer.dart';

/// Native (`dart:io`) Bluetooth connector (ANDROID-003). Android uses the
/// plugin-backed connector; other native platforms (iOS/desktop) report
/// unsupported for this Android-focused MVP. Web never links this file.
BluetoothPrinterConnector createBluetoothPrinterConnector() =>
    defaultTargetPlatform == TargetPlatform.android
    ? const PluginBluetoothPrinterConnector()
    : const _UnsupportedNativeConnector();

/// Talks to a bonded Bluetooth Classic (SPP) thermal printer via
/// `print_bluetooth_thermal` + `permission_handler`. Best-effort — every path
/// maps to a typed result and NEVER throws / hangs (bounded by the timeout).
class PluginBluetoothPrinterConnector implements BluetoothPrinterConnector {
  const PluginBluetoothPrinterConnector();

  @override
  bool get isSupported => true;

  @override
  Future<bool> ensurePermissions() async {
    try {
      final results = await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ].request();
      return results.values.every((s) => s.isGranted);
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
      final enabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!enabled) {
        return const BluetoothPairedResult.failed(
          BluetoothPrinterError.bluetoothOff,
        );
      }
      final paired = await PrintBluetoothThermal.pairedBluetooths;
      return BluetoothPairedResult.ok([
        for (final d in paired)
          BluetoothDeviceInfo(address: d.macAdress, name: d.name),
      ]);
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
    if (!await ensurePermissions()) {
      return const pp.PrintResult.failure(
        pp.PrinterErrorCategory.unsupported,
        'bluetooth permission denied',
      );
    }
    try {
      final connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: address,
      ).timeout(timeout);
      if (!connected) {
        return const pp.PrintResult.failure(
          pp.PrinterErrorCategory.unreachable,
          'bluetooth connect failed (printer off / out of range / not bonded)',
        );
      }
      try {
        final wrote = await PrintBluetoothThermal.writeBytes(
          bytes.toList(),
        ).timeout(timeout);
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

  Future<void> _disconnectQuietly() async {
    try {
      await PrintBluetoothThermal.disconnect.timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {
      // ignore — best-effort cleanup.
    }
  }
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
    Duration timeout = const Duration(seconds: 8),
  }) async => const pp.PrintResult.failure(
    pp.PrinterErrorCategory.unsupported,
    'Bluetooth printing is only implemented on Android.',
  );
}
