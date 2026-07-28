// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap A) — the kitchen-mode SUBMISSION
// READINESS: a NEW order must never be submitted with a GUESSED KDS dispatch
// before the verified/cached mode has resolved (which, on a real printer_only
// branch, would strand the order). Synthetic values only.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext, DeviceSessionCredential, DeviceSessionSecretStore;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart';
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

    test(
      'publish maps trusted modes to Resolved; non-trusted to Unavailable',
      () {
        final c = make(demo: false);
        addTearDown(c.dispose);
        final n = c.read(posKitchenModeReadinessProvider.notifier);
        n.publish(printerOnly());
        expect(
          c.read(posKitchenModeReadinessProvider),
          isA<KitchenModeReadinessResolved>(),
        );
        n.reset();
        n.publish(const KitchenModeRevisionUnavailable());
        expect(
          c.read(posKitchenModeReadinessProvider),
          isA<KitchenModeReadinessUnavailable>(),
        );
        n.reset();
        n.publish(const KitchenModeInvalidSession());
        expect(
          c.read(posKitchenModeReadinessProvider),
          isA<KitchenModeReadinessUnavailable>(),
        );
      },
    );

    test('a non-trusted result never DOWNGRADES an already resolved mode', () {
      final c = make(demo: false);
      addTearDown(c.dispose);
      final n = c.read(posKitchenModeReadinessProvider.notifier);
      n.publish(printerOnly());
      n.publish(const KitchenModeTransientFailure()); // a blip
      final r = c.read(posKitchenModeReadinessProvider);
      expect(r, isA<KitchenModeReadinessResolved>());
      expect(
        (r as KitchenModeReadinessResolved).mode,
        isA<KitchenModePrinterOnlyWithRevision>(),
      );
    });

    test('markUnavailable only acts while Loading', () {
      final c = make(demo: false);
      addTearDown(c.dispose);
      final n = c.read(posKitchenModeReadinessProvider.notifier);
      n.markUnavailable();
      expect(
        c.read(posKitchenModeReadinessProvider),
        isA<KitchenModeReadinessUnavailable>(),
      );
    });

    test('requestResolution reopens to Loading and calls the bound resolver; '
        'a no-op when nothing is bound (web/demo/unpaired)', () {
      final c = make(demo: false);
      addTearDown(c.dispose);
      final n = c.read(posKitchenModeReadinessProvider.notifier);
      // Nothing bound yet: a retry must be a safe no-op (never clears the block).
      n.markUnavailable();
      n.requestResolution();
      expect(
        c.read(posKitchenModeReadinessProvider),
        isA<KitchenModeReadinessUnavailable>(),
      );
      // The native composition binds the heartbeat's re-verify entrypoint; a
      // retry then reopens the gate to Loading and asks for a fresh check.
      var calls = 0;
      n.bindResolver(() => calls++);
      n.requestResolution();
      expect(calls, 1);
      expect(
        c.read(posKitchenModeReadinessProvider),
        isA<KitchenModeReadinessLoading>(),
      );
      // Unbinding (scope change / dispose) restores the no-op behavior.
      n.bindResolver(null);
      n.markUnavailable();
      n.requestResolution();
      expect(calls, 1);
      expect(
        c.read(posKitchenModeReadinessProvider),
        isA<KitchenModeReadinessUnavailable>(),
      );
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
        c.read(posKitchenModeReadinessProvider.notifier).publish(printerOnly());
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
        c.read(posKitchenModeReadinessProvider.notifier).publish(kds());
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.posSendOrder));
        await tester.pumpAndSettle();
        final entries = c.read(outboxControllerProvider);
        expect(entries, hasLength(1));
        expect(entries.single.payloadJson.contains('dispatch_mode'), isFalse);
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
