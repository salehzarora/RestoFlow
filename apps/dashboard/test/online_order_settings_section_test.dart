import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/online_orders/online_order_settings_copy.dart';
import 'package:restoflow_dashboard/src/online_orders/online_order_settings_repository.dart';
import 'package:restoflow_dashboard/src/online_orders/online_order_settings_section.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

const _initial = OnlineOrderSettings(
  revision: '40',
  values: OnlineOrderValues(ordering: true, alerts: true, printing: false),
);

class _Repo implements OnlineOrderSettingsRepository {
  OnlineOrderSettings state = _initial;
  OnlineOrderOutcome readOutcome = OnlineOrderOutcome.ok;
  OnlineOrderOutcome saveOutcome = OnlineOrderOutcome.ok;
  OnlineOrderReconciliation? reconciliation;
  Completer<void>? readGate;
  Completer<void>? saveGate;
  bool failReadAfterSave = false;
  int reads = 0;
  int reconciles = 0;
  final writes = <OnlineOrderMutation>[];

  @override
  Future<OnlineOrderResult> read() async {
    reads++;
    await readGate?.future;
    if (failReadAfterSave && writes.isNotEmpty) {
      return const OnlineOrderResult(OnlineOrderOutcome.unavailable);
    }
    return OnlineOrderResult(
      readOutcome,
      settings: readOutcome == OnlineOrderOutcome.ok ? state : null,
    );
  }

  @override
  Future<OnlineOrderResult> save(OnlineOrderMutation intent) async {
    writes.add(intent);
    await saveGate?.future;
    if (saveOutcome == OnlineOrderOutcome.ok) {
      state = OnlineOrderSettings(revision: '41', values: intent.values);
      return OnlineOrderResult(OnlineOrderOutcome.ok, settings: state);
    }
    return OnlineOrderResult(saveOutcome, settings: state);
  }

