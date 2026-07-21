import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pos_kitchen_spool_capability.dart';
import 'pos_kitchen_spool_composition_web.dart'
    if (dart.library.io) 'pos_kitchen_spool_composition_native.dart';
import 'pos_kitchen_spool_hooks.dart';

export 'pos_kitchen_spool_capability.dart' show PosKitchenSpoolCapability;
export 'pos_kitchen_spool_hooks.dart' show PosKitchenSpoolLifecycleHooks;

/// KITCHEN-MODE-001C2C — the typed operational capability of the kitchen
/// spool (safe scalars only; updated by the native composition after each
/// lifecycle run; permanently [PosKitchenSpoolCapability.idle] on web).
final posKitchenSpoolCapabilityProvider =
    StateProvider<PosKitchenSpoolCapability>(
      (_) => PosKitchenSpoolCapability.idle,
    );

/// KITCHEN-MODE-001C2B — the platform-split composition seam for the
/// kitchen-spool runtime.
///
/// The DEFAULT import target is the WEB branch (always null, zero native
/// imports); only `dart.library.io` platforms link the native branch that
/// assembles the real [PosKitchenSpoolRuntime]. This keeps drift/sqlite3
/// FFI, dart:io, and path_provider entirely OUT of the Flutter web compile
/// graph while native behavior is unchanged. `main.dart` stays untouched —
/// the ONLY production caller is the [PosSyncLifecycle] startup/resume hook
/// (LOCKED D4).
final posKitchenSpoolRuntimeProvider = Provider<PosKitchenSpoolLifecycleHooks?>(
  buildPosKitchenSpoolRuntime,
);
