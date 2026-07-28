// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap A) — the kitchen-mode SUBMISSION
// READINESS: a NEW order must never be submitted with a GUESSED KDS dispatch
// before the verified/cached mode has resolved (which, on a real printer_only
// branch, would strand the order). Synthetic values only.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext, DeviceSessionCredential, DeviceSessionSecretStore;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart';
import 'package:restoflow_pos/src/data/order_dispatch.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/spool/kitchen_mode_cache_seed.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_platform.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_runtime.dart'
    show sessionFingerprint;
import 'package:restoflow_pos/src/spool/pos_secure_kitchen_mode_cache.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';

class _FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> values = {};
  @override
  Future<String?> read({
    required String key,
    iOptions,
    aOptions,
    lOptions,
    webOptions,
    mOptions,
    wOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    iOptions,
    aOptions,
    lOptions,
    webOptions,
    mOptions,
    wOptions,
  }) async => values[key] = value!;
  @override
  Future<void> delete({
    required String key,
    iOptions,
    aOptions,
    lOptions,
    webOptions,
    mOptions,
    wOptions,
  }) async => values.remove(key);
}

class _FakeSecretStore extends Fake implements DeviceSessionSecretStore {
  _FakeSecretStore(this._cred);
  final DeviceSessionCredential? _cred;
  @override
  Future<DeviceSessionCredential?> read() async => _cred;
}

