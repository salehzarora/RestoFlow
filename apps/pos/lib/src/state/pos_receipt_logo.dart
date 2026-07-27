import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceReceiptLogoReader, ReceiptLogoBytes;
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart' show FlutterLogoDecoder;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import '../data/receipt_logo_raster_cache.dart';
import '../data/receipt_logo_raster_cache_stub.dart'
    if (dart.library.io) '../data/receipt_logo_raster_cache_native.dart';
import '../print/receipt_logo_asset.dart';
import 'pos_bluetooth_printer_config.dart';
import 'pos_network_printer_config.dart';
import 'pos_printer_assignments.dart';
import 'pos_printer_transport.dart';

/// PRINT-BRANDING-LOGO-001 — the POS-side receipt-logo resolver (§16).
///
/// It turns the CURRENT server-delivered branding pointer (from the token-proven
/// device assignments) into a print-ready [ReceiptLogoAsset] for the ACTIVE
/// media profile, using a durable raster cache first (fast + offline) and, on a
/// miss, a background download + decode + rasterize + cache. Every step
/// fail-closes to null (text-only) — the logo NEVER blocks the receipt.

/// The current restaurant receipt-logo configuration for this station.
class PosReceiptLogoConfig {
  const PosReceiptLogoConfig({
    required this.organizationId,
    required this.restaurantId,
    required this.path,
    required this.version,
  });

  final String organizationId;
  final String restaurantId;
  final String path;
  final int version;
}

/// The durable raster cache (native file-backed; in-memory on web/tests).
final receiptLogoRasterCacheProvider = Provider<ReceiptLogoRasterCache>(
  (ref) => createDefaultReceiptLogoRasterCache(),
);

/// The logo download seam (token-proven device read). Null by default (demo /
/// unconfigured -> text-only); overridden in `main.dart` for real mode.
final posReceiptLogoReaderProvider = Provider<DeviceReceiptLogoReader?>(
  (ref) => null,
);

/// The ACTIVE media profile for the customer-receipt printer (mirrors the
/// resolution in `posActivePrintBridgeProvider`). Drives the logo raster width
/// so a printer swap re-rasterizes rather than reusing a wrong-width bitmap.
final posActiveMediaProfileProvider = Provider<pp.MediaProfile>((ref) {
  if (!ref.watch(posNativePrintingAvailableProvider)) {
    return pp.MediaProfile.continuous80;
  }
  final selected =
      ref.watch(posSelectedPrinterTransportProvider).valueOrNull ??
      PosPrinterTransportKind.network;
  switch (selected) {
    case PosPrinterTransportKind.bluetooth:
      final bt = ref.watch(posBluetoothPrinterConfigProvider).valueOrNull;
      if (bt != null) return bt.mediaProfile;
    case PosPrinterTransportKind.network:
      final net = ref.watch(posNetworkPrinterConfigProvider).valueOrNull;
      if (net != null) return net.mediaProfile;
  }
  return pp.MediaProfile.continuous80;
});

/// The current branding config, or null when there is no printable logo (no
/// reader, load failure, disabled, no path, or missing tenant scope).
final posReceiptLogoConfigProvider = Provider<PosReceiptLogoConfig?>((ref) {
  final snapshot = switch (ref
      .watch(posPrinterAssignmentsProvider)
      .valueOrNull) {
    Success(:final value) => value,
    _ => null,
  };
  if (snapshot == null || !snapshot.hasReceiptLogo) return null;
  return PosReceiptLogoConfig(
    organizationId: snapshot.organizationId!,
    restaurantId: snapshot.restaurantId!,
    path: snapshot.receiptLogoPath!,
    version: snapshot.receiptLogoVersion,
  );
});

/// The resolved, ready-to-print logo asset for the current config + active media
/// profile — or null (text-only). Read by every customer-receipt path; a null
/// value yields a byte-identical no-logo receipt.
final posReceiptLogoAssetProvider =
    StateNotifierProvider<PosReceiptLogoController, ReceiptLogoAsset?>((ref) {
      final controller = PosReceiptLogoController(
        cache: ref.watch(receiptLogoRasterCacheProvider),
        reader: ref.watch(posReceiptLogoReaderProvider),
      );
      // Re-resolve whenever the branding config OR the active media profile
      // changes (prewarm on config load, re-rasterize on printer/profile swap).
      ref.listen<PosReceiptLogoConfig?>(posReceiptLogoConfigProvider, (
        _,
        config,
      ) {
        controller.resolve(config, ref.read(posActiveMediaProfileProvider));
      }, fireImmediately: true);
      ref.listen<pp.MediaProfile>(posActiveMediaProfileProvider, (_, profile) {
        controller.resolve(ref.read(posReceiptLogoConfigProvider), profile);
      });
      return controller;
    });

