import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory;
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart'
    show KitchenSpoolDatabaseFactory;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show
        FlutterSecureDeviceSessionStore,
        SupabaseDeviceKitchenModeRepository,
        SupabaseDevicePrinterAssignmentsRepository,
        SupabaseKitchenDispatchAckRepository,
        SupabaseKitchenDispatchPullRepository,
        runtimeConfigProvider;

import '../data/ids.dart' show clientIdGeneratorProvider;
import '../state/pos_bluetooth_printer_config.dart'
    show posKitchenBluetoothPrinterConfigProvider;
import '../state/pos_device_context.dart' show posDeviceContextProvider;
import '../state/pos_network_printer_config.dart'
    show posKitchenNetworkPrinterConfigProvider;
import '../state/pos_printer_transport.dart'
    show posKitchenSelectedPrinterTransportProvider;
import '../state/pos_session.dart' show posAuthTransportProvider;
import 'kitchen_destination_resolver.dart';
import 'pos_kitchen_spool_hooks.dart';
import 'pos_kitchen_spool_platform.dart';
import 'pos_kitchen_spool_runtime.dart';
import 'pos_secure_kitchen_mode_cache.dart';

/// KITCHEN-MODE-001C2B — the NATIVE (`dart.library.io`) composition branch.
///
/// This is the ONLY file that hands the lifecycle a real
/// [PosKitchenSpoolRuntime]; it is linked exclusively through the
/// conditional import in `pos_kitchen_spool_composition.dart`, so
/// drift/sqlite3 FFI, dart:io, and path_provider never enter the Flutter
/// web compile graph. Self-assembles from existing providers; inert in demo
/// mode and whenever the real transport is absent.
PosKitchenSpoolLifecycleHooks? buildPosKitchenSpoolRuntime(Ref ref) {
  const platform = PosKitchenSpoolPlatform();
  if (!platform.supportsSecureSpool) return null;
  if (ref.watch(runtimeConfigProvider).isDemoMode) return null;
  final transport = ref.watch(posAuthTransportProvider);
  if (transport == null) return null;
  final secretStore = FlutterSecureDeviceSessionStoreProvider.of();
  return PosKitchenSpoolRuntime(
    platform: platform,
    deviceContext: () => ref.read(posDeviceContextProvider),
    secretStore: secretStore,
    modeRepository: SupabaseDeviceKitchenModeRepository(
      transport: transport,
      secretStore: secretStore,
    ),
    ackRepository: SupabaseKitchenDispatchAckRepository(
      transport: transport,
      secretStore: secretStore,
    ),
    databaseFactoryBuilder: () => KitchenSpoolDatabaseFactory(
      documentsDirectoryProvider: getApplicationDocumentsDirectory,
    ),
    // CORRECTION-001: the dormant drain seam is FULLY wired — but it can
    // only ever run for a trusted printer-only-with-revision mode result,
    // which the production mode repository can never construct (D1), and
    // the server independently refuses pulls without a readiness report.
    pullRepository: SupabaseKitchenDispatchPullRepository(
      transport: transport,
      secretStore: secretStore,
    ),
    localJobIdGenerator: () => ref.read(clientIdGeneratorProvider).newId(),
    destinationResolver: () async {
      // ACCEPTED LIMITATION (correction pass): the assignment contract has
      // no stable local↔server printer identity — the D2 binding (enabled +
      // kitchen purpose + matching transport + 80mm) is the one-printer
      // pilot's contract; a stable assignment id is a 001C3+ additive
      // extension.
      final assignments = await SupabaseDevicePrinterAssignmentsRepository(
        transport: transport,
        secretStore: secretStore,
      ).load();
      final snapshot = assignments.fold<DevicePrinterAssignments?>(
        (value) => value,
        (_) => null,
      );
      if (snapshot == null) {
        // Could not DETERMINE the assignment state — fail closed rather
        // than importing rows as blocked on a guess.
        throw const KitchenSpoolDestinationUnresolvableException();
      }
      final selected = await ref.read(
        posKitchenSelectedPrinterTransportProvider.future,
      );
      final network = await ref.read(
        posKitchenNetworkPrinterConfigProvider.future,
      );
      final bluetooth = await ref.read(
        posKitchenBluetoothPrinterConfigProvider.future,
      );
      return const KitchenDestinationResolver().resolve(
        selectedTransport: selected,
        networkConfig: network,
        bluetoothConfig: bluetooth,
        assignments: snapshot,
      );
    },
    modeCache: PosSecureKitchenModeCache(platform: platform),
  );
}

/// Small indirection so tests can see exactly which secret store the
/// composition uses (the SAME Keystore-backed store as device pairing).
abstract final class FlutterSecureDeviceSessionStoreProvider {
  static DeviceSessionSecretStore of() => FlutterSecureDeviceSessionStore();
}
