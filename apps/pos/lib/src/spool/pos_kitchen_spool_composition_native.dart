import 'dart:ui' as ui show PlatformDispatcher;

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
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show
        ChannelBluetoothConnector,
        KitchenBluetoothSingleAttempt,
        bluetoothPrinterConnectorProvider,
        classifyKitchenBluetoothAttempt,
        nativePrintRasterizerProvider;
import 'package:restoflow_printing/restoflow_printing.dart'
    show
        KitchenTransportOutcome,
        KitchenTransportOutcomeKind,
        sendKitchenBytesOverTcp;

import '../data/ids.dart' show clientIdGeneratorProvider;
import '../print/native_print_bridges.dart'
    show kPosNativePrintTimeout, posPrinterDestinationSendGateProvider;
import '../state/pos_bluetooth_printer_config.dart'
    show posKitchenBluetoothPrinterConfigProvider;
import '../state/pos_device_context.dart' show posDeviceContextProvider;
import '../state/pos_network_printer_config.dart'
    show posKitchenNetworkPrinterConfigProvider;
import '../state/pos_printer_transport.dart'
    show posKitchenSelectedPrinterTransportProvider;
import '../state/pos_session.dart' show posAuthTransportProvider;
import 'kitchen_destination_resolver.dart';
import 'kitchen_ticket_renderer.dart';
import 'pos_kitchen_spool_capability.dart';
import 'pos_kitchen_spool_composition.dart'
    show posKitchenSpoolCapabilityProvider;
import 'pos_kitchen_spool_hooks.dart';
import 'pos_kitchen_spool_platform.dart';
import 'pos_kitchen_spool_runtime.dart';
import 'pos_secure_kitchen_mode_cache.dart';

/// KITCHEN-MODE-001C2B/001C2C — the NATIVE (`dart.library.io`) composition
/// branch.
///
/// This is the ONLY file that hands the lifecycle a real
/// [PosKitchenSpoolRuntime]; it is linked exclusively through the
/// conditional import in `pos_kitchen_spool_composition.dart`, so
/// drift/sqlite3 FFI, dart:io, and path_provider never enter the Flutter
/// web compile graph. Self-assembles from existing providers; inert in demo
/// mode and whenever the real transport is absent. PASS 2 additions: the
/// full worker dependency set (renderer, kitchen-safe transports, THE
/// shared receipt/kitchen send gate), report-derived capability updates,
/// and REAL disposal — the provider watches the device context so any
/// pairing/scope change rebuilds it, and `ref.onDispose` closes the
/// dedicated database and stops an in-flight worker before its next send.
PosKitchenSpoolLifecycleHooks? buildPosKitchenSpoolRuntime(Ref ref) {
  const platform = PosKitchenSpoolPlatform();
  if (!platform.supportsSecureSpool) return null;
  if (ref.watch(runtimeConfigProvider).isDemoMode) return null;
  final transport = ref.watch(posAuthTransportProvider);
  if (transport == null) return null;
  // A pairing/scope transition is a DIFFERENT world: rebuild (and thereby
  // dispose) the runtime whenever the device context changes.
  ref.watch(posDeviceContextProvider);
  final secretStore = FlutterSecureDeviceSessionStoreProvider.of();
  final connector = ref.watch(bluetoothPrinterConnectorProvider);
  final runtime = PosKitchenSpoolRuntime(
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
    // KITCHEN-MODE-001C2C: the worker dependency set. The renderer's frame
    // labels follow the device locale (ar/he/en; payload content is already
    // the operator's language); the rasterizer is the SAME app-injected
    // seam the receipt path uses; both transports are the kitchen-safe
    // single-attempt seams; the gate is THE shared receipt/kitchen
    // instance. All of it stays unreachable in production until a trusted
    // printer-only revision exists (D1 + server readiness gate).
    renderer: KitchenTicketRenderer(
      labels: KitchenTicketLabels.forLanguageCode(
        ui.PlatformDispatcher.instance.locale.languageCode,
      ),
      rasterizer: ref.watch(nativePrintRasterizerProvider),
    ),
    networkSend: ({required host, required port, required bytes}) =>
        sendKitchenBytesOverTcp(
          host: host,
          port: port,
          bytes: bytes,
          timeout: kPosNativePrintTimeout,
        ),
    bluetoothSend: ({required address, required bytes}) async =>
        connector is ChannelBluetoothConnector
        ? classifyKitchenBluetoothAttempt(
            await connector.sendOnceForKitchen(address: address, bytes: bytes),
          )
        : const KitchenTransportOutcome(
            KitchenTransportOutcomeKind.unsupported,
            'bluetooth_connector_unsupported',
          ),
    sendGate: ref.watch(posPrinterDestinationSendGateProvider),
    modeCache: PosSecureKitchenModeCache(platform: platform),
  );
  // REAL disposal: logout/unpair/scope change (the device-context watch) or
  // provider teardown closes the dedicated DB and stops an in-flight worker
  // before its next send. Rows and key are preserved.
  ref.onDispose(runtime.dispose);
  return _CapabilityReportingHooks(runtime, (capability) {
    try {
      ref.read(posKitchenSpoolCapabilityProvider.notifier).state = capability;
    } catch (_) {
      // The provider container may already be disposed mid-run teardown.
    }
  });
}

