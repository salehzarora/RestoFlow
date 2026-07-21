@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/pos_package_root.dart';

/// KITCHEN-MODE-001C2B — runtime source-boundary proof (evolved from the
/// 001C2A dormancy scan).
///
/// The spool is now COMPOSED, but only through the sanctioned boundary:
/// every spool reference lives in `lib/src/spool/`, and the ONE production
/// caller is the `PosSyncLifecycle` startup/resume hook (LOCKED D4 — no
/// timer, no worker). Readiness reporting, the workflow-mode setter, the
/// member inspection RPC, print transport, and browser storage remain
/// prohibited everywhere. These are STRING-LEVEL code scans, so any wiring
/// beyond the sanctioned boundary fails this test until its own reviewed
/// phase.
void main() {
  late final List<File> libSources;
  late final String mainSource;

  setUpAll(() {
    // CI-PORTABLE: CI runs `flutter test apps/pos` from the REPOSITORY ROOT
    // while local runs start inside the app — resolve the app root instead
    // of assuming the working directory.
    final appRoot = locatePosPackageRoot();
    libSources =
        Directory(p.join(appRoot.path, 'lib'))
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path)); // deterministic order
    expect(libSources, isNotEmpty);
    mainSource = File(
      p.join(appRoot.path, 'lib', 'main.dart'),
    ).readAsStringSync();
  });

  String allSourcesExcept(bool Function(String path) excluded) {
    final buffer = StringBuffer();
    for (final f in libSources) {
      final normalized = f.path.replaceAll('\\', '/');
      if (excluded(normalized)) continue;
      // CLEANUP 7E: scan CODE ONLY — comment lines are stripped so a
      // doc-comment MENTION (e.g. outbox_repository's LocalDatabase note)
      // does not mask the detector, while any real import/alias/reference
      // (which must live in code) still trips it.
      for (final line in f.readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//')) continue;
        buffer.writeln(line);
      }
    }
    return buffer.toString();
  }

  test(
    'main.dart (the production composition root) never touches the spool',
    () {
      expect(mainSource, isNot(contains('kitchen_spool')));
      expect(mainSource, isNot(contains('KitchenSpool')));
      expect(mainSource, isNot(contains('restoflow_data_local')));
      expect(mainSource, isNot(contains('LocalDatabase')));
      expect(mainSource, isNot(contains('ProtectedLocalDatabaseFactory')));
    },
  );

  test('spool references live ONLY in lib/src/spool + the sanctioned '
      'PosSyncLifecycle hook (D4)', () {
    final outside = allSourcesExcept(
      (p) =>
          p.contains('lib/src/spool/') ||
          p.endsWith('lib/src/widgets/pos_sync_lifecycle.dart'),
    );
    // Identifier set hardened against alias/barrel/indirect construction
    // bypasses — an aliased import still carries the package path string,
    // and ANY reference to these types/members must name them.
    for (final needle in [
      'FlutterSecureKitchenSpoolKeyStore',
      'PosKitchenSpoolPlatform',
      'KitchenSpoolKeyManager',
      'KitchenSpoolCipher',
      'AesGcmKitchenSpoolCipher',
      'DriftKitchenSpoolStore',
      'KitchenSpoolStore',
      'KitchenSpoolAad',
      'KitchenSpoolLocalPayload',
      'KitchenSpoolDatabase',
      'kitchen_spool',
      'KitchenSpool',
      'provisionKey',
      'provisionPersistentKey',
      'LocalDatabase',
      'ProtectedLocalDatabaseFactory',
    ]) {
      expect(
        outside,
        isNot(contains(needle)),
        reason: '"$needle" must not appear outside the sanctioned boundary',
      );
    }
  });

  test('the sanctioned lifecycle hook may reference ONLY the runtime provider '
      '(never stores, ciphers, keys, or databases directly)', () {
    final hook = allSourcesExcept(
      (p) => !p.endsWith('lib/src/widgets/pos_sync_lifecycle.dart'),
    );
    expect(hook, contains('posKitchenSpoolRuntimeProvider'));
    // 001C3A: the readiness heartbeat provider is the SECOND sanctioned
    // reference (startup/resume/paused delegation only).
    expect(hook, contains('posKitchenReadinessHeartbeatProvider'));
    for (final needle in [
      'DriftKitchenSpoolStore',
      'KitchenSpoolKeyManager',
      'KitchenSpoolCipher',
      'KitchenSpoolDatabase',
      'FlutterSecureKitchenSpoolKeyStore',
      'provisionKey',
    ]) {
      expect(hook, isNot(contains(needle)));
    }
  });

  test('restoflow_data_local imports are CONFINED to lib/src/spool', () {
    final outside = allSourcesExcept((p) => p.contains('lib/src/spool/'));
    expect(outside, isNot(contains('package:restoflow_data_local')));
  });

  test('001C3A EVOLUTION: raw kitchen RPC strings never appear in POS '
      'sources (readiness is now SANCTIONED but only through the typed '
      'feature_auth repository); mode setters stay fully banned', () {
    final all = allSourcesExcept((_) => false);
    for (final rpc in [
      // Sanctioned CLIENTS exist in feature_auth — the raw strings still
      // must never appear here (POS talks only through typed repositories).
      'report_kitchen_printer_readiness',
      'pull_kitchen_print_dispatches',
      'acknowledge_kitchen_print_dispatch',
      // Member-context RPCs have NO POS caller of any kind.
      'get_kitchen_workflow_transition_readiness',
      'list_kitchen_print_dispatches',
      // NO workflow-mode writer exists anywhere (001C3B is unshipped, and
      // its eventual activation is gated even later).
      'set_kitchen_workflow_mode',
      'set_branch_kitchen_workflow_mode',
    ]) {
      expect(all, isNot(contains(rpc)), reason: '$rpc must have NO caller');
    }
  });

  test('001C3A: the readiness heartbeat is the ONE sanctioned spool timer '
      'and is READINESS-ONLY (no worker, drain, transport, pull, or key '
      'provisioning in its dependency closure)', () {
    final readinessFiles = allSourcesExcept(
      (p) =>
          !p.endsWith('lib/src/spool/kitchen_readiness_coordinator.dart') &&
          !p.endsWith('lib/src/spool/kitchen_readiness_evidence.dart') &&
          !p.endsWith('lib/src/spool/kitchen_spool_readiness_probe.dart'),
    );
    expect(readinessFiles, isNotEmpty);
    for (final needle in [
      'KitchenPrintWorker',
      'KitchenDispatchDrainCoordinator',
      'SupabaseKitchenDispatchPullRepository',
      'sendKitchenBytesOverTcp',
      'sendOnceForKitchen',
      'classifyKitchenBluetoothAttempt',
      'provisionKey',
      'insertImportedJob',
      'markPrinting',
      'claimRunnable',
    ]) {
      expect(
        readinessFiles,
        isNot(contains(needle)),
        reason: '"$needle" must never enter the readiness-only closure',
      );
    }
    // Timers stay confined to the readiness coordinator: no OTHER spool
    // file may create one (the worker/runtime remain lifecycle-driven, D4).
    final otherSpool = allSourcesExcept(
      (p) =>
          !p.contains('lib/src/spool/') ||
          p.endsWith('lib/src/spool/kitchen_readiness_coordinator.dart'),
    );
    expect(otherSpool, isNot(contains('Timer.periodic')));
    expect(otherSpool, isNot(matches(RegExp(r'(?<![A-Za-z0-9_])Timer\('))));
  });

  test('the spool layer never calls print transport (no worker in 001C2B)', () {
    final spool = allSourcesExcept((p) => !p.contains('lib/src/spool/'));
    for (final needle in [
      'NativePrintTarget',
      'PrintBridge',
      'printBridge',
      'sendToPrinter',
      'MethodChannel',
    ]) {
      expect(spool, isNot(contains(needle)));
    }
  });

  test('the spool layer never touches SharedPreferences/localStorage', () {
    final spool = allSourcesExcept((p) => !p.contains('lib/src/spool/'));
    expect(spool, isNotEmpty);
    // Code-level usage patterns (doc comments may NAME the prohibition).
    expect(spool, isNot(contains('package:shared_preferences')));
    expect(spool, isNot(contains('SharedPreferences.')));
    expect(spool, isNot(contains('getInstance(')));
    expect(spool, isNot(contains('localStorage')));
    expect(spool, isNot(contains('window.')));
  });

  test('the spool layer never logs or prints (no secret leak channel)', () {
    final spool = allSourcesExcept((p) => !p.contains('lib/src/spool/'));
    // Word-boundary matches: identifiers like `sessionFingerprint(` or
    // `catalog(` must not mask-trip the bare print()/log() detectors.
    expect(spool, isNot(matches(RegExp(r'(?<![A-Za-z0-9_])print\('))));
    expect(spool, isNot(contains('debugPrint')));
    expect(spool, isNot(matches(RegExp(r'(?<![A-Za-z0-9_.])log\('))));
  });
}