void main() {
  final at = DateTime.utc(2026, 7, 28, 12);
  KitchenModePrinterOnlyWithRevision printerOnly() =>
      KitchenModePrinterOnlyWithRevision(revision: 4, verifiedAt: at);
  KitchenModeVerifiedKds kds() =>
      KitchenModeVerifiedKds(verifiedAt: at, revision: 4);

  // Finding 1: distinct scopes (branch A, branch B, a different device in A).
  const scopeA = PosKitchenModeScopeKey(
    organizationId: 'org',
    restaurantId: 'rest',
    branchId: 'branch-A',
    deviceId: 'dev-1',
  );
  const scopeB = PosKitchenModeScopeKey(
    organizationId: 'org',
    restaurantId: 'rest',
    branchId: 'branch-B',
    deviceId: 'dev-1',
  );
  const scopeADeviceB = PosKitchenModeScopeKey(
    organizationId: 'org',
    restaurantId: 'rest',
    branchId: 'branch-A',
    deviceId: 'dev-2',
  );

  group('resolvePosSubmissionDecision', () {
    test('resolved printer_only -> ready + direct_print', () {
      final d = resolvePosSubmissionDecision(
        KitchenModeReadinessResolved(printerOnly()),
      );
      expect(d.canSubmit, isTrue);
      expect(d.dispatchMode, OrderDispatchMode.directPrint);
    });
    test('resolved kds -> ready + kds', () {
      final d = resolvePosSubmissionDecision(
        KitchenModeReadinessResolved(kds()),
      );
      expect(d.canSubmit, isTrue);
      expect(d.dispatchMode, OrderDispatchMode.kds);
    });
    test('loading -> blocked (kitchenModeLoading)', () {
      final d = resolvePosSubmissionDecision(
        const KitchenModeReadinessLoading(),
      );
      expect(d.canSubmit, isFalse);
      expect(d.blockReason, PosSubmissionBlockReason.kitchenModeLoading);
    });
    test('unavailable -> blocked (kitchenModeUnavailable)', () {
      final d = resolvePosSubmissionDecision(
        const KitchenModeReadinessUnavailable(),
      );
      expect(d.canSubmit, isFalse);
      expect(d.blockReason, PosSubmissionBlockReason.kitchenModeUnavailable);
    });
  });

  group('PosKitchenModeReadinessController', () {
    ProviderContainer make({bool demo = true}) => ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: demo),
        ),
      ],
    );

    test('DEMO resolves to kds immediately (Send never blocks)', () {
      final c = make(demo: true);
      addTearDown(c.dispose);
      final r = c.read(posKitchenModeReadinessProvider);
      expect(r, isA<KitchenModeReadinessResolved>());
      expect(
        (r as KitchenModeReadinessResolved).mode,
        isA<KitchenModeVerifiedKds>(),
      );
    });

    test('REAL starts Loading (blocked) until verified', () {
      final c = make(demo: false);
      addTearDown(c.dispose);
      expect(
        c.read(posKitchenModeReadinessProvider),
        isA<KitchenModeReadinessLoading>(),
      );
    });

    PosKitchenModeReadiness stateOf(ProviderContainer c) =>
        c.read(posKitchenModeReadinessProvider);

    test(
      'publish maps trusted modes to Resolved; non-trusted to Unavailable',
      () {
        final c = make(demo: false);
        addTearDown(c.dispose);
        final n = c.read(posKitchenModeReadinessProvider.notifier);
        n.bindScope(scopeA).publish(printerOnly());
        expect(stateOf(c), isA<KitchenModeReadinessResolved>());
        n.reset();
        n.bindScope(scopeA).publish(const KitchenModeRevisionUnavailable());
        expect(stateOf(c), isA<KitchenModeReadinessUnavailable>());
        n.reset();
        n.bindScope(scopeA).publish(const KitchenModeInvalidSession());
        expect(stateOf(c), isA<KitchenModeReadinessUnavailable>());
      },
    );

    test('a non-trusted result never DOWNGRADES an already resolved mode', () {
      final c = make(demo: false);
      addTearDown(c.dispose);
      final b = c
          .read(posKitchenModeReadinessProvider.notifier)
          .bindScope(scopeA);
      b.publish(printerOnly());
      b.publish(const KitchenModeTransientFailure()); // a blip
      final r = stateOf(c);
      expect(r, isA<KitchenModeReadinessResolved>());
      expect(
        (r as KitchenModeReadinessResolved).mode,
        isA<KitchenModePrinterOnlyWithRevision>(),
      );
      expect(r.scope, scopeA);
    });

    test('markUnavailable only acts while Loading', () {
      final c = make(demo: false);
      addTearDown(c.dispose);
      c
          .read(posKitchenModeReadinessProvider.notifier)
          .bindScope(scopeA)
          .markUnavailable();
      expect(stateOf(c), isA<KitchenModeReadinessUnavailable>());
    });

    test('requestResolution reopens to Loading and calls the bound resolver; '
        'a no-op when nothing is bound (web/demo/unpaired)', () {
      final c = make(demo: false);
      addTearDown(c.dispose);
      final n = c.read(posKitchenModeReadinessProvider.notifier);
      // Nothing bound yet: a retry must be a safe no-op (never clears the block).
      n.bindScope(scopeA).markUnavailable();
      n.requestResolution();
      expect(stateOf(c), isA<KitchenModeReadinessUnavailable>());
      // The native composition binds the heartbeat's re-verify entrypoint; a
      // retry then reopens the gate to Loading and asks for a fresh check.
      var calls = 0;
      final b = n.bindScope(scopeA)..bindResolver(() => calls++);
      b.markUnavailable();
      n.requestResolution();
      expect(calls, 1);
      expect(stateOf(c), isA<KitchenModeReadinessLoading>());
      // Unbinding (scope change / dispose) restores the no-op behavior.
      b.unbind();
      expect(stateOf(c), isA<KitchenModeReadinessLoading>());
      n.requestResolution();
      expect(calls, 1);
    });
  });

  // Finding 1: no delayed cache/fetch/heartbeat/retry result from an old
  // restaurant/branch/device scope may publish into the current readiness.
  group('scope-bound readiness (Finding 1)', () {
    ProviderContainer real() => ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
      ],
    );
    PosKitchenModeReadiness stateOf(ProviderContainer c) =>
        c.read(posKitchenModeReadinessProvider);

    test('delayed printer_only fetch for A completes after switching to B -> B '
        'stays Loading; NO direct_print leak', () {
      final c = real();
      addTearDown(c.dispose);
      final n = c.read(posKitchenModeReadinessProvider.notifier);
      final a = n.bindScope(scopeA); // heartbeat A
      a.unbind(); // scope change: A's heartbeat disposed
      n.bindScope(scopeB); // heartbeat B installs, fresh Loading for B
      a.publish(printerOnly()); // A's delayed fetch lands LATE
      final s = stateOf(c);
      expect(s, isA<KitchenModeReadinessLoading>());
      expect(s.scope, scopeB);
    });

    test('delayed KDS fetch for A completes after switching to printer_only '
        'branch B -> no stale KDS leak', () {
      final c = real();
      addTearDown(c.dispose);
      final n = c.read(posKitchenModeReadinessProvider.notifier);
      final a = n.bindScope(scopeA);
      a.unbind();
      final b = n.bindScope(scopeB);
      a.publish(kds()); // A's delayed KDS result
      expect(stateOf(c), isA<KitchenModeReadinessLoading>());
      // B then verifies printer_only for ITSELF -> direct_print, never the stale KDS.
      b.publish(printerOnly());
      final s = stateOf(c) as KitchenModeReadinessResolved;
      expect(s.mode, isA<KitchenModePrinterOnlyWithRevision>());
      expect(s.scope, scopeB);
    });

    test('a delayed cache seed after a scope change is ignored', () {
      final c = real();
      addTearDown(c.dispose);
      final n = c.read(posKitchenModeReadinessProvider.notifier);
      final a = n.bindScope(scopeA);
      final b = n.bindScope(
        scopeB,
      ); // same as a scope switch (no unbind needed)
      a.publish(kds()); // stale cache seed for A
      expect(stateOf(c), isA<KitchenModeReadinessLoading>());
      b.publish(kds());
      expect((stateOf(c) as KitchenModeReadinessResolved).scope, scopeB);
    });

    test('a heartbeat result after disposal (unbind) is ignored', () {
      final c = real();
      addTearDown(c.dispose);
      final n = c.read(posKitchenModeReadinessProvider.notifier);
      final a = n.bindScope(scopeA);
      a.unbind(); // heartbeat A disposed, no new bind yet
      expect(a.isCurrent, isFalse);
      a.publish(printerOnly());
      a.markUnavailable();
      expect(stateOf(c), isA<KitchenModeReadinessLoading>());
    });

    test('an OLD retry resolver cannot publish into a NEW scope', () {
      final c = real();
      addTearDown(c.dispose);
      final n = c.read(posKitchenModeReadinessProvider.notifier);
      var aCalls = 0;
      final a = n.bindScope(scopeA)..bindResolver(() => aCalls++);
      final b = n.bindScope(scopeB); // scope switch drops A's resolver
      n.requestResolution(); // B has no resolver yet -> no-op, A's is gone
      expect(aCalls, 0);
      // A's stale resolver, if somehow invoked, cannot resolve B either.
      a.publish(printerOnly());
      expect(stateOf(c), isA<KitchenModeReadinessLoading>());
      var bCalls = 0;
      b.bindResolver(() => bCalls++);
      n.requestResolution();
      expect(bCalls, 1);
    });

    test(
      'a device change inside the same restaurant invalidates readiness',
      () {
        final c = real();
        addTearDown(c.dispose);
        final n = c.read(posKitchenModeReadinessProvider.notifier);
        n.bindScope(scopeA).publish(printerOnly());
        expect(stateOf(c), isA<KitchenModeReadinessResolved>());
        n.bindScope(scopeADeviceB); // same branch, different device
        final s = stateOf(c);
        expect(s, isA<KitchenModeReadinessLoading>());
        expect(s.scope, scopeADeviceB);
      },
    );

    test('a branch change invalidates readiness', () {
      final c = real();
      addTearDown(c.dispose);
      final n = c.read(posKitchenModeReadinessProvider.notifier);
      n.bindScope(scopeA).publish(kds());
      expect(stateOf(c), isA<KitchenModeReadinessResolved>());
      n.bindScope(scopeB);
      expect(stateOf(c), isA<KitchenModeReadinessLoading>());
    });

    test('a valid cached mode works ONLY for its exact scope', () {
      final c = real();
      addTearDown(c.dispose);
      final n = c.read(posKitchenModeReadinessProvider.notifier);
      final a = n.bindScope(scopeA);
      // Rebinding to B before A's cache lands: A's cache is dropped.
      final b = n.bindScope(scopeB);
      a.publish(printerOnly());
      expect(stateOf(c), isA<KitchenModeReadinessLoading>());
      // The same cached mode, published for B's OWN binding, resolves B.
      b.publish(printerOnly());
      expect((stateOf(c) as KitchenModeReadinessResolved).scope, scopeB);
    });

    test(
      'a transient failure preserves a verified mode ONLY for the same scope',
      () {
        final c = real();
        addTearDown(c.dispose);
        final n = c.read(posKitchenModeReadinessProvider.notifier);
        final a = n.bindScope(scopeA)..publish(kds());
        a.publish(const KitchenModeTransientFailure()); // same-scope blip
        expect(stateOf(c), isA<KitchenModeReadinessResolved>());
        // A scope change does NOT keep A's verified mode alive for B.
        n.bindScope(scopeB);
        expect(stateOf(c), isA<KitchenModeReadinessLoading>());
      },
    );

    test('repeated bind/unbind never leaks a resolver across scopes', () {
      final c = real();
      addTearDown(c.dispose);
      final n = c.read(posKitchenModeReadinessProvider.notifier);
      var latest = 0;
      for (var i = 0; i < 5; i++) {
        final b = n.bindScope(i.isEven ? scopeA : scopeB)
          ..bindResolver(() => latest = i);
        b.unbind();
      }
      // Every binding was unbound: no stale resolver survives.
      n.requestResolution();
      expect(latest, 0);
      // Only the freshly-bound resolver fires.
      final live = n.bindScope(scopeA)..bindResolver(() => latest = 99);
      n.requestResolution();
      expect(latest, 99);
      live.unbind();
    });

    test('a disposed controller accepts no publish (binding not current)', () {
      final c = real();
      final n = c.read(posKitchenModeReadinessProvider.notifier);
      final a = n.bindScope(scopeA);
      c.dispose(); // whole controller torn down
      expect(a.isCurrent, isFalse);
      // No throw, no state mutation attempted on the disposed controller.
      a.publish(printerOnly());
      a.markUnavailable();
    });
  });

  group('readVerifiedCachedMode (offline seed)', () {
    const platform = PosKitchenSpoolPlatform(isWeb: false);
    const ctx = DeviceContext(
      organizationId: 'org-1',
      restaurantId: 'rest-1',
      branchId: 'branch-1',
      deviceId: 'dev-1',
    );
    final fp = sessionFingerprint('tok');

    Future<KitchenModeResult?> run({
      required String mode,
      int? revision,
      DateTime? verifiedAt,
      DeviceContext? context = ctx,
      DeviceSessionCredential? cred = const DeviceSessionCredential(
        deviceId: 'dev-1',
        sessionToken: 'tok',
      ),
    }) async {
      final storage = _FakeSecureStorage();
      final cache = PosSecureKitchenModeCache(
        storage: storage,
        platform: platform,
        now: () => at,
      );
      await cache.write(
        KitchenModeCacheRecord(
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: 'branch-1',
          deviceId: 'dev-1',
          sessionFingerprint: fp,
          mode: mode,
          modeRevision: revision,
          verifiedAt: verifiedAt ?? at,
        ),
      );
      return readVerifiedCachedMode(
        cache: cache,
        secretStore: _FakeSecretStore(cred),
        context: context,
        now: () => at,
      );
    }

    test(
      'fresh printer_only WITH revision -> PrinterOnlyWithRevision',
      () async {
        expect(
          await run(mode: 'printer_only', revision: 4),
          isA<KitchenModePrinterOnlyWithRevision>(),
        );
      },
    );
    test('fresh kds -> VerifiedKds', () async {
      expect(
        await run(mode: 'kds', revision: 4),
        isA<KitchenModeVerifiedKds>(),
      );
    });
    test('printer_only WITHOUT a revision is untrusted -> null', () async {
      expect(await run(mode: 'printer_only'), isNull);
    });
    test(
      'a stale record (>10 min) -> null (never used to allow work)',
      () async {
        expect(
          await run(
            mode: 'printer_only',
            revision: 4,
            verifiedAt: at.subtract(const Duration(minutes: 20)),
          ),
          isNull,
        );
      },
    );
    test('no credential -> null', () async {
      expect(await run(mode: 'printer_only', revision: 4, cred: null), isNull);
    });
    test('missing scope (no device/restaurant) -> null', () async {
      expect(
        await run(
          mode: 'printer_only',
          revision: 4,
          context: const DeviceContext(
            organizationId: 'org-1',
            branchId: 'branch-1',
          ),
        ),
        isNull,
      );
    });
  });

  group('cart_panel Send-gate + payload (real integration)', () {
    Future<ProviderContainer> pump(
      WidgetTester tester,
      DemoOutboxStore repo,
    ) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [outboxRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: PosMenuScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(
        tester.element(find.byType(PosMenuScreen)),
      );
    }

    testWidgets(
      'unresolved mode BLOCKS Send, shows the hint, and enqueues ZERO ops',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final repo = DemoOutboxStore(delay: (_) async {});
        final c = await pump(tester, repo);
        // Force the (demo-default resolved) readiness back to Loading.
        c.read(posKitchenModeReadinessProvider.notifier).reset();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('send-kitchen-mode-hint')), findsOneWidget);
        // Tapping Send does nothing (button disabled).
        await tester.tap(find.text(l10n.posSendOrder));
        await tester.pumpAndSettle();
        expect(c.read(outboxControllerProvider), isEmpty);
      },
    );

    testWidgets(
      'resolved printer_only enables Send and emits dispatch_mode=direct_print',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final repo = DemoOutboxStore(delay: (_) async {});
        final c = await pump(tester, repo);
        c
            .read(posKitchenModeReadinessProvider.notifier)
            .bindScope(null)
            .publish(printerOnly());
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('send-kitchen-mode-hint')), findsNothing);
        await tester.tap(find.text(l10n.posSendOrder));
        await tester.pumpAndSettle();
        final entries = c.read(outboxControllerProvider);
        expect(entries, hasLength(1));
        expect(entries.single.payloadJson.contains('direct_print'), isTrue);
      },
    );

    testWidgets(
      'resolved kds enables Send and OMITS dispatch_mode (byte-identical)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final repo = DemoOutboxStore(delay: (_) async {});
        final c = await pump(tester, repo);
        c
            .read(posKitchenModeReadinessProvider.notifier)
            .bindScope(null)
            .publish(kds());
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.posSendOrder));
        await tester.pumpAndSettle();
        final entries = c.read(outboxControllerProvider);
        expect(entries, hasLength(1));
        expect(entries.single.payloadJson.contains('dispatch_mode'), isFalse);
      },
    );

    // KITCHEN-DISPATCH-ENFORCE-001 (bypass proof): the server now REJECTS a
    // direct_print submit on a non-printer_only branch, so the client must be
    // incapable of emitting a dispatch_mode that disagrees with the ONE
    // resolver. This asserts PARITY through the real submit path — the emitted
    // payload always equals resolveOrderDispatchMode(mode) for that mode, and
    // the key is OMITTED (never forged) whenever the decision is kds.
    testWidgets(
      'the emitted dispatch_mode always EQUALS the resolved decision',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        Future<Map<String, dynamic>> emitFor(KitchenModeResult mode) async {
          final repo = DemoOutboxStore(delay: (_) async {});
          final c = await pump(tester, repo);
          c
              .read(posKitchenModeReadinessProvider.notifier)
              .bindScope(null)
              .publish(mode);
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.posSendOrder));
          await tester.pumpAndSettle();
          final entries = c.read(outboxControllerProvider);
          expect(entries, hasLength(1));
          return jsonDecode(entries.single.payloadJson) as Map<String, dynamic>;
        }

        // VERIFIED printer_only -> the resolver says directPrint, and that is
        // exactly what the wire carries.
        final po = printerOnly();
        expect(resolveOrderDispatchMode(po), OrderDispatchMode.directPrint);
        expect((await emitFor(po))['dispatch_mode'], 'direct_print');

        // VERIFIED kds -> the resolver fails closed to kds, and the key is
        // omitted entirely (the deployed old-client contract the server
        // accepts on every branch mode).
        final k = kds();
        expect(resolveOrderDispatchMode(k), OrderDispatchMode.kds);
        expect((await emitFor(k)).containsKey('dispatch_mode'), isFalse);
      },
    );

    testWidgets('a double-tap while unresolved enqueues ZERO ops', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final repo = DemoOutboxStore(delay: (_) async {});
      final c = await pump(tester, repo);
      c.read(posKitchenModeReadinessProvider.notifier).reset();
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.posSendOrder), warnIfMissed: false);
      await tester.tap(find.text(l10n.posSendOrder), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(c.read(outboxControllerProvider), isEmpty);
    });
  });
}
