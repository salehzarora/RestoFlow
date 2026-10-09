import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/admin/branch_kitchen_workflow_repository.dart';
import 'package:restoflow_dashboard/src/admin/branch_order_edit_settings_repository.dart';
import 'package:restoflow_dashboard/src/admin/real_admin_views.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// ORDER-EDIT-001G — the owner-only "Editing sent orders" Settings card over
/// `get_branch_order_edit_settings` (§4.47a) and the ORDER-EDIT-001A setter
/// `set_branch_order_edit_settings` (§4.45.8).
///
/// The card never shows a value the server has not confirmed: writes are not
/// optimistic, the server's echo is adopted and then re-read, and a refusal or
/// a failure leaves the stored values on screen.
class _FakeRepo implements BranchOrderEditSettingsRepository {
  _FakeRepo({
    this.enabled = false,
    this.finished = false,
    this.readMode,
    this.readStatus = OrderEditSettingsStatus.ok,
    this.writeStatus = OrderEditSettingsStatus.ok,
    this.echo,
    this.writeGate,
    this.failReadsAfterWrite = false,
  });

  bool enabled;
  bool finished;
  final KitchenWorkflowMode? readMode;
  final OrderEditSettingsStatus readStatus;
  final OrderEditSettingsStatus writeStatus;

  /// What the server echoes on a successful write; null = the requested pair.
  final (bool, bool)? echo;
  final Completer<void>? writeGate;

  /// Every read after the first write fails, so only the echo can move the
  /// displayed value.
  final bool failReadsAfterWrite;

  int reads = 0;
  final List<(bool, bool)> writes = <(bool, bool)>[];

  @override
  Future<OrderEditSettingsResult> read() async {
    reads++;
    if (failReadsAfterWrite && writes.isNotEmpty) {
      return const OrderEditSettingsResult(OrderEditSettingsStatus.unavailable);
    }
    if (readStatus != OrderEditSettingsStatus.ok) {
      return OrderEditSettingsResult(readStatus);
    }
    return OrderEditSettingsResult(
      OrderEditSettingsStatus.ok,
      settings: OrderEditSettings(
        enabled: enabled,
        finishedFoodManagerOnly: finished,
        kitchenMode: readMode,
      ),
    );
  }

  @override
  Future<OrderEditSettingsResult> write({
    required bool enabled,
    required bool finishedFoodManagerOnly,
  }) async {
    writes.add((enabled, finishedFoodManagerOnly));
    if (writeGate != null) await writeGate!.future;
    if (writeStatus != OrderEditSettingsStatus.ok) {
      return OrderEditSettingsResult(writeStatus);
    }
    final (e, f) = echo ?? (enabled, finishedFoodManagerOnly);
    // The server's truth for any later re-read.
    this.enabled = e;
    finished = f;
    return OrderEditSettingsResult(
      OrderEditSettingsStatus.ok,
      settings: OrderEditSettings(enabled: e, finishedFoodManagerOnly: f),
    );
  }
}

class _FakeWorkflowRepo implements BranchKitchenWorkflowRepository {
  _FakeWorkflowRepo(this.mode);
  KitchenWorkflowMode mode;

  @override
  Future<KitchenWorkflowMode?> read() async => mode;

  @override
  Future<KitchenWorkflowWriteResult> setMode(KitchenWorkflowMode next) async {
    mode = next;
    return KitchenWorkflowWriteResult(KitchenWorkflowWrite.ok, mode: next);
  }
}

class _RecordingTransport implements SyncRpcTransport {
  _RecordingTransport(this.responses, {this.throwFor = const {}});