/// Wraps the runtime so every lifecycle run's typed report also updates the
/// web-safe operational capability provider (safe scalars only).
final class _CapabilityReportingHooks implements PosKitchenSpoolLifecycleHooks {
  _CapabilityReportingHooks(this._runtime, this._update);

  final PosKitchenSpoolRuntime _runtime;
  final void Function(PosKitchenSpoolCapability) _update;

  @override
  Future<Object?> onStartup() => _report(_runtime.onStartup);

  @override
  Future<Object?> onResume() => _report(_runtime.onResume);

  Future<Object?> _report(
    Future<PosKitchenSpoolRunReport> Function() run,
  ) async {
    final report = await run();
    _update(deriveKitchenSpoolCapability(report));
    return report;
  }
}

/// Derives the typed operational capability from a run report — priority
/// order: terminal conflict > review-required > blocked > transport down >
/// waiting retry > idle; blocked/failed runs map to their typed causes.
PosKitchenSpoolCapability deriveKitchenSpoolCapability(
  PosKitchenSpoolRunReport report,
) => switch (report) {
  KitchenSpoolRunWorked(:final worker, :final recoveredStale, :final drain) =>
    worker.ackTerminal > 0
        ? PosKitchenSpoolCapability.terminalOwnershipConflict
        : (worker.possiblyPrinted > 0 || recoveredStale > 0)
        ? PosKitchenSpoolCapability.possiblyPrintedReviewRequired
        : (worker.blockedConfiguration > 0 ||
              drain.rowsBlockedConfiguration > 0)
        ? PosKitchenSpoolCapability.blockedConfiguration
        : worker.transportUnavailable > 0
        ? PosKitchenSpoolCapability.transportUnavailable
        : worker.failedRetryable > 0
        ? PosKitchenSpoolCapability.waitingRetry
        : PosKitchenSpoolCapability.idle,
  KitchenSpoolRunDrained() ||
  KitchenSpoolRunReconciled() ||
  KitchenSpoolRunSkipped() => PosKitchenSpoolCapability.idle,
  KitchenSpoolRunBlocked(:final detail) => switch (detail) {
    'unexpected_failure' => PosKitchenSpoolCapability.unexpectedFailure,
    'kitchen_destination_unresolvable' =>
      PosKitchenSpoolCapability.destinationUnsupported,
    'documents_directory_unavailable' ||
    'spool_directory_create_failed' ||
    'spool_database_open_failed' =>
      PosKitchenSpoolCapability.databaseUnavailable,
    _ =>
      detail.startsWith('KitchenSpoolKey')
          ? PosKitchenSpoolCapability.keyUnavailable
          : PosKitchenSpoolCapability.unexpectedFailure,
  },
};

/// Small indirection so tests can see exactly which secret store the
/// composition uses (the SAME Keystore-backed store as device pairing).
abstract final class FlutterSecureDeviceSessionStoreProvider {
  static DeviceSessionSecretStore of() => FlutterSecureDeviceSessionStore();
}
