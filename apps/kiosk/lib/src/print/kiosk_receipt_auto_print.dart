import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/kiosk_appearance.dart';
import '../state/kiosk_flow_controller.dart';
import '../state/kiosk_receipt_branding.dart';
import '../state/kiosk_staff_access.dart';
import 'kiosk_receipt_document.dart';

/// KIOSK-001-103 §10 — optional EXACTLY-ONCE auto-print of the customer
/// receipt for a DEFINITIVELY ACCEPTED kiosk order.
///
/// Triggered only from the accepted branch of the submit flow (never
/// in-flight / unconfirmed / rejected / cart states). One logical order
/// prints AT MOST once: an in-memory in-flight latch + a DURABLE bounded
/// printed-order UUID ledger (last [kKioskPrintedLedgerLimit]) absorb widget
/// rebuilds and idempotent replays. A print failure NEVER touches the
/// accepted order — the confirmation stays, a localized non-blocking notice
/// appears, and there is no automatic retry loop.

const int kKioskPrintedLedgerLimit = 100;

/// The per-device auto-print preference key (kiosk namespace — never POS/KDS).
String kioskAutoPrintPrefKey(String deviceId) =>
    'restoflow.autoprint.kiosk.receipt.$deviceId';

String kioskPrintedLedgerKey(String deviceId) =>
    'restoflow.kiosk.printed_receipts.v1.$deviceId';

/// Durable bounded newest-first printed-order ledger (the project's
/// JSON-envelope-in-one-string idiom; NOT an offline order queue). Recorded
/// only AFTER a transport-accepted send, so a failed print stays printable
/// on a legitimate replay.
class KioskPrintedReceiptLedger {
  KioskPrintedReceiptLedger(this._prefs);

  final SharedPreferences _prefs;

  List<String> _read(String deviceId) {
    try {
      final raw = _prefs.getString(kioskPrintedLedgerKey(deviceId));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['v'] != 1) return const [];
      final ids = decoded['ids'];
      if (ids is! List) return const [];
      return [
        for (final e in ids)
          if (e is Map && e['id'] is String) e['id'] as String,
      ];
    } catch (_) {
      return const []; // unreadable => treated as empty, never a crash
    }
  }

  bool contains(String deviceId, String orderId) =>
      _read(deviceId).contains(orderId);

  Future<void> record(String deviceId, String orderId) async {
    final ids = _read(deviceId);
    if (ids.contains(orderId)) return;
    final entries = <Map<String, Object?>>[
      {'id': orderId, 'at': DateTime.now().toUtc().toIso8601String()},
      for (final id in ids.take(kKioskPrintedLedgerLimit - 1)) {'id': id},
    ];
    try {
      await _prefs.setString(
        kioskPrintedLedgerKey(deviceId),
        jsonEncode({'v': 1, 'ids': entries}),
      );
    } catch (_) {
      // Best-effort durability: the in-memory latch still holds this run.
    }
  }
}

final kioskPrintedReceiptLedgerProvider = Provider<KioskPrintedReceiptLedger?>(
  (ref) => null,
);

/// The per-device auto-print toggle — default OFF (§10).
final kioskAutoPrintReceiptProvider =
    AsyncNotifierProvider<KioskAutoPrintReceiptController, bool>(
      KioskAutoPrintReceiptController.new,
    );

class KioskAutoPrintReceiptController extends AsyncNotifier<bool> {
  String? get _deviceId => ref.watch(kioskDeviceContextProvider)?.deviceId;

  @override
  Future<bool> build() async {
    final deviceId = _deviceId;
    if (deviceId == null) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(kioskAutoPrintPrefKey(deviceId)) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    state = AsyncData(enabled);
    final deviceId = _deviceId;
    if (deviceId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kioskAutoPrintPrefKey(deviceId), enabled);
    } catch (_) {
      // Best-effort persistence; the in-session choice applies.
    }
  }
}

/// Send seam: encodes+delivers one ESC/POS document. The DEFAULT resolves
/// the device's saved kiosk transport (network/Bluetooth) through the shared
/// native store's READY provider (never the sync `.valueOrNull` snapshot —
/// the documented cold-start first-print trap); web/tests without a printer
/// resolve to null. Tests override the whole provider with a capturing fake.
typedef KioskReceiptSend =
    Future<pp.BridgeSubmitResult> Function(pp.PrintDocument document);

final kioskReceiptSendProvider =
    Provider<Future<KioskReceiptSend?> Function()?>((ref) {
      return () async {
        final factory = await ref.read(
          activeNativeTransportFactoryReadyProvider.future,
        );
        if (factory == null) return null;
        return (document) =>
            NativeEscPosSender(transportFactory: factory).send(document);
      };
    });

/// Honest per-order print status for the confirmation screen's non-blocking
/// notice. Keyed by order id so a new order never shows a stale notice.
enum KioskReceiptPrintOutcome { sent, failed, notConfigured }