  final Map<String, Object?> responses;
  final Set<String> throwFor;
  final List<String> calls = [];
  final List<Map<String, dynamic>> params = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    calls.add(function);
    params.add(Map<String, dynamic>.from(p));
    if (throwFor.contains(function)) throw StateError('42501');
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
  BranchOrderEditSettingsRepository? repo,
  BranchKitchenWorkflowRepository? workflow,
  MembershipRole role = MembershipRole.orgOwner,
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(1400, 3000);
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
            kitchenWorkflowRepository: workflow,
            orderEditSettingsRepository: repo,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

SwitchListTile _switch(WidgetTester tester, String key) =>
    tester.widget<SwitchListTile>(find.byKey(Key(key)));

const _enabledKey = 'order-edit-enabled-toggle';
const _finishedKey = 'order-edit-finished-food-toggle';

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  group('the section', () {
    testWidgets('loads the server values', (tester) async {
      final repo = _FakeRepo(enabled: true);
      await _pump(tester, repo: repo);
      expect(
        find.byKey(const Key('order-edit-settings-section')),
        findsOneWidget,
      );
      expect(_switch(tester, _enabledKey).value, isTrue);
      expect(_switch(tester, _finishedKey).value, isFalse);
      expect(repo.reads, 1);
    });

    testWidgets('an unreadable value shows an honest unavailable state', (
      tester,
    ) async {
      final l10n = await _l10n('en');
      await _pump(
        tester,
        repo: _FakeRepo(readStatus: OrderEditSettingsStatus.unavailable),
      );
      expect(
        find.byKey(const Key('order-edit-settings-unavailable')),
        findsOneWidget,
      );
      expect(
        find.text(l10n.dashboardKitchenWorkflowUnavailable),
        findsOneWidget,
      );
      expect(find.byKey(const Key(_enabledKey)), findsNothing);

      await _pump(
        tester,
        repo: _FakeRepo(readStatus: OrderEditSettingsStatus.notFound),
      );
      expect(find.text(l10n.dashboardKitchenWorkflowNotFound), findsOneWidget);
    });

    testWidgets('the owner turns editing on: the OTHER switch keeps its '
        'server value, the echo is adopted and re-read', (tester) async {
      final l10n = await _l10n('en');
      final repo = _FakeRepo(enabled: false, finished: true);
      await _pump(tester, repo: repo);
      await _tap(tester, _enabledKey);
      expect(repo.writes, [(true, true)]);
      expect(_switch(tester, _enabledKey).value, isTrue);
      expect(_switch(tester, _finishedKey).value, isTrue);
      expect(repo.reads, 2, reason: 're-read after a successful write');
      expect(find.text(l10n.dashboardOrderEditSaved), findsOneWidget);
    });

    testWidgets('the owner sets the finished-food rule', (tester) async {
      final repo = _FakeRepo(enabled: true, finished: false);
      await _pump(tester, repo: repo);
      await _tap(tester, _finishedKey);
      expect(repo.writes, [(true, true)]);
      expect(_switch(tester, _finishedKey).value, isTrue);
    });

    testWidgets('the SERVER echo wins over the requested value', (
      tester,
    ) async {
      final repo = _FakeRepo(enabled: false, echo: (false, false));
      await _pump(tester, repo: repo);
      await _tap(tester, _enabledKey);
      expect(repo.writes.single, (true, false));
      expect(_switch(tester, _enabledKey).value, isFalse);
    });

    testWidgets('the echo is adopted even when the re-read fails', (
      tester,
    ) async {
      final repo = _FakeRepo(
        enabled: false,
        echo: (false, true),
        failReadsAfterWrite: true,
      );
      await _pump(tester, repo: repo);
      await _tap(tester, _enabledKey);
      expect(repo.writes.single, (true, false));
      expect(repo.reads, 2);
      // The server said (false, true): neither the requested `true` nor the
      // old `false` for the second switch.
      expect(_switch(tester, _enabledKey).value, isFalse);
      expect(_switch(tester, _finishedKey).value, isTrue);
    });

    for (final (status, message) in [
      (OrderEditSettingsStatus.denied, 'denied'),
      (OrderEditSettingsStatus.notFound, 'notFound'),
      (OrderEditSettingsStatus.unavailable, 'failed'),
    ]) {
      testWidgets('a $message write keeps the old values', (tester) async {
        final l10n = await _l10n('en');
        final repo = _FakeRepo(writeStatus: status);
        await _pump(tester, repo: repo);
        await _tap(tester, _enabledKey);
        expect(repo.writes, hasLength(1));
        expect(_switch(tester, _enabledKey).value, isFalse);
        expect(repo.reads, 1, reason: 'no re-read claims a change');
        final expected = switch (status) {
          OrderEditSettingsStatus.denied => l10n.dashboardKitchenWorkflowDenied,
          OrderEditSettingsStatus.notFound =>
            l10n.dashboardKitchenWorkflowNotFound,
          _ => l10n.dashboardOrderEditSaveFailed,
        };
        expect(find.text(expected), findsOneWidget);
      });
    }

    testWidgets('a double press cannot produce a second write', (tester) async {
      final gate = Completer<void>();
      final repo = _FakeRepo(writeGate: gate);
      await _pump(tester, repo: repo);
      await tester.tap(find.byKey(const Key(_enabledKey)));
      await tester.pump();
      // Mid-flight: both switches are locked.
      expect(_switch(tester, _enabledKey).onChanged, isNull);
      expect(_switch(tester, _finishedKey).onChanged, isNull);
      await tester.tap(find.byKey(const Key(_enabledKey)), warnIfMissed: false);
      await tester.tap(
        find.byKey(const Key(_finishedKey)),
        warnIfMissed: false,
      );
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(repo.writes, hasLength(1));
    });

    for (final role in [MembershipRole.manager, MembershipRole.cashier]) {
      testWidgets('a ${role.name} sees the switches locked with the owner '
          'note', (tester) async {
        final l10n = await _l10n('en');
        final repo = _FakeRepo(enabled: true);
        await _pump(tester, repo: repo, role: role);
        expect(_switch(tester, _enabledKey).value, isTrue);
        expect(_switch(tester, _enabledKey).onChanged, isNull);
        expect(_switch(tester, _finishedKey).onChanged, isNull);
        expect(
          find.byKey(const Key('order-edit-settings-owner-only')),
          findsOneWidget,
        );
        expect(find.text(l10n.dashboardKitchenWorkflowOwnerOnly), findsWidgets);
        await tester.tap(
          find.byKey(const Key(_enabledKey)),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(repo.writes, isEmpty);
      });
    }

    testWidgets('the section is omitted without a seam', (tester) async {
      await _pump(tester);
      expect(
        find.byKey(const Key('order-edit-settings-section')),
        findsNothing,
      );
    });
  });

  group('the printer-only note', () {
    testWidgets('shown on a printer_only branch, value kept and editable', (
      tester,
    ) async {
      final l10n = await _l10n('en');
      final repo = _FakeRepo(enabled: true, finished: true);
      await _pump(
        tester,
        repo: repo,
        workflow: _FakeWorkflowRepo(KitchenWorkflowMode.printerOnly),
      );
      expect(
        find.byKey(const Key('order-edit-printer-only-note')),
        findsOneWidget,
      );
      expect(
        find.text(l10n.dashboardOrderEditFinishedFoodPrinterOnlyNote),
        findsOneWidget,
      );
      expect(_switch(tester, _finishedKey).value, isTrue);
      expect(_switch(tester, _finishedKey).onChanged, isNotNull);
    });

    testWidgets('hidden on a kds branch', (tester) async {
      await _pump(
        tester,
        repo: _FakeRepo(),
        workflow: _FakeWorkflowRepo(KitchenWorkflowMode.kds),
      );
      expect(
        find.byKey(const Key('order-edit-printer-only-note')),
        findsNothing,
      );
    });

    testWidgets('follows the kitchen workflow live', (tester) async {
      await _pump(
        tester,
        repo: _FakeRepo(),
        workflow: _FakeWorkflowRepo(KitchenWorkflowMode.kds),
      );
      expect(
        find.byKey(const Key('order-edit-printer-only-note')),
        findsNothing,
      );
      await _tap(tester, 'kitchen-workflow-printer-only');
      await _tap(tester, 'kitchen-workflow-confirm');
      expect(
        find.byKey(const Key('order-edit-printer-only-note')),
        findsOneWidget,
      );
    });

    testWidgets('falls back to the reader\'s own mode without the workflow '
        'card', (tester) async {
      await _pump(
        tester,
        repo: _FakeRepo(readMode: KitchenWorkflowMode.printerOnly),
      );
      expect(
        find.byKey(const Key('order-edit-printer-only-note')),
        findsOneWidget,
      );
    });

    testWidgets('Arabic and Hebrew render the card', (tester) async {
      for (final code in ['ar', 'he']) {
        final l10n = await _l10n(code);
        await _pump(
          tester,
          repo: _FakeRepo(readMode: KitchenWorkflowMode.printerOnly),
          locale: code,
        );
        expect(find.text(l10n.dashboardOrderEditSectionTitle), findsOneWidget);
        expect(find.text(l10n.dashboardOrderEditEnabledLabel), findsOneWidget);
        expect(
          find.text(l10n.dashboardOrderEditFinishedFoodPrinterOnlyNote),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('the REAL repository wire contract', () {
    SupabaseBranchOrderEditSettingsRepository repo(
      _RecordingTransport t, {
      int Function()? nonce,
    }) => SupabaseBranchOrderEditSettingsRepository(
      transport: t,
      organizationId: 'org-A',
      restaurantId: 'rest-A',
      branchId: 'branch-A',
      nonce: nonce,
    );

    test('the read calls the reader with the pinned scope only', () async {
      final t = _RecordingTransport({
        'get_branch_order_edit_settings': {
          'ok': true,
          'entity': 'branch',
          'branch_id': 'branch-A',
          'order_edit_enabled': true,
          'order_edit_finished_food_manager_only': false,
          'kitchen_workflow_mode': 'printer_only',
        },
      });
      final r = await repo(t).read();
      expect(t.calls, ['get_branch_order_edit_settings']);
      expect(t.params.single, {
        'p_organization_id': 'org-A',
        'p_restaurant_id': 'rest-A',
        'p_branch_id': 'branch-A',
      });
      expect(r.status, OrderEditSettingsStatus.ok);
      expect(r.settings!.enabled, isTrue);
      expect(r.settings!.finishedFoodManagerOnly, isFalse);
      expect(r.settings!.kitchenMode, KitchenWorkflowMode.printerOnly);
    });

    test('the write calls the guarded setter with both switches and a '
        'fresh request id per press', () async {
      var n = 0;
      final t = _RecordingTransport({
        'set_branch_order_edit_settings': {
          'ok': true,
          'idempotent_replay': false,
          'entity': 'branch',
          'branch_id': 'branch-A',
          'order_edit_enabled': true,
          'order_edit_finished_food_manager_only': true,
        },
      });
      final r = repo(t, nonce: () => ++n);
      final result = await r.write(
        enabled: true,
        finishedFoodManagerOnly: true,
      );
      await r.write(enabled: true, finishedFoodManagerOnly: true);
      expect(t.calls, [
        'set_branch_order_edit_settings',
        'set_branch_order_edit_settings',
      ]);
      final p = t.params.first;
      expect(p.keys.toSet(), {
        'p_client_request_id',
        'p_organization_id',
        'p_restaurant_id',
        'p_branch_id',
        'p_order_edit_enabled',
        'p_finished_food_manager_only',
      });
      expect(p['p_order_edit_enabled'], isTrue);
      expect(p['p_finished_food_manager_only'], isTrue);
      expect(p['p_branch_id'], 'branch-A');
      final id1 = p['p_client_request_id'] as String;
      final id2 = t.params.last['p_client_request_id'] as String;
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(id1),
        isTrue,
      );
      expect(id1, isNot(id2), reason: 'each press is its own request');
      expect(result.status, OrderEditSettingsStatus.ok);
      expect(result.settings!.kitchenMode, isNull);
    });

    test('envelopes map to typed outcomes', () async {
      Future<OrderEditSettingsStatus> write(Object? response) async {
        final t = _RecordingTransport({
          'set_branch_order_edit_settings': response,
        });
        return (await repo(
          t,
        ).write(enabled: true, finishedFoodManagerOnly: false)).status;
      }

      expect(
        await write({
          'ok': false,
          'error': 'permission_denied',
          'entity': 'branch',
        }),
        OrderEditSettingsStatus.denied,
      );
      expect(
        await write({'ok': false, 'error': 'not_found', 'entity': 'branch'}),
        OrderEditSettingsStatus.notFound,
      );
      expect(
        await write({'ok': false, 'error': 'something_new'}),
        OrderEditSettingsStatus.unavailable,
      );
      expect(
        await write({'ok': true}),
        OrderEditSettingsStatus.unavailable,
        reason: 'a success without readable switches is not adopted',
      );
      expect(await write('x'), OrderEditSettingsStatus.unavailable);

      final thrown = _RecordingTransport(
        const {},
        throwFor: {
          'set_branch_order_edit_settings',
          'get_branch_order_edit_settings',
        },
      );
      expect(
        (await repo(
          thrown,
        ).write(enabled: true, finishedFoodManagerOnly: true)).status,
        OrderEditSettingsStatus.unavailable,
      );
      expect(
        (await repo(thrown).read()).status,
        OrderEditSettingsStatus.unavailable,
      );
      final notFound = _RecordingTransport({
        'get_branch_order_edit_settings': {
          'ok': false,
          'error': 'not_found',
          'entity': 'branch',
        },
      });
      expect(
        (await repo(notFound).read()).status,
        OrderEditSettingsStatus.notFound,
      );
    });

    test('no code path performs a direct branches-table update', () {
      const rel = 'lib/src/admin/branch_order_edit_settings_repository.dart';
      final candidates = [rel, 'apps/dashboard/$rel'];
      final found = candidates
          .map(File.new)
          .firstWhere(
            (f) => f.existsSync(),
            orElse: () => throw StateError('repository source not found'),
          );
      final src = found.readAsStringSync();
      expect(src.contains('set_branch_order_edit_settings'), isTrue);
      expect(src.contains('get_branch_order_edit_settings'), isTrue);
      expect(src.contains('.from('), isFalse);
      expect(src.toLowerCase().contains('update branches'), isFalse);
      expect(src.contains('service_role'), isFalse);
    });
  });
}
