import 'dart:async' show unawaited;
import 'dart:ui' as ui show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory;
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart'
    show KitchenSpoolDatabaseFactory, KitchenSpoolKeyManager;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show
        FlutterSecureDeviceSessionStore,
        SupabaseDeviceKitchenModeRepository,
        SupabaseDevicePrinterAssignmentsRepository,
        SupabaseKitchenDispatchAckRepository,
        SupabaseKitchenDispatchPullRepository,
        SupabaseKitchenPosStatusRepository,
        SupabaseKitchenReadinessRepository,
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

import '../data/customer_phone.dart' show normalizeCustomerPhone;
import '../data/ids.dart' show clientIdGeneratorProvider;
import '../data/kitchen_mode_readiness.dart'
    show PosKitchenModeScopeKey, posKitchenModeReadinessProvider;
import 'kitchen_mode_cache_seed.dart' show readVerifiedCachedMode;
import '../print/native_print_bridges.dart'
    show kPosNativePrintTimeout, posPrinterDestinationSendGateProvider;
import '../state/pos_bluetooth_printer_config.dart'
    show posKitchenBluetoothPrinterConfigProvider;
import '../state/pos_device_context.dart' show posDeviceContextProvider;
import '../state/outbox_controller.dart' show outboxRepositoryProvider;
import '../state/recent_orders_controller.dart'
    show posRecentOrdersControllerProvider;
import '../state/pos_network_printer_config.dart'
    show posKitchenNetworkPrinterConfigProvider;
import '../state/pos_printer_transport.dart'
    show posKitchenSelectedPrinterTransportProvider;
import '../state/pos_session.dart' show posAuthTransportProvider;
import 'flutter_secure_kitchen_spool_key_store.dart';
import 'kitchen_destination_resolver.dart';
import 'kitchen_readiness_coordinator.dart';
import 'kitchen_readiness_evidence.dart';
import 'kitchen_spool_readiness_probe.dart';
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
    // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 2, Codex HIGH): resolve the
    // order's phone from LOCAL authoritative sources (never the redacted server
    // payload). The FULLY-SCOPED [key] is built by the import coordinator from THIS
    // run's org/restaurant/branch/device import scope + the dispatch order id, so
    // neither source can cross scopes. Lookup order:
    //   1. the DURABLE `order.submit` outbox op — persisted BEFORE the network push,
    //      matched on the full scope + order identity and validated through the ONE
    //      shared normalizer (a malformed durable value yields null);
    //   2. recent/server-backed order data for the SAME order id — the recent-orders
    //      controller is itself scope-derived, and the value is re-validated here.
    // Best-effort: any miss/failure/invalid value yields null (name-only).
    resolveCustomerPhone: (key) async {
      final fromOutbox = await ref
          .read(outboxRepositoryProvider)
          .findOrderSubmitCustomerPhone(key);
      if (fromOutbox != null && fromOutbox.isNotEmpty) return fromOutbox;
      for (final o in ref.read(posRecentOrdersControllerProvider)) {
        if (o.orderId == key.orderId) {
          return normalizeCustomerPhone(o.order?.customerPhone);
        }
      }
      return null;
    },
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

