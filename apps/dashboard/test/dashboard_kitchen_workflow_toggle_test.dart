import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport;
import 'package:restoflow_dashboard/src/admin/branch_kitchen_workflow_repository.dart';
import 'package:restoflow_dashboard/src/admin/real_admin_views.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// DASHBOARD-PRINTER-ONLY-MODE-TOGGLE-010 — the owner-only kitchen workflow
/// control on the real-mode Settings tab.
///
/// It exists so an owner can move the verified one-device branch to
/// `printer_only`, which is what activates the server-side round-close fix from
/// migration 20260807090000. The control writes ONLY through the guarded RPC
/// (`public.set_kitchen_workflow_mode`) — never a branches-table update — and it
/// never shows a value the server has not confirmed.
class _FakeWorkflowRepo implements BranchKitchenWorkflowRepository {
  _FakeWorkflowRepo({
    this.initial = KitchenWorkflowMode.kds,
    KitchenWorkflowWriteResult? writeResult,
    this.writeGate,
  }) : writeResult =
           writeResult ??
           const KitchenWorkflowWriteResult(
             KitchenWorkflowWrite.ok,
             mode: KitchenWorkflowMode.printerOnly,
             revision: 2,
           );

  final KitchenWorkflowMode? initial;
  final KitchenWorkflowWriteResult writeResult;

  /// Holds the write open so a second press can be attempted mid-flight.
  final Completer<void>? writeGate;

  int reads = 0;
  int writes = 0;
  final List<KitchenWorkflowMode> requested = [];

  /// What a re-read returns after a successful write (the server's truth).
  KitchenWorkflowMode? afterWrite;

  @override
  Future<KitchenWorkflowMode?> read() async {
    reads++;
    if (writes > 0 && afterWrite != null) return afterWrite;
    return initial;
  }

  @override
  Future<KitchenWorkflowWriteResult> setMode(KitchenWorkflowMode mode) async {
    writes++;
    requested.add(mode);
    if (writeGate != null) await writeGate!.future;
    return writeResult;
  }
}

/// Records exactly what the REAL repository puts on the wire.
class _RecordingTransport implements SyncRpcTransport {
  _RecordingTransport(this.responses);

  final Map<String, Object?> responses;
  final List<String> calls = [];
  final List<Map<String, dynamic>> params = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    calls.add(function);
    params.add(Map<String, dynamic>.from(p));
    if (responses.containsKey(function)) return responses[function];
    throw StateError('unexpected RPC: $function');
  }
}

MembershipContext _membership(MembershipRole role) => MembershipContext(
  id: 'm-1',
  organizationId: 'org-1',
  organizationName: 'Maps Group',
  restaurantId: 'rest-1',
  restaurantName: 'Maps Burger',
  branchId: 'branch-1',
  branchName: 'Kafr Manda',
  role: role,
  status: 'active',
);

Future<AppLocalizations> _l10n(String code) =>
    AppLocalizations.delegate.load(Locale(code));