typedef KioskReceiptPrintStatus = ({
  String orderId,
  KioskReceiptPrintOutcome outcome,
});

final kioskReceiptPrintStatusProvider = StateProvider<KioskReceiptPrintStatus?>(
  (ref) => null,
);

final kioskReceiptAutoPrintProvider = Provider<KioskReceiptAutoPrint>(
  KioskReceiptAutoPrint.new,
);

class KioskReceiptAutoPrint {
  KioskReceiptAutoPrint(this._ref);

  final Ref _ref;
  final Set<String> _inFlight = {};
  final Set<String> _sentThisRun = {};

  /// Fire-and-forget from the ACCEPTED submit branch only. Never throws.
  Future<void> onOrderAccepted({
    required KioskOrderSnapshot order,
    required String lang,
  }) async {
    try {
      await _run(order: order, lang: lang);
    } catch (_) {
      // A print problem must NEVER surface as an order problem.
    }
  }

  Future<void> _run({
    required KioskOrderSnapshot order,
    required String lang,
  }) async {
    // Context-free localization: the controller runs outside the widget tree.
    final l10n = lookupAppLocalizations(Locale(lang));
    final orderId = order.orderId;
    if (orderId == null) return; // demo/fixture orders never print
    if (!(_ref.read(kioskAutoPrintReceiptProvider).valueOrNull ?? false)) {
      // Re-read through the future so a cold start answers the STORED pref
      // instead of a still-loading default.
      final enabled = await _ref.read(kioskAutoPrintReceiptProvider.future);
      if (!enabled) return;
    }
    // Exactly-once: in-memory latch (rebuild/double-fire) + this-run success
    // set + the durable ledger (idempotent replay across restarts).
    if (_sentThisRun.contains(orderId) || !_inFlight.add(orderId)) return;
    try {
      final deviceId = _ref.read(kioskDeviceContextProvider)?.deviceId;
      final ledger = _ref.read(kioskPrintedReceiptLedgerProvider);
      if (deviceId != null && (ledger?.contains(deviceId, orderId) ?? false)) {
        _sentThisRun.add(orderId);
        return;
      }
      final resolveSend = _ref.read(kioskReceiptSendProvider);
      final send = resolveSend == null ? null : await resolveSend();
      if (send == null) {
        _publish(orderId, KioskReceiptPrintOutcome.notConfigured);
        return;
      }
      // §12: the RECEIPT identity is the Dashboard branding — the device
      // appearance logo is never consulted here. Branding failures degrade
      // to the real restaurant name (appearance display name as the last
      // real fallback; never the fixture).
      KioskReceiptBranding? branding;
      try {
        branding = await _ref.read(kioskReceiptBrandingProvider.future);
      } catch (_) {
        branding = null;
      }
      final appearance = _ref.read(kioskAppearanceProvider);
      final name = (branding?.restaurantName?.isNotEmpty ?? false)
          ? branding!.restaurantName!
          : appearance.restaurantDisplayName;
      pp.LogoRaster? raster;
      final logoBytes = branding?.logoBytes;
      if (logoBytes != null) {
        try {
          final decoder = _ref.read(kioskLogoDecoderProvider);
          final decoded = decoder == null ? null : await decoder(logoBytes);
          if (decoded != null) {
            raster = const pp.LogoRasterizer().rasterizeForProfile(
              decoded,
              _ref.read(activeNativeMediaProfileProvider),
            );
          }
        } catch (_) {
          raster = null; // logo raster failure => text-identity receipt
        }
      }
      final profile = _ref.read(activeNativeMediaProfileProvider);
      final doc = buildKioskReceiptDocument(
        l10n: l10n,
        order: order,
        restaurantName: name,
        lang: lang,
        logoRaster: raster,
        columns: profile.columns,
      );
      pp.PrintDocument rendered = doc;
      try {
        rendered = await pp.rasterizeForMediaProfile(
          doc,
          rasterizer: _ref.read(nativePrintRasterizerProvider),
          profile: profile,
        );
      } catch (_) {
        rendered = doc;
      }
      final result = await send(rendered);
      if (result.ok) {
        _sentThisRun.add(orderId);
        if (deviceId != null) await ledger?.record(deviceId, orderId);
        _publish(orderId, KioskReceiptPrintOutcome.sent);
      } else {
        _publish(orderId, KioskReceiptPrintOutcome.failed);
      }
    } finally {
      _inFlight.remove(orderId);
    }
  }

  void _publish(String orderId, KioskReceiptPrintOutcome outcome) {
    _ref.read(kioskReceiptPrintStatusProvider.notifier).state = (
      orderId: orderId,
      outcome: outcome,
    );
  }
}

/// Decoder seam for the Dashboard logo bytes (the real root wires the
/// dart:ui-backed decoder from restoflow_l10n; tests fake or omit it).
typedef KioskLogoDecode = Future<pp.DecodedLogoImage?> Function(List<int>);

final kioskLogoDecoderProvider = Provider<KioskLogoDecode?>((ref) => null);
