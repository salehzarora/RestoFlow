import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

import '../state/kiosk_receipt_branding.dart';
import '../state/kiosk_staff_access.dart';

/// KIOSK-PRINT-114B.2 — the kiosk printer PURPOSE model.
///
/// Mirrors the proven POS key-segment scheme: the CUSTOMER RECEIPT role keeps
/// the shipped shared-store keys byte-for-byte (`restoflow.printer.*.kiosk.
/// deviceId` — ZERO migration), and the new KITCHEN TICKET role adds a
/// `kitchen_ticket.` segment. The kitchen slot is kiosk-local state over the
/// same shared config types; nothing here ever touches a POS/KDS key.
enum KioskPrinterPurpose {
  customerReceipt(''),
  kitchenTicket('kitchen_ticket.');

  const KioskPrinterPurpose(this.keySegment);

  final String keySegment;
}

String kioskKitchenNetworkKey(String deviceId) =>
    'restoflow.printer.network.kiosk.kitchen_ticket.$deviceId';
String kioskKitchenBluetoothKey(String deviceId) =>
    'restoflow.printer.bluetooth.kiosk.kitchen_ticket.$deviceId';
String kioskKitchenSelectedKey(String deviceId) =>
    'restoflow.printer.selected.kiosk.kitchen_ticket.$deviceId';
String kioskKitchenAutoPrintKey(String deviceId) =>
    'restoflow.autoprint.kiosk.kitchen.$deviceId';

/// ONE process-wide destination send gate: customer receipt AND kitchen
/// ticket physical sends (and test prints) serialize per physical printer
/// through this single instance — never one gate per role.
final kioskPrinterDestinationSendGateProvider =
    Provider<pp.PrinterDestinationSendGate>(
      (ref) => pp.PrinterDestinationSendGate(),
    );

String? _kioskDeviceId(Ref ref) =>
    ref.watch(kioskDeviceContextProvider)?.deviceId;

/// The saved KITCHEN network destination (null = not configured).
final kioskKitchenNetworkConfigProvider =
    AsyncNotifierProvider<
      KioskKitchenNetworkConfigController,
      NetworkPrinterConfig?
    >(KioskKitchenNetworkConfigController.new);

class KioskKitchenNetworkConfigController
    extends AsyncNotifier<NetworkPrinterConfig?> {
  @override
  Future<NetworkPrinterConfig?> build() async {
    final deviceId = _kioskDeviceId(ref);
    if (deviceId == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kioskKitchenNetworkKey(deviceId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? NetworkPrinterConfig.fromJson(decoded)
          : null;
    } catch (_) {
      return null; // unreadable => not configured, never a crash
    }
  }

  Future<void> save(NetworkPrinterConfig config) async {
    state = AsyncData(config);
    final deviceId = _kioskDeviceId(ref);
    if (deviceId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        kioskKitchenNetworkKey(deviceId),
        jsonEncode(config.toJson()),
      );
    } catch (_) {}
  }
}

/// The saved KITCHEN Bluetooth destination (null = not configured).
final kioskKitchenBluetoothConfigProvider =
    AsyncNotifierProvider<
      KioskKitchenBluetoothConfigController,
      BluetoothPrinterConfig?
    >(KioskKitchenBluetoothConfigController.new);

class KioskKitchenBluetoothConfigController
    extends AsyncNotifier<BluetoothPrinterConfig?> {
  @override
  Future<BluetoothPrinterConfig?> build() async {
    final deviceId = _kioskDeviceId(ref);
    if (deviceId == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kioskKitchenBluetoothKey(deviceId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? BluetoothPrinterConfig.fromJson(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(BluetoothPrinterConfig config) async {
    state = AsyncData(config);
    final deviceId = _kioskDeviceId(ref);
    if (deviceId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        kioskKitchenBluetoothKey(deviceId),
        jsonEncode(config.toJson()),
      );
    } catch (_) {}
  }
}

/// The KITCHEN role's selected transport (default network, like the shared
/// store's convention).
final kioskKitchenSelectedTransportProvider =
    AsyncNotifierProvider<
      KioskKitchenSelectedTransportController,
      PrinterTransportKind
    >(KioskKitchenSelectedTransportController.new);

class KioskKitchenSelectedTransportController
    extends AsyncNotifier<PrinterTransportKind> {
  @override
  Future<PrinterTransportKind> build() async {
    final deviceId = _kioskDeviceId(ref);
    if (deviceId == null) return PrinterTransportKind.network;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kioskKitchenSelectedKey(deviceId));
      return raw == PrinterTransportKind.bluetooth.name
          ? PrinterTransportKind.bluetooth
          : PrinterTransportKind.network;
    } catch (_) {
      return PrinterTransportKind.network;
    }
  }

  Future<void> select(PrinterTransportKind kind) async {
    state = AsyncData(kind);
    final deviceId = _kioskDeviceId(ref);
    if (deviceId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kioskKitchenSelectedKey(deviceId), kind.name);
    } catch (_) {}
  }
}