/// Resolves + caches the receipt-logo asset. Every resolve is guarded by an
/// epoch counter so a config/profile change mid-prewarm supersedes the stale
/// in-flight work (never a wrong-restaurant or wrong-width raster).
class PosReceiptLogoController extends StateNotifier<ReceiptLogoAsset?> {
  PosReceiptLogoController({
    required this.cache,
    required this.reader,
    this.decoder = const FlutterLogoDecoder(),
  }) : super(null);

  final ReceiptLogoRasterCache cache;
  final DeviceReceiptLogoReader? reader;
  final FlutterLogoDecoder decoder;
  final pp.LogoRasterizer _rasterizer = const pp.LogoRasterizer();

  int _epoch = 0;

  /// Resolve the asset for [config] on [profile]. Cache-first, then a
  /// download+decode+rasterize+cache on a miss. Fail-closes to null throughout.
  Future<void> resolve(
    PosReceiptLogoConfig? config,
    pp.MediaProfile profile,
  ) async {
    final epoch = ++_epoch;
    if (config == null) {
      _set(epoch, null);
      return;
    }
    final key = ReceiptLogoCacheKey(
      organizationId: config.organizationId,
      restaurantId: config.restaurantId,
      logoVersion: config.version,
      mediaProfileId: profile.idKey,
      widthDots: profile.widthDots,
      preprocessingVersion: pp.kLogoRasterPreprocessingVersion,
    );

    // 1. Durable cache first — instant, offline-capable.
    final cached = await _safeRead(key);
    if (epoch != _epoch) return; // superseded
    if (cached != null) {
      _set(epoch, _assetFromCache(cached, profile));
      return;
    }

    // 2. Miss: download the source (null seam / offline / failure -> text-only).
    final logoReader = reader;
    if (logoReader == null) {
      _set(epoch, null);
      return;
    }
    ReceiptLogoBytes? fetched;
    try {
      fetched = await logoReader.load(config.path);
    } catch (_) {
      fetched = null;
    }
    if (epoch != _epoch) return;
    if (fetched == null) {
      _set(epoch, null);
      return;
    }

    // 3. Decode + rasterize for the active profile. A decode/convert failure
    //    still yields an asset with source bytes (HTML/preview) but no raster
    //    (native then prints text-only).
    pp.LogoRaster? raster;
    try {
      raster = await decoder.decodeAndRasterize(
        fetched.bytes,
        profile,
        rasterizer: _rasterizer,
      );
    } catch (_) {
      raster = null;
    }
    if (epoch != _epoch) return;

    // 4. Persist the raster (best-effort) so the next print is instant + offline.
    if (raster != null) {
      await _safeWrite(
        key,
        ReceiptLogoCacheEntry(
          rasterData: raster.data,
          widthBytes: raster.widthBytes,
          heightDots: raster.heightDots,
          sourceBytes: fetched.bytes,
          sourceMime: fetched.mime,
        ),
      );
    }
    if (epoch != _epoch) return;
    _set(
      epoch,
      ReceiptLogoAsset(
        sourceBytes: fetched.bytes,
        sourceMime: fetched.mime,
        raster: raster,
      ),
    );
  }

  void _set(int epoch, ReceiptLogoAsset? asset) {
    if (epoch == _epoch && mounted) state = asset;
  }

  ReceiptLogoAsset _assetFromCache(
    ReceiptLogoCacheEntry entry,
    pp.MediaProfile profile,
  ) {
    return ReceiptLogoAsset(
      sourceBytes: entry.sourceBytes,
      sourceMime: entry.sourceMime,
      raster: pp.LogoRaster(
        widthDots: profile.widthDots,
        widthBytes: entry.widthBytes,
        heightDots: entry.heightDots,
        data: entry.rasterData,
      ),
    );
  }

  Future<ReceiptLogoCacheEntry?> _safeRead(ReceiptLogoCacheKey key) async {
    try {
      return await cache.read(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _safeWrite(
    ReceiptLogoCacheKey key,
    ReceiptLogoCacheEntry entry,
  ) async {
    try {
      await cache.write(key, entry);
    } catch (_) {
      // best-effort
    }
  }
}