Future<void> _pump(
  WidgetTester tester, {
  required BranchKitchenWorkflowRepository repo,
  MembershipRole role = MembershipRole.orgOwner,
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: RealSettingsView(
            membership: _membership(role),
            currencyCode: 'ILS',
            kitchenWorkflowRepository: repo,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

RadioListTile<KitchenWorkflowMode> _tile(WidgetTester tester, String key) =>
    tester.widget<RadioListTile<KitchenWorkflowMode>>(find.byKey(Key(key)));

KitchenWorkflowMode? _selected(WidgetTester tester) {
  final group = tester.widget<RadioGroup<KitchenWorkflowMode>>(
    find.byType(RadioGroup<KitchenWorkflowMode>),
  );
  return group.groupValue;
}

Future<void> _choosePrinterOnly(
  WidgetTester tester, {
  bool confirm = true,
}) async {
  await tester.tap(find.byKey(const Key('kitchen-workflow-printer-only')));
  await tester.pumpAndSettle();
  if (confirm) {
    await tester.tap(find.byKey(const Key('kitchen-workflow-confirm')));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('1. an existing kds branch loads with kds selected', (
    tester,
  ) async {
    final repo = _FakeWorkflowRepo(initial: KitchenWorkflowMode.kds);
    await _pump(tester, repo: repo);
    expect(_selected(tester), KitchenWorkflowMode.kds);
    expect(repo.reads, 1, reason: 'read authoritatively from the server');
  });

  testWidgets('2. an existing printer_only branch loads with printer_only '
      'selected — never assumed from local state', (tester) async {
    final repo = _FakeWorkflowRepo(initial: KitchenWorkflowMode.printerOnly);
    await _pump(tester, repo: repo);
    expect(_selected(tester), KitchenWorkflowMode.printerOnly);
  });

  testWidgets('3+4+5. an owner moves kds -> printer_only: the guarded RPC is '
      'called ONCE with printer_only, and the screen shows the SERVER value', (
    tester,
  ) async {
    final repo = _FakeWorkflowRepo(initial: KitchenWorkflowMode.kds)
      ..afterWrite = KitchenWorkflowMode.printerOnly;
    await _pump(tester, repo: repo);
    final l10n = await _l10n('en');

    await _choosePrinterOnly(tester);

    expect(repo.writes, 1, reason: 'exactly one guarded write');
    expect(repo.requested, [KitchenWorkflowMode.printerOnly]);
    expect(_selected(tester), KitchenWorkflowMode.printerOnly);
    expect(
      repo.reads,
      2,
      reason: 'the branch is re-read authoritatively after a successful save',
    );
    expect(find.text(l10n.dashboardKitchenWorkflowSaved), findsOneWidget);
  });

  testWidgets('3b. the confirmation names the branch, the old mode and the new '
      'mode, and warns about printer_only', (tester) async {
    final repo = _FakeWorkflowRepo(initial: KitchenWorkflowMode.kds);
    await _pump(tester, repo: repo);
    final l10n = await _l10n('en');

    await _choosePrinterOnly(tester, confirm: false);

    expect(
      find.text(l10n.dashboardKitchenWorkflowConfirmTitle),
      findsOneWidget,
    );
    expect(
      find.text(l10n.dashboardKitchenWorkflowConfirmBranch('Kafr Manda')),
      findsOneWidget,
    );
    expect(
      find.text(
        l10n.dashboardKitchenWorkflowConfirmChange(
          l10n.dashboardKitchenWorkflowKdsLabel,
          l10n.dashboardKitchenWorkflowPrinterLabel,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text(l10n.dashboardKitchenWorkflowPrinterWarning),
      findsOneWidget,
    );
    expect(repo.writes, 0, reason: 'nothing is written before confirmation');
  });

  testWidgets('3c. cancelling the confirmation writes nothing and keeps the '
      'old value', (tester) async {
    final repo = _FakeWorkflowRepo(initial: KitchenWorkflowMode.kds);
    await _pump(tester, repo: repo);
    await _choosePrinterOnly(tester, confirm: false);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.writes, 0);
    expect(_selected(tester), KitchenWorkflowMode.kds);
  });

  testWidgets('6. a manager cannot edit it — the tiles are disabled, the '
      'owner-only note shows, and no write is possible', (tester) async {
    final repo = _FakeWorkflowRepo(initial: KitchenWorkflowMode.kds);
    await _pump(tester, repo: repo, role: MembershipRole.manager);
    final l10n = await _l10n('en');

    expect(_tile(tester, 'kitchen-workflow-kds').enabled, isFalse);
    expect(_tile(tester, 'kitchen-workflow-printer-only').enabled, isFalse);
    expect(find.text(l10n.dashboardKitchenWorkflowOwnerOnly), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('kitchen-workflow-printer-only')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(repo.writes, 0, reason: 'a non-owner cannot reach the RPC');
    expect(_selected(tester), KitchenWorkflowMode.kds);
  });

  testWidgets('6b. a cashier cannot edit it either', (tester) async {
    final repo = _FakeWorkflowRepo(initial: KitchenWorkflowMode.printerOnly);
    await _pump(tester, repo: repo, role: MembershipRole.cashier);
    expect(_tile(tester, 'kitchen-workflow-kds').enabled, isFalse);
    expect(repo.writes, 0);
  });

  testWidgets('6c. a server-side denial keeps the OLD value on screen', (
    tester,
  ) async {
    final repo = _FakeWorkflowRepo(
      initial: KitchenWorkflowMode.kds,
      writeResult: const KitchenWorkflowWriteResult(
        KitchenWorkflowWrite.denied,
      ),
    );
    await _pump(tester, repo: repo);
    final l10n = await _l10n('en');

    await _choosePrinterOnly(tester);

    expect(repo.writes, 1);
    expect(
      _selected(tester),
      KitchenWorkflowMode.kds,
      reason: 'the UI never adopts a value the server refused',
    );
    expect(find.text(l10n.dashboardKitchenWorkflowDenied), findsOneWidget);
  });

  testWidgets('7. an UNRECOGNISED server refusal (e.g. a future concurrency '
      'conflict) preserves the old value', (tester) async {
    // The shipped RPC takes no expected-revision argument — it serialises with
    // a row lock — so there is no revision-conflict envelope to simulate
    // faithfully. What IS reachable is an error this client does not know; it
    // must be treated as "nothing changed".
    final repo = _FakeWorkflowRepo(
      initial: KitchenWorkflowMode.kds,
      writeResult: const KitchenWorkflowWriteResult(
        KitchenWorkflowWrite.unavailable,
      ),
    );
    await _pump(tester, repo: repo);
    final l10n = await _l10n('en');

    await _choosePrinterOnly(tester);

    expect(_selected(tester), KitchenWorkflowMode.kds);
    expect(find.text(l10n.dashboardKitchenWorkflowSaveFailed), findsOneWidget);
  });

  testWidgets('8. a network failure preserves the old value and does not '
      'retry', (tester) async {
    final repo = _FakeWorkflowRepo(
      initial: KitchenWorkflowMode.printerOnly,
      writeResult: const KitchenWorkflowWriteResult(
        KitchenWorkflowWrite.unavailable,
      ),
    );
    await _pump(tester, repo: repo);
    await tester.tap(find.byKey(const Key('kitchen-workflow-kds')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kitchen-workflow-confirm')));
    await tester.pumpAndSettle();

    expect(repo.writes, 1, reason: 'no automatic retry');
    expect(_selected(tester), KitchenWorkflowMode.printerOnly);
  });

  testWidgets('9. a double press cannot produce a second write', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repo = _FakeWorkflowRepo(
      initial: KitchenWorkflowMode.kds,
      writeGate: gate,
    )..afterWrite = KitchenWorkflowMode.printerOnly;
    await _pump(tester, repo: repo);

    await _choosePrinterOnly(tester);
    expect(repo.writes, 1);

    // Press again while the first write is still in flight.
    await tester.tap(
      find.byKey(const Key('kitchen-workflow-printer-only')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(repo.writes, 1, reason: 'the in-flight guard blocks a second write');

    gate.complete();
    await tester.pumpAndSettle();
    expect(repo.writes, 1);
  });

  testWidgets('10. an unreadable mode shows an honest unavailable state and no '
      'control at all', (tester) async {
    final repo = _FakeWorkflowRepo(initial: null);
    await _pump(tester, repo: repo);
    final l10n = await _l10n('en');
    expect(
      find.byKey(const Key('kitchen-workflow-unavailable')),
      findsOneWidget,
    );
    expect(find.text(l10n.dashboardKitchenWorkflowUnavailable), findsOneWidget);
    expect(find.byKey(const Key('kitchen-workflow-kds')), findsNothing);
  });

  testWidgets('11. the section is omitted entirely without a seam (no branch '
      'in scope) — never a fake control', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: RealSettingsView(
              membership: _membership(MembershipRole.orgOwner),
              currencyCode: 'ILS',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kitchen-workflow-kds')), findsNothing);
  });

  testWidgets(
    '12. Arabic and Hebrew copy is present and distinct from English',
    (tester) async {
      final en = await _l10n('en');
      final ar = await _l10n('ar');
      final he = await _l10n('he');
      for (final s in [
        ar.dashboardKitchenWorkflowSectionTitle,
        ar.dashboardKitchenWorkflowKdsLabel,
        ar.dashboardKitchenWorkflowPrinterLabel,
        ar.dashboardKitchenWorkflowPrinterHelp,
        ar.dashboardKitchenWorkflowPrinterWarning,
        he.dashboardKitchenWorkflowSectionTitle,
        he.dashboardKitchenWorkflowKdsLabel,
        he.dashboardKitchenWorkflowPrinterLabel,
        he.dashboardKitchenWorkflowPrinterHelp,
        he.dashboardKitchenWorkflowPrinterWarning,
      ]) {
        expect(s.trim(), isNotEmpty);
      }
      expect(
        ar.dashboardKitchenWorkflowSectionTitle,
        isNot(en.dashboardKitchenWorkflowSectionTitle),
      );
      expect(
        he.dashboardKitchenWorkflowSectionTitle,
        isNot(en.dashboardKitchenWorkflowSectionTitle),
      );
      expect(ar.dashboardKitchenWorkflowSectionTitle, 'سير عمل المطبخ');
      expect(ar.dashboardKitchenWorkflowKdsLabel, 'شاشة مطبخ منفصلة');
      expect(
        ar.dashboardKitchenWorkflowPrinterLabel,
        'جهاز واحد مع طابعة مطبخ',
      );

      // And the Arabic UI actually renders the Arabic label.
      final repo = _FakeWorkflowRepo(initial: KitchenWorkflowMode.kds);
      await _pump(tester, repo: repo, locale: 'ar');
      expect(
        find.text(ar.dashboardKitchenWorkflowPrinterLabel),
        findsOneWidget,
      );
    },
  );

  group('the REAL repository wire contract', () {
    SupabaseBranchKitchenWorkflowRepository repo(_RecordingTransport t) =>
        SupabaseBranchKitchenWorkflowRepository(
          transport: t,
          organizationId: '20605c2b-org',
          restaurantId: 'de3bbc64-rest',
          branchId: '2847c0be-branch',
        );

    test(
      '4. the write calls EXACTLY the guarded RPC with the scoped arguments '
      'and the wire mode - no branches-table update, no org override',
      () async {
        final t = _RecordingTransport({
          'set_kitchen_workflow_mode': {
            'ok': true,
            'kitchen_workflow_mode': 'printer_only',
            'kitchen_workflow_mode_revision': 2,
            'changed': true,
          },
        });
        final result = await repo(t).setMode(KitchenWorkflowMode.printerOnly);

        expect(t.calls, ['set_kitchen_workflow_mode']);
        expect(t.params.single, {
          'p_organization_id': '20605c2b-org',
          'p_restaurant_id': 'de3bbc64-rest',
          'p_branch_id': '2847c0be-branch',
          'p_mode': 'printer_only',
        });
        expect(result.status, KitchenWorkflowWrite.ok);
        expect(result.mode, KitchenWorkflowMode.printerOnly);
        expect(result.revision, 2);
      },
    );

    test('4b. the read uses the authoritative branch read RPC', () async {
      final t = _RecordingTransport({
        'get_branch_kitchen_workflow_mode': {
          'ok': true,
          'kitchen_workflow_mode': 'kds',
        },
      });
      expect(await repo(t).read(), KitchenWorkflowMode.kds);
      expect(t.calls, ['get_branch_kitchen_workflow_mode']);
      expect(t.params.single.containsKey('p_mode'), isFalse);
    });

    test('10. no code path performs a direct branches-table update', () {
      // The runner's CWD is the repo root or the package dir depending on how
      // the suite is invoked; resolve against both rather than assume.
      const rel = 'lib/src/admin/branch_kitchen_workflow_repository.dart';
      final candidates = [rel, 'apps/dashboard/$rel'];
      final found = candidates
          .map(File.new)
          .firstWhere(
            (f) => f.existsSync(),
            orElse: () => throw StateError('repository source not found'),
          );
      final src = found.readAsStringSync();
      expect(src.contains('set_kitchen_workflow_mode'), isTrue);
      expect(
        src.contains('.from('),
        isFalse,
        reason: 'a PostgREST table builder would bypass the guarded RPC',
      );
      expect(src.toLowerCase().contains('update branches'), isFalse);
      expect(src.contains('service_role'), isFalse);
    });

    test('11. the seam is pinned to ONE branch, so a write cannot reach '
        'another branch', () async {
      final t = _RecordingTransport({
        'set_kitchen_workflow_mode': {
          'ok': true,
          'kitchen_workflow_mode': 'kds',
          'kitchen_workflow_mode_revision': 3,
        },
      });
      final r = SupabaseBranchKitchenWorkflowRepository(
        transport: t,
        organizationId: 'org-A',
        restaurantId: 'rest-A',
        branchId: 'branch-A',
      );
      await r.setMode(KitchenWorkflowMode.kds);
      expect(t.params.single['p_branch_id'], 'branch-A');
      expect(
        t.params.every((p) => p['p_branch_id'] == 'branch-A'),
        isTrue,
        reason: 'the branch id is constructor-pinned, never caller-supplied',
      );
    });

    test(
      'a success envelope without a readable mode is NOT claimed as applied',
      () async {
        final t = _RecordingTransport({
          'set_kitchen_workflow_mode': {'ok': true},
        });
        final result = await repo(t).setMode(KitchenWorkflowMode.printerOnly);
        expect(result.status, KitchenWorkflowWrite.unavailable);
        expect(result.mode, isNull);
      },
    );

    test('typed refusals map to distinct outcomes', () async {
      for (final (error, expected) in [
        ('permission_denied', KitchenWorkflowWrite.denied),
        ('not_found', KitchenWorkflowWrite.notFound),
        ('invalid_mode', KitchenWorkflowWrite.invalidMode),
        ('something_new', KitchenWorkflowWrite.unavailable),
      ]) {
        final t = _RecordingTransport({
          'set_kitchen_workflow_mode': {'ok': false, 'error': error},
        });
        final r = await repo(t).setMode(KitchenWorkflowMode.printerOnly);
        expect(r.status, expected, reason: error);
        expect(r.mode, isNull);
      }
    });
  });
}