/// The KITCHEN auto-print toggle — default OFF (never inherited from the
/// customer role).
final kioskKitchenAutoPrintEnabledProvider =
    AsyncNotifierProvider<KioskKitchenAutoPrintController, bool>(
      KioskKitchenAutoPrintController.new,
    );

class KioskKitchenAutoPrintController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final deviceId = _kioskDeviceId(ref);
    if (deviceId == null) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(kioskKitchenAutoPrintKey(deviceId)) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    state = AsyncData(enabled);
    final deviceId = _kioskDeviceId(ref);
    if (deviceId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kioskKitchenAutoPrintKey(deviceId), enabled);
    } catch (_) {}
  }
}

/// TRUE when the server-reported branch capability includes kitchen_ticket —
/// i.e. the branch kitchen workflow is printer_only (114B.1 widening).
/// STRICT purpose check (never the legacy role fallback) and FAIL-CLOSED:
/// no assignments / fetch failure / demo => false, so a kiosk never assumes
/// kitchen authority the server did not grant.
final kioskKitchenPrintSupportedProvider = FutureProvider<bool>((ref) async {
  try {
    final result = await ref.watch(kioskPrinterAssignmentsProvider.future);
    if (result == null) return false;
    return switch (result) {
      Success(:final value) => value.printers.any(
        (p) => p.supportedPurposes.contains('kitchen_ticket'),
      ),
      Failure() => false,
    };
  } catch (_) {
    return false;
  }
});

/// The kitchen role's resolved physical target for ONE send.
class KioskKitchenPrintTarget {
  const KioskKitchenPrintTarget.network(NetworkPrinterConfig this.network)
    : bluetooth = null;
  const KioskKitchenPrintTarget.bluetooth(BluetoothPrinterConfig this.bluetooth)
    : network = null;

  final NetworkPrinterConfig? network;
  final BluetoothPrinterConfig? bluetooth;

  String get destinationKey => network != null
      ? pp.PrinterDestinationSendGate.networkKey(network!.host, network!.port)
      : pp.PrinterDestinationSendGate.bluetoothKey(bluetooth!.address);
}

/// Resolves the kitchen role's usable target for its SELECTED transport, or
/// null when not configured.
Future<KioskKitchenPrintTarget?> resolveKioskKitchenPrintTarget(Ref ref) async {
  final kind = await ref.read(kioskKitchenSelectedTransportProvider.future);
  switch (kind) {
    case PrinterTransportKind.network:
      final config = await ref.read(kioskKitchenNetworkConfigProvider.future);
      if (config == null || !isValidPrinterHost(config.host)) return null;
      return KioskKitchenPrintTarget.network(config);
    case PrinterTransportKind.bluetooth:
      final config = await ref.read(kioskKitchenBluetoothConfigProvider.future);
      if (config == null || config.address.trim().isEmpty) return null;
      return KioskKitchenPrintTarget.bluetooth(config);
  }
}

/// The submit-time claim decision (§9): TRUE only when the branch is
/// printer_only (server-reported kitchen support), the kitchen auto-print
/// toggle is ON, and the selected kitchen transport has a usable saved
/// destination. Everything else — including an unreachable assignments read
/// — is FALSE, so the wire stays byte-compatible with a pre-114B hosted
/// backend (the argument is only ever sent when the server already granted
/// kitchen purposes).
final kioskKitchenClaimDecisionProvider = FutureProvider<bool>((ref) async {
  try {
    final supported = await ref.watch(
      kioskKitchenPrintSupportedProvider.future,
    );
    if (!supported) return false;
    final enabled = await ref.watch(
      kioskKitchenAutoPrintEnabledProvider.future,
    );
    if (!enabled) return false;
    return await resolveKioskKitchenPrintTarget(ref) != null;
  } catch (_) {
    return false;
  }
});