  @override
  Future<OnlineOrderReconciliation> reconcile(
    OnlineOrderMutation intent,
  ) async {
    reconciles++;
    return reconciliation ??
        const OnlineOrderReconciliation(OnlineOrderOutcome.unavailable);
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Repo repo, {
  String language = 'en',
  bool canManage = true,
  double width = 1200,
  double textScale = 1,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        fontFamily:
            Platform.environment['BIZBOT_ONLINE_CONTROLS_CAPTURE_DIR'] != null
            ? 'QAArial'
            : null,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      locale: Locale(language),
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: RepaintBoundary(
        key: const Key('capture'),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: OnlineOrderSettingsSection(
                repository: repo,
                canManage: canManage,
                branchName: 'QA — Synthetic branch',
                mutationId: () => '157bc841-5b3d-4e42-b551-7ad00c6a8a19',
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (settle)
    await tester.pumpAndSettle();
  else
    await tester.pump();
}

SwitchListTile _toggle(WidgetTester tester, String key) =>
    tester.widget(find.byKey(Key('online-order-$key-toggle')));

Future<void> _tap(WidgetTester tester, String key, {bool settle = true}) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  if (settle)
    await tester.pumpAndSettle();
  else
    await tester.pump();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['BIZBOT_ONLINE_CONTROLS_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Real glyphs for opt-in local captures; ordinary tests keep Flutter's
    // deterministic test font and need no OS fonts or filesystem access.
    if (Platform.environment['BIZBOT_ONLINE_CONTROLS_CAPTURE_DIR'] == null)
      return;
    for (final entry in {
      'QAArial': Platform.environment['BIZBOT_QA_TEXT_FONT'],
      'MaterialIcons': Platform.environment['BIZBOT_QA_ICON_FONT'],
    }.entries) {
      final file = entry.value;
      if (file == null) throw StateError('Capture font path required');
      final bytes = await File(file).readAsBytes();
      final loader = FontLoader(entry.key)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
  for (final language in ['ar', 'he', 'en']) {
    testWidgets(
      '$language renders three independent accessible controls and save/failure UX',
      (tester) async {
        final repo = _Repo();
        final copy = OnlineOrderSettingsCopy(language);
        await _pump(tester, repo, language: language);
        expect(find.text(copy.title), findsOneWidget);
        expect(find.text(copy.orderingHelp), findsOneWidget);
        expect(find.text(copy.alertsHelp), findsOneWidget);
        expect(
          copy.alertsHelp,
          contains(switch (language) {
            'ar' => 'لا يعيد تفعيل الأجهزة تلقائيًا',
            'he' => 'אינה מפעילה מכשירים אוטומטית',
            _ => 'does not re-enable devices automatically',
          }),
        );
        expect(
          copy.alertsHelp,
          contains(switch (language) {
            'ar' => 'داخل POS المفتوح مجددًا',
            'he' => 'בדרך הרגילה כאשר POS פתוח',
            _ => 'enable alerts normally in foreground POS again',
          }),
        );
        expect(find.text(copy.printingHelp), findsOneWidget);
        final context = tester.element(
          find.byKey(const Key('online-order-settings-section')),
        );
        expect(
          Directionality.of(context),
          language == 'en' ? TextDirection.ltr : TextDirection.rtl,
        );
        expect(_toggle(tester, 'ordering').value, true);
        expect(_toggle(tester, 'alerts').value, true);
        expect(_toggle(tester, 'printing').value, false);
        await _capture(tester, '$language-authoritative');
        await _tap(tester, 'online-order-alerts-toggle');
        expect(find.text(copy.dirty), findsOneWidget);
        expect(repo.writes, isEmpty);
        expect(_toggle(tester, 'ordering').value, true);
        expect(_toggle(tester, 'printing').value, false);
        repo.saveOutcome = OnlineOrderOutcome.unavailable;
        await _tap(tester, 'online-order-save');
        expect(find.text(copy.uncertain), findsOneWidget);
        expect(repo.writes, hasLength(1));
        expect(_toggle(tester, 'alerts').onChanged, isNull);
        expect(find.byKey(const Key('online-order-resend')), findsNothing);
        await _capture(tester, '$language-uncertain');
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final field in ['ordering', 'alerts', 'printing']) {
    testWidgets('explicit Save changes only $field and rereads server state', (
      tester,
    ) async {
      final repo = _Repo();
      await _pump(tester, repo);
      await _tap(tester, 'online-order-$field-toggle');
      expect(repo.writes, isEmpty);
      await _tap(tester, 'online-order-save');
      final value = repo.writes.single.values;
      expect(value.ordering, field == 'ordering' ? false : true);
      expect(value.alerts, field == 'alerts' ? false : true);
      expect(value.printing, field == 'printing' ? true : false);
      expect(repo.writes.single.expectedRevision, '40');
      expect(repo.reads, 2);
      expect(find.byKey(const Key('online-order-unsaved')), findsNothing);
    });
  }

  testWidgets(
    'loading is authoritative and failed reads expose no fake toggles',
    (tester) async {
      final gate = Completer<void>();
      final repo = _Repo()
        ..readGate = gate
        ..readOutcome = OnlineOrderOutcome.unavailable;
      await _pump(tester, repo, settle: false);
      expect(
        find.byKey(const Key('online-order-settings-loading')),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        find.text(OnlineOrderSettingsCopy('en').unavailable),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsNothing);
      expect(repo.writes, isEmpty);
    },
  );

  testWidgets('cashier advisory gate disables all controls and save', (
    tester,
  ) async {
    final repo = _Repo();
    await _pump(tester, repo, canManage: false);
    for (final field in ['ordering', 'alerts', 'printing']) {
      expect(_toggle(tester, field).onChanged, isNull);
    }
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('online-order-save')))
          .onPressed,
      isNull,
    );
    expect(repo.writes, isEmpty);
  });

  testWidgets('server denial overrides manager-looking client gate', (
    tester,
  ) async {
    final repo = _Repo()..readOutcome = OnlineOrderOutcome.denied;
    await _pump(tester, repo);
    expect(find.text(OnlineOrderSettingsCopy('en').denied), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(repo.writes, isEmpty);
  });

  testWidgets('one write at a time; no duplicate Save while pending', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repo = _Repo()..saveGate = gate;
    await _pump(tester, repo);
    await _tap(tester, 'online-order-ordering-toggle');
    await _tap(tester, 'online-order-save', settle: false);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('online-order-save')))
          .onPressed,
      isNull,
    );
    expect(_toggle(tester, 'printing').onChanged, isNull);
    expect(repo.writes, hasLength(1));
    gate.complete();
    await tester.pumpAndSettle();
    expect(repo.writes, hasLength(1));
  });

  testWidgets(
    'stale revision freezes draft until explicit discard and fresh read',
    (tester) async {
      final repo = _Repo()..saveOutcome = OnlineOrderOutcome.revisionConflict;
      await _pump(tester, repo);
      await _tap(tester, 'online-order-ordering-toggle');
      repo.state = OnlineOrderSettings(
        revision: '41',
        values: _initial.values.copyWith(alerts: false),
      );
      await _tap(tester, 'online-order-save');
      expect(find.text(OnlineOrderSettingsCopy('en').conflict), findsOneWidget);
      expect(_toggle(tester, 'alerts').onChanged, isNull);
      expect(repo.writes, hasLength(1));
      expect(repo.reads, 1);
      await _tap(tester, 'online-order-reload');
      expect(_toggle(tester, 'ordering').value, true);
      expect(_toggle(tester, 'alerts').value, false);
      expect(find.byKey(const Key('online-order-unsaved')), findsNothing);
      expect(repo.writes, hasLength(1));
    },
  );

  testWidgets('uncertain commit reconciles by receipt without resending', (
    tester,
  ) async {
    final repo = _Repo()..saveOutcome = OnlineOrderOutcome.unavailable;
    await _pump(tester, repo);
    await _tap(tester, 'online-order-alerts-toggle');
    await _tap(tester, 'online-order-save');
    await tester.pump(const Duration(seconds: 15));
    expect(repo.writes, hasLength(1));
    expect(repo.reconciles, 0);
    repo.reconciliation = OnlineOrderReconciliation(
      OnlineOrderOutcome.ok,
      state: OnlineOrderMutationState.committed,
      current: OnlineOrderSettings(
        revision: '42',
        values: _initial.values.copyWith(alerts: false, printing: true),
      ),
    );
    await _tap(tester, 'online-order-check-save');
    expect(repo.writes, hasLength(1));
    expect(repo.reconciles, 1);
    expect(_toggle(tester, 'printing').value, true);
    expect(find.byKey(const Key('online-order-check-save')), findsNothing);
  });

  testWidgets(
    'only verified not-recorded permits explicit SAME intent resend',
    (tester) async {
      final repo = _Repo()..saveOutcome = OnlineOrderOutcome.unavailable;
      await _pump(tester, repo);
      await _tap(tester, 'online-order-alerts-toggle');
      await _tap(tester, 'online-order-save');
      await _tap(tester, 'online-order-check-save');
      expect(find.byKey(const Key('online-order-resend')), findsNothing);
      repo.reconciliation = const OnlineOrderReconciliation(
        OnlineOrderOutcome.ok,
        state: OnlineOrderMutationState.notRecorded,
        current: _initial,
      );
      await _tap(tester, 'online-order-check-save');
      expect(repo.writes, hasLength(1));
      expect(find.byKey(const Key('online-order-resend')), findsOneWidget);
      expect(find.byKey(const Key('online-order-reload')), findsNothing);
      repo.saveOutcome = OnlineOrderOutcome.ok;
      await _tap(tester, 'online-order-resend');
      expect(repo.writes, hasLength(2));
      expect(identical(repo.writes.first, repo.writes.last), true);
    },
  );

  testWidgets(
    'not-recorded retains identity until late original commit is reconciled',
    (tester) async {
      final repo = _Repo()..saveOutcome = OnlineOrderOutcome.unavailable;
      await _pump(tester, repo);
      await _tap(tester, 'online-order-alerts-toggle');
      await _tap(tester, 'online-order-save');
      repo.reconciliation = const OnlineOrderReconciliation(
        OnlineOrderOutcome.ok,
        state: OnlineOrderMutationState.notRecorded,
        current: _initial,
      );
      await _tap(tester, 'online-order-check-save');
      expect(find.byKey(const Key('online-order-reload')), findsNothing);
      expect(find.byKey(const Key('online-order-save')), findsNothing);
      expect(_toggle(tester, 'ordering').onChanged, isNull);
      repo.reconciliation = OnlineOrderReconciliation(
        OnlineOrderOutcome.ok,
        state: OnlineOrderMutationState.committed,
        current: OnlineOrderSettings(
          revision: '41',
          values: repo.writes.single.values,
        ),
      );
      await _tap(tester, 'online-order-check-save');
      expect(repo.writes, hasLength(1));
      expect(find.byKey(const Key('online-order-resend')), findsNothing);
      expect(find.byKey(const Key('online-order-reload')), findsOneWidget);
      expect(_toggle(tester, 'alerts').value, false);
    },
  );

  testWidgets('confirmed write plus failed current read never resubmits', (
    tester,
  ) async {
    final repo = _Repo()..failReadAfterSave = true;
    await _pump(tester, repo);
    await _tap(tester, 'online-order-alerts-toggle');
    await _tap(tester, 'online-order-save');
    expect(
      find.text(OnlineOrderSettingsCopy('en').savedReadUnavailable),
      findsOneWidget,
    );
    expect(find.byType(SwitchListTile), findsNothing);
    expect(repo.writes, hasLength(1));
    repo.failReadAfterSave = false;
    await _tap(tester, 'online-order-reload');
    expect(_toggle(tester, 'alerts').value, false);
    expect(repo.writes, hasLength(1));
  });

  testWidgets('uncertain result resolves to a recorded refusal without retry', (
    tester,
  ) async {
    final repo = _Repo()..saveOutcome = OnlineOrderOutcome.unavailable;
    await _pump(tester, repo);
    await _tap(tester, 'online-order-alerts-toggle');
    await _tap(tester, 'online-order-save');
    repo.reconciliation = const OnlineOrderReconciliation(
      OnlineOrderOutcome.revisionConflict,
      state: OnlineOrderMutationState.refused,
      current: _initial,
    );
    await _tap(tester, 'online-order-check-save');
    expect(find.text(OnlineOrderSettingsCopy('en').conflict), findsOneWidget);
    expect(find.byKey(const Key('online-order-resend')), findsNothing);
    expect(find.byKey(const Key('online-order-check-save')), findsNothing);
    expect(repo.writes, hasLength(1));
    await _tap(tester, 'online-order-reload');
    expect(repo.writes, hasLength(1));
  });

  testWidgets(
    'reconciliation authority denial keeps uncertainty and never resends',
    (tester) async {
      final repo = _Repo()..saveOutcome = OnlineOrderOutcome.unavailable;
      await _pump(tester, repo);
      await _tap(tester, 'online-order-alerts-toggle');
      await _tap(tester, 'online-order-save');
      repo.reconciliation = const OnlineOrderReconciliation(
        OnlineOrderOutcome.denied,
      );
      await _tap(tester, 'online-order-check-save');
      expect(
        find.textContaining(OnlineOrderSettingsCopy('en').denied),
        findsOneWidget,
      );
      expect(
        find.textContaining(OnlineOrderSettingsCopy('en').uncertain),
        findsOneWidget,
      );
      expect(find.byKey(const Key('online-order-resend')), findsNothing);
      expect(find.byKey(const Key('online-order-reload')), findsNothing);
      expect(repo.writes, hasLength(1));
    },
  );

  testWidgets('late previous-branch response cannot replace selected branch', (
    tester,
  ) async {
    final gate = Completer<void>();
    final old = _Repo()..readGate = gate;
    await _pump(tester, old, settle: false);
    final next = _Repo()
      ..state = OnlineOrderSettings(
        revision: '80',
        values: _initial.values.copyWith(ordering: false),
      );
    await _pump(tester, next);
    gate.complete();
    await tester.pumpAndSettle();
    expect(_toggle(tester, 'ordering').value, false);
    expect(next.reads, 1);
  });

  testWidgets('390px RTL at large text remains usable without overflow', (
    tester,
  ) async {
    await _pump(tester, _Repo(), language: 'ar', width: 390, textScale: 2);
    await tester.ensureVisible(find.byKey(const Key('online-order-save')));
    await _capture(tester, 'ar-mobile');
    expect(tester.takeException(), isNull);
  });
}