/// KITCHEN-MODE-001C3A — the NATIVE readiness-heartbeat composition.
///
/// READINESS-ONLY by construction: its dependency set is the mode getter,
/// the pure printer-evidence derivation, the NON-MUTATING spool probe, the
/// readiness repository, and the mode-cache invalidator — it can NOT reach
/// the print worker, the dispatch drain, any transport send, key
/// provisioning, or database creation. The device-context watch rebuilds
/// (and thereby disposes) the heartbeat on any pairing/scope change;
/// `ref.onDispose` stops the timer permanently. Immediate re-reports are
/// wired to printer-configuration changes and to spool capability changes
/// (each lifecycle run's derived capability), on top of the 5-minute
/// foreground cadence and the startup/resume/paused hooks.
PosKitchenReadinessLifecycle? buildPosKitchenReadinessHeartbeat(Ref ref) {
  const platform = PosKitchenSpoolPlatform();
  if (!platform.supportsSecureSpool) return null;
  if (ref.watch(runtimeConfigProvider).isDemoMode) return null;
  final transport = ref.watch(posAuthTransportProvider);
  if (transport == null) return null;
  // Scope transition = a DIFFERENT world: rebuild for the new scope.
  ref.watch(posDeviceContextProvider);
  final secretStore = FlutterSecureDeviceSessionStoreProvider.of();
  final modeRepository = SupabaseDeviceKitchenModeRepository(
    transport: transport,
    secretStore: secretStore,
  );
  final readinessRepository = SupabaseKitchenReadinessRepository(
    transport: transport,
    secretStore: secretStore,
  );
  final statusRepository = SupabaseKitchenPosStatusRepository(
    transport: transport,
    secretStore: secretStore,
  );
  final modeCache = PosSecureKitchenModeCache(platform: platform);
  final probe = KitchenSpoolReadinessProbe(
    platform: platform,
    databaseFactoryBuilder: () => KitchenSpoolDatabaseFactory(
      documentsDirectoryProvider: getApplicationDocumentsDirectory,
    ),
    keyManagerBuilder: () => KitchenSpoolKeyManager(
      FlutterSecureKitchenSpoolKeyStore(platform: platform),
    ),
  );
  // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 1): bind the readiness to THIS
  // scope for a fresh generation. This heartbeat provider rebuilds (disposing the
  // old one) whenever the device context changes, so a restaurant/branch/device
  // switch bindsScope anew — invalidating the previous verified mode and bumping
  // the generation so any delayed cache/fetch/heartbeat result from the old scope
  // is dropped by the binding rather than publishing across scopes.
  final ctxAtBind = ref.read(posDeviceContextProvider);
  final binding = ref
      .read(posKitchenModeReadinessProvider.notifier)
      .bindScope(PosKitchenModeScopeKey.fromContext(ctxAtBind));
  final heartbeat = KitchenReadinessHeartbeat(
    deviceContext: () => ref.read(posDeviceContextProvider),
    fetchMode: modeRepository.fetchMode,
    // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: publish the verified mode so a
    // printer_only branch's submits emit direct_print and its dine-in orders
    // close. Fail-closed: a non-trusted result blocks submission (never guessed
    // KDS); a definitive fetch failure marks the readiness unavailable (retryable).
    // Scope-bound: the binding drops a result that arrives after a scope change.
    onMode: binding.publish,
    onModeUnavailable: binding.markUnavailable,
    printerEvidence: () async {
      final assignments = await SupabaseDevicePrinterAssignmentsRepository(
        transport: transport,
        secretStore: secretStore,
      ).load();
      final snapshot = assignments.fold<DevicePrinterAssignments?>(
        (value) => value,
        (_) => null,
      );
      if (snapshot == null) {
        // Could not DETERMINE the assignment state — skip this report
        // rather than filing evidence built on a guess.
        return const BlockedKitchenPrinterEvidence('assignments_unavailable');
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
      return buildKitchenReadinessPrinterEvidence(
        selectedTransport: selected,
        networkConfig: network,
        bluetoothConfig: bluetooth,
        assignments: snapshot,
      );
    },
    probeSpool: ({required deviceId, required branchId}) =>
        probe.probe(deviceId: deviceId, branchId: branchId),
    sendStatus: statusRepository.report,
    sendReport: readinessRepository.report,
    invalidateModeCache: modeCache.invalidate,
  );
  // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap A): expose an immediate re-verify
  // to the cart's retry affordance WITHOUT the UI importing this spool boundary
  // (the runtime source-boundary proof forbids any spool reference outside
  // `lib/src/spool`). Single-flight inside the coordinator absorbs bursts.
  // Scope-bound (Finding 1): a retry re-verifies THIS scope only.
  binding.bindResolver(() => heartbeat.requestImmediate('user_retry'));
  // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap A): OFFLINE readiness seed. A fresh
  // trusted secure-cached mode resolves submission IMMEDIATELY (before the network
  // heartbeat), so a returning cashier's printer_only branch emits direct_print
  // even offline. Fire-and-forget: a miss/failure leaves the readiness Loading and
  // the heartbeat resolves it. Never a downgrade — publish only maps a TRUSTED
  // cached mode to Resolved. Read against the scope captured AT BIND; the binding
  // drops the result if the scope changed while the cache read was in flight
  // (Finding 1: a stale cross-scope cache seed can never apply).
  unawaited(() async {
    final cached = await readVerifiedCachedMode(
      cache: modeCache,
      secretStore: secretStore,
      context: ctxAtBind,
    );
    if (cached != null) {
      binding.publish(cached);
    }
  }());
  // Immediate evidence-change triggers (fire-and-forget; single-flight
  // inside the coordinator absorbs bursts).
  ref.listen(posKitchenSelectedPrinterTransportProvider, (_, _) {
    heartbeat.requestImmediate('printer_config_changed');
  });
  ref.listen(posKitchenNetworkPrinterConfigProvider, (_, _) {
    heartbeat.requestImmediate('printer_config_changed');
  });
  ref.listen(posKitchenBluetoothPrinterConfigProvider, (_, _) {
    heartbeat.requestImmediate('printer_config_changed');
  });
  ref.listen(posKitchenSpoolCapabilityProvider, (previous, next) {
    if (previous != next) heartbeat.requestImmediate('spool_state_changed');
  });
  ref.onDispose(() {
    // Finding 1 (disposal safety): release this binding BEFORE the heartbeat is
    // gone. Unbinding bumps the readiness generation, so any of this scope's
    // in-flight cache/fetch/heartbeat results can no longer publish — even before
    // the next scope's heartbeat installs its own binding.
    binding.unbind();
    heartbeat.dispose();
  });
  return heartbeat;
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
///
/// REVIEW NOTE F1: a terminal ownership verdict can surface OUTSIDE the
/// worker's own acknowledgements — from the run-level pre/post pending-ack
/// flushes (`report.terminal`), including reconciled/drained runs with no
/// worker at all. ANY terminal count > 0 maps to
/// [PosKitchenSpoolCapability.terminalOwnershipConflict] at the highest
/// priority; a run that saw one can never read as idle/success.
PosKitchenSpoolCapability deriveKitchenSpoolCapability(
  PosKitchenSpoolRunReport report,
) => switch (report) {
  KitchenSpoolRunWorked(
    :final worker,
    :final recoveredStale,
    :final drain,
    :final terminal,
  ) =>
    (worker.ackTerminal > 0 ||
            terminal > 0 ||
            drain.acknowledgementsTerminal > 0)
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
  KitchenSpoolRunDrained(:final terminal, :final drain) =>
    (terminal > 0 || drain.acknowledgementsTerminal > 0)
        ? PosKitchenSpoolCapability.terminalOwnershipConflict
        : PosKitchenSpoolCapability.idle,
  KitchenSpoolRunReconciled(:final terminal) =>
    terminal > 0
        ? PosKitchenSpoolCapability.terminalOwnershipConflict
        : PosKitchenSpoolCapability.idle,
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
