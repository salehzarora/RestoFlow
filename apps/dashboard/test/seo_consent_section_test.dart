import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_dashboard/src/storefront/seo_consent_operations.dart';
import 'package:restoflow_dashboard/src/storefront/seo_consent_copy.dart';
import 'package:restoflow_dashboard/src/storefront/seo_consent_repository.dart';
import 'package:restoflow_dashboard/src/storefront/seo_consent_section.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

const _scope = SeoConsentOperationScope(
  membershipId: 'synthetic-owner',
  organizationId: 'org',
  restaurantId: 'restaurant',
);
late SeoConsentOperations _operations;

class _Journal implements SeoConsentJournal {
  final values = <String, Map<String, String>>{};
  @override
  Future<Map<String, String>> read(String scope) async =>
      Map.of(values[scope] ?? {});
  @override
  Future<void> write(String scope, String requestId, String value) async {
    values.putIfAbsent(scope, () => {})[requestId] = value;
  }

  @override
  Future<void> remove(String scope, String requestId) async {
    values[scope]?.remove(requestId);
  }
}

const _initial = SeoConsentState(
  consentEnabled: false,
  revision: '40',
  canManage: true,
);

class _Repo implements SeoConsentRepository {
  SeoConsentState state = _initial;
  SeoConsentOutcome readOutcome = SeoConsentOutcome.ok;
  SeoConsentOutcome saveOutcome = SeoConsentOutcome.ok;
  SeoConsentReconciliation? reconciliation;
  Completer<void>? readGate;
  Completer<void>? saveGate;
  bool failReadAfterSave = false;
  int reads = 0;
  int reconciles = 0;
  final writes = <SeoConsentMutation>[];

  @override
  Future<SeoConsentResult> read() async {
    reads++;
    await readGate?.future;
    if (failReadAfterSave && writes.isNotEmpty)
      return const SeoConsentResult(SeoConsentOutcome.unavailable);
    return SeoConsentResult(
      readOutcome,
      state: readOutcome == SeoConsentOutcome.ok ? state : null,
    );
  }

  @override
  Future<SeoConsentResult> save(SeoConsentMutation intent) async {
    writes.add(intent);
    await saveGate?.future;
    if (saveOutcome == SeoConsentOutcome.ok) {
      state = SeoConsentState(
        consentEnabled: intent.consentEnabled,
        revision: '41',
        canManage: true,
      );
      return SeoConsentResult(SeoConsentOutcome.ok, state: state);
    }
    return SeoConsentResult(saveOutcome);
  }

  @override
  Future<SeoConsentReconciliation> reconcile(SeoConsentMutation intent) async {
    reconciles++;
    return reconciliation ??
        const SeoConsentReconciliation(SeoConsentOutcome.unavailable);
  }
}

ThemeData _captureFontTheme(ThemeData theme) {
  ButtonStyle? buttonFont(ButtonStyle? style) => style?.copyWith(
    textStyle: WidgetStateProperty.resolveWith(
      (states) =>
          style.textStyle?.resolve(states)?.copyWith(fontFamily: 'QAArial'),
    ),
  );
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'QAArial'),
    filledButtonTheme: FilledButtonThemeData(
      style: buttonFont(theme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: buttonFont(theme.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: buttonFont(theme.textButtonTheme.style),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  _Repo repo, {
  String language = 'en',
  bool canManage = true,
  String scopeIdentity = 'synthetic-owner|org|restaurant|active',
  SeoConsentOperationScope operationScope = _scope,
  double width = 1200,
  double textScale = 1,
  bool settle = true,
}) async {
  final theme = restoflowLightBrandTheme();
  tester.view.physicalSize = Size(width, 2500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [seoConsentOperationsProvider.overrideWithValue(_operations)],
      child: MaterialApp(
        theme: Platform.environment['BIZBOT_SEO_CONSENT_CAPTURE_DIR'] != null
            ? _captureFontTheme(theme)
            : theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        locale: Locale(language),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: RepaintBoundary(
                key: const Key('capture'),
                child: SeoConsentSection(
                  repository: repo,
                  operationScope: operationScope,
                  canManage: canManage,
                  scopeIdentity: scopeIdentity,
                  restaurantName: 'QA — Synthetic restaurant',
                  mutationId: () => '157bc841-5b3d-4e42-b551-7ad00c6a8a19',
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

SwitchListTile _toggle(WidgetTester tester) =>
    tester.widget(find.byKey(const Key('seo-consent-toggle')));

Future<void> _tap(WidgetTester tester, String key, {bool settle = true}) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['BIZBOT_SEO_CONSENT_CAPTURE_DIR'];
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
  setUp(() => _operations = SeoConsentOperations(_Journal()));
  setUpAll(() async {
    if (Platform.environment['BIZBOT_SEO_CONSENT_CAPTURE_DIR'] == null) return;
    for (final entry in {
      'QAArial': Platform.environment['BIZBOT_QA_TEXT_FONT'],
      'MaterialIcons': Platform.environment['BIZBOT_QA_ICON_FONT'],
    }.entries) {
      if (entry.value == null) throw StateError('Capture font path required');
      final bytes = await File(entry.value!).readAsBytes();
      await (FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  testWidgets(
    'default OFF is authoritative; changing a draft never writes before explicit Save',
    (tester) async {
      final repo = _Repo();
      await _pump(tester, repo);
      expect(_toggle(tester).value, false);
      expect(repo.writes, isEmpty);
      await _tap(tester, 'seo-consent-toggle');
      expect(find.text(SeoConsentCopy('en').dirty), findsOneWidget);
      expect(repo.writes, isEmpty);
      await _tap(tester, 'seo-consent-save');
      expect(repo.writes.single.consentEnabled, true);
      expect(repo.writes.single.expectedRevision, '40');
      expect(repo.reads, 2);
      expect(_toggle(tester).value, true);
      expect(find.text(SeoConsentCopy('en').saved), findsOneWidget);
      expect(find.text(SeoConsentCopy('en').notOperational), findsOneWidget);
    },
  );

  testWidgets('revocation sends OFF with the confirmed revision', (
    tester,
  ) async {
    final repo = _Repo()
      ..state = const SeoConsentState(
        consentEnabled: true,
        revision: '80',
        canManage: true,
      );
    await _pump(tester, repo);
    await _tap(tester, 'seo-consent-toggle');
    await _tap(tester, 'seo-consent-save');
    expect(repo.writes.single.consentEnabled, false);
    expect(repo.writes.single.expectedRevision, '80');
    expect(_toggle(tester).value, false);
  });

  for (final outcome in [
    SeoConsentOutcome.unavailable,
    SeoConsentOutcome.denied,
    SeoConsentOutcome.notFound,
  ]) {
    testWidgets('$outcome read exposes no inferred state or usable Save', (
      tester,
    ) async {
      final gate = Completer<void>();
      final repo = _Repo()
        ..readGate = gate
        ..readOutcome = outcome;
      await _pump(tester, repo, settle: false);
      expect(
        find.byKey(const Key('seo-consent-settings-loading')),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNothing);
      expect(repo.writes, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('seo-consent-save')))
            .onPressed,
        isNull,
      );
    });
  }

  for (final advisory in [true, false]) {
    testWidgets(
      'both advisory gate and server capability required ($advisory)',
      (tester) async {
        final repo = _Repo()
          ..state = SeoConsentState(
            consentEnabled: true,
            revision: '40',
            canManage: !advisory,
          );
        await _pump(tester, repo, canManage: advisory);
        expect(_toggle(tester).value, true);
        expect(_toggle(tester).onChanged, isNull);
        expect(find.text(SeoConsentCopy('en').denied), findsOneWidget);
        expect(repo.writes, isEmpty);
      },
    );
  }

  testWidgets(
    'one write at a time and receipt is followed by authoritative readback',
    (tester) async {
      final gate = Completer<void>();
      final repo = _Repo()..saveGate = gate;
      await _pump(tester, repo);
      await _tap(tester, 'seo-consent-toggle');
      await _tap(tester, 'seo-consent-save', settle: false);
      expect(_toggle(tester).onChanged, isNull);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('seo-consent-save')))
            .onPressed,
        isNull,
      );
      expect(repo.writes, hasLength(1));
      gate.complete();
      await tester.pumpAndSettle();
      expect(repo.reads, 2);
      expect(repo.writes, hasLength(1));
    },
  );

  for (final outcome in [
    SeoConsentOutcome.revisionConflict,
    SeoConsentOutcome.requestConflict,
    SeoConsentOutcome.invalidRequest,
    SeoConsentOutcome.denied,
    SeoConsentOutcome.notFound,
  ]) {
    testWidgets('$outcome Save keeps the operation until a terminal receipt', (
      tester,
    ) async {
      final repo = _Repo()..saveOutcome = outcome;
      await _pump(tester, repo);
      await _tap(tester, 'seo-consent-toggle');
      await _tap(tester, 'seo-consent-save');
      expect(_toggle(tester).onChanged, isNull);
      expect(repo.writes, hasLength(1));
      expect(find.byKey(const Key('seo-consent-reload')), findsNothing);
      repo.reconciliation = const SeoConsentReconciliation(
        SeoConsentOutcome.revisionConflict,
        mutationState: SeoConsentMutationState.refused,
        current: _initial,
      );
      await _tap(tester, 'seo-consent-check-save');
      await _tap(tester, 'seo-consent-reload');
      expect(_toggle(tester).value, false);
      expect(repo.reads, 2);
      expect(repo.writes, hasLength(1));
    });
  }

  testWidgets(
    'uncertain commit freezes all drafts; receipt check never writes',
    (tester) async {
      final repo = _Repo()..saveOutcome = SeoConsentOutcome.unavailable;
      await _pump(tester, repo);
      await _tap(tester, 'seo-consent-toggle');
      await _tap(tester, 'seo-consent-save');
      await tester.pump(const Duration(seconds: 30));
      expect(_toggle(tester).onChanged, isNull);
      expect(repo.writes, hasLength(1));
      expect(repo.reconciles, 0);
      expect(find.byKey(const Key('seo-consent-reload')), findsNothing);
      expect(find.byKey(const Key('seo-consent-resend')), findsNothing);
      repo.reconciliation = const SeoConsentReconciliation(
        SeoConsentOutcome.ok,
        mutationState: SeoConsentMutationState.committed,
        current: SeoConsentState(
          consentEnabled: false,
          revision: '42',
          canManage: true,
        ),
      );
      await _tap(tester, 'seo-consent-check-save');
      expect(repo.writes, hasLength(1));
      expect(repo.reconciles, 1);
      // A later revocation wins over the original successful ON receipt.
      expect(_toggle(tester).value, false);
      expect(find.byKey(const Key('seo-consent-check-save')), findsNothing);
    },
  );

  testWidgets(
    'only not-recorded receipt permits explicit same UUID/CAS resend',
    (tester) async {
      final repo = _Repo()..saveOutcome = SeoConsentOutcome.unavailable;
      await _pump(tester, repo);
      await _tap(tester, 'seo-consent-toggle');
      await _tap(tester, 'seo-consent-save');
      await _tap(tester, 'seo-consent-check-save');
      expect(find.byKey(const Key('seo-consent-resend')), findsNothing);
      repo.reconciliation = const SeoConsentReconciliation(
        SeoConsentOutcome.ok,
        mutationState: SeoConsentMutationState.notRecorded,
        current: _initial,
      );
      await _tap(tester, 'seo-consent-check-save');
      expect(find.byKey(const Key('seo-consent-save')), findsNothing);
      expect(find.byKey(const Key('seo-consent-reload')), findsNothing);
      expect(_toggle(tester).onChanged, isNull);
      repo.saveOutcome = SeoConsentOutcome.ok;
      await _tap(tester, 'seo-consent-resend');
      expect(repo.writes, hasLength(2));
      expect(identical(repo.writes.first, repo.writes.last), true);
    },
  );

  testWidgets('not-recorded does not cancel a late original commit', (
    tester,
  ) async {
    final repo = _Repo()..saveOutcome = SeoConsentOutcome.unavailable;
    await _pump(tester, repo);
    await _tap(tester, 'seo-consent-toggle');
    await _tap(tester, 'seo-consent-save');
    repo.reconciliation = const SeoConsentReconciliation(
      SeoConsentOutcome.ok,
      mutationState: SeoConsentMutationState.notRecorded,
      current: _initial,
    );
    await _tap(tester, 'seo-consent-check-save');
    expect(find.byKey(const Key('seo-consent-reload')), findsNothing);
    repo.reconciliation = const SeoConsentReconciliation(
      SeoConsentOutcome.ok,
      mutationState: SeoConsentMutationState.committed,
      current: SeoConsentState(
        consentEnabled: true,
        revision: '41',
        canManage: true,
      ),
    );
    await _tap(tester, 'seo-consent-check-save');
    expect(_toggle(tester).value, true);
    expect(repo.writes, hasLength(1));
  });

  testWidgets('recorded refusal resolves uncertainty without retry', (
    tester,
  ) async {
    final repo = _Repo()..saveOutcome = SeoConsentOutcome.unavailable;
    await _pump(tester, repo);
    await _tap(tester, 'seo-consent-toggle');
    await _tap(tester, 'seo-consent-save');
    repo.reconciliation = const SeoConsentReconciliation(
      SeoConsentOutcome.revisionConflict,
      mutationState: SeoConsentMutationState.refused,
      current: _initial,
    );
    await _tap(tester, 'seo-consent-check-save');
    expect(find.text(SeoConsentCopy('en').conflict), findsOneWidget);
    expect(find.byKey(const Key('seo-consent-resend')), findsNothing);
    await _tap(tester, 'seo-consent-reload');
    expect(repo.writes, hasLength(1));
  });

  testWidgets(
    'denied reconciliation cannot free an uncertain request for a new write',
    (tester) async {
      final repo = _Repo()..saveOutcome = SeoConsentOutcome.unavailable;
      await _pump(tester, repo);
      await _tap(tester, 'seo-consent-toggle');
      await _tap(tester, 'seo-consent-save');
      repo.reconciliation = const SeoConsentReconciliation(
        SeoConsentOutcome.denied,
      );
      await _tap(tester, 'seo-consent-check-save');
      expect(
        find.textContaining(SeoConsentCopy('en').uncertain),
        findsOneWidget,
      );
      expect(find.byKey(const Key('seo-consent-reload')), findsNothing);
      expect(find.byKey(const Key('seo-consent-resend')), findsNothing);
      expect(repo.writes, hasLength(1));
    },
  );

  testWidgets(
    'confirmed write plus failed readback never permits a second save',
    (tester) async {
      final repo = _Repo()..failReadAfterSave = true;
      await _pump(tester, repo);
      await _tap(tester, 'seo-consent-toggle');
      await _tap(tester, 'seo-consent-save');
      expect(
        find.text(SeoConsentCopy('en').savedReadUnavailable),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsNothing);
      expect(repo.writes, hasLength(1));
      repo.failReadAfterSave = false;
      await _tap(tester, 'seo-consent-reload');
      expect(_toggle(tester).value, true);
    },
  );

  testWidgets(
    'restaurant change drops draft and ignores late previous response',
    (tester) async {
      final gate = Completer<void>();
      final old = _Repo()..readGate = gate;
      await _pump(tester, old, settle: false);
      final next = _Repo()
        ..state = const SeoConsentState(
          consentEnabled: true,
          revision: '88',
          canManage: true,
        );
      await _pump(
        tester,
        next,
        scopeIdentity: 'owner|another-org|another-restaurant|active',
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(_toggle(tester).value, true);
      await _tap(tester, 'seo-consent-toggle');
      await _tap(tester, 'seo-consent-save');
      expect(next.writes.single.expectedRevision, '88');
      expect(old.writes, isEmpty);
    },
  );

  testWidgets(
    'scope identity change clears draft even with the same injected repository',
    (tester) async {
      final repo = _Repo();
      await _pump(tester, repo);
      await _tap(tester, 'seo-consent-toggle');
      await _pump(
        tester,
        repo,
        scopeIdentity: 'other-membership|org|restaurant|active',
      );
      expect(_toggle(tester).value, false);
      expect(repo.reads, 2);
      expect(repo.writes, isEmpty);
    },
  );

  testWidgets(
    'late old-restaurant save cannot read back into the new restaurant draft',
    (tester) async {
      final gate = Completer<void>();
      final old = _Repo()..saveGate = gate;
      await _pump(tester, old);
      await _tap(tester, 'seo-consent-toggle');
      await _tap(tester, 'seo-consent-save', settle: false);
      final next = _Repo();
      await _pump(
        tester,
        next,
        scopeIdentity: 'other-owner|other-org|other-restaurant|active',
        operationScope: const SeoConsentOperationScope(
          membershipId: 'other-owner',
          organizationId: 'other-org',
          restaurantId: 'other-restaurant',
        ),
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(_toggle(tester).value, false);
      expect(old.reads, 1);
      expect(next.reads, 1);
      expect(next.writes, isEmpty);
      expect(find.text(SeoConsentCopy('en').saved), findsNothing);
    },
  );

  testWidgets(
    'multiple durable operations stay frozen between exact receipt checks',
    (tester) async {
      final journal = _Journal();
      final ids = [
        '11111111-1111-4111-8111-111111111111',
        '22222222-2222-4222-8222-222222222222',
      ];
      journal.values[_scope.key] = {
        for (var index = 0; index < ids.length; index++)
          ids[index]: jsonEncode({
            'version': 1,
            'id': ids[index],
            'expected_revision': '40',
            'consent_enabled': index == 0,
          }),
      };
      _operations = SeoConsentOperations(journal);
      final repo = _Repo()
        ..reconciliation = const SeoConsentReconciliation(
          SeoConsentOutcome.ok,
          mutationState: SeoConsentMutationState.committed,
          current: _initial,
        );
      await _pump(tester, repo);
      expect(find.byKey(const Key('seo-consent-save')), findsNothing);
      expect(_toggle(tester).value, true);
      await _tap(tester, 'seo-consent-check-save');
      expect(journal.values[_scope.key]!.keys, [ids[1]]);
      expect(_toggle(tester).value, false);
      expect(_toggle(tester).onChanged, isNull);
      expect(find.byKey(const Key('seo-consent-save')), findsNothing);
      expect(find.byKey(const Key('seo-consent-check-save')), findsOneWidget);
      await _tap(tester, 'seo-consent-check-save');
      expect(journal.values[_scope.key], isEmpty);
      expect(_toggle(tester).onChanged, isNotNull);
      expect(repo.writes, isEmpty);
    },
  );

  for (final language in ['ar', 'he', 'en']) {
    for (final width in [390.0, 1440.0]) {
      for (final textScale in [1.0, 2.0]) {
        testWidgets(
          '$language ${width.toInt()}px ${textScale}x is accessible, optional and clearly future-only',
          (tester) async {
            final semantics = tester.ensureSemantics();
            try {
              final repo = _Repo();
              final copy = SeoConsentCopy(language);
              await _pump(
                tester,
                repo,
                language: language,
                width: width,
                textScale: textScale,
              );
              final section = find.byKey(
                const Key('seo-consent-settings-section'),
              );
              expect(
                Directionality.of(tester.element(section)),
                language == 'en' ? TextDirection.ltr : TextDirection.rtl,
              );
              for (final text in [
                copy.label,
                copy.scope,
                copy.notOperational,
                copy.help,
                copy.withdrawal,
                copy.independent,
              ]) {
                expect(find.text(text), findsOneWidget);
              }
              if (language == 'ar')
                expect(copy.label, 'السماح بظهور منيو المطعم في محركات البحث');
              await tester.ensureVisible(
                find.byKey(const Key('seo-consent-toggle')),
              );
              await tester.pumpAndSettle();
              final data = tester
                  .getSemantics(find.byKey(const Key('seo-consent-toggle')))
                  .getSemanticsData();
              expect(data.label, contains(copy.label));
              expect(data.flagsCollection.isToggled, ui.Tristate.isFalse);
              expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
              expect(data.hasAction(ui.SemanticsAction.tap), true);
              for (final text
                  in find
                      .descendant(of: section, matching: find.byType(RichText))
                      .evaluate()) {
                expect(
                  (text.renderObject! as RenderParagraph).didExceedMaxLines,
                  false,
                );
              }
              expect(repo.writes, isEmpty);
              expect(tester.takeException(), isNull);
              await _capture(
                tester,
                '$language-${width.toInt()}-${textScale}x-card',
              );
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }
    testWidgets(
      '$language uncertainty is visible and preserves no automatic retry',
      (tester) async {
        final repo = _Repo()..saveOutcome = SeoConsentOutcome.unavailable;
        await _pump(tester, repo, language: language, width: 390);
        await _tap(tester, 'seo-consent-toggle');
        await _tap(tester, 'seo-consent-save');
        expect(find.text(SeoConsentCopy(language).uncertain), findsOneWidget);
        expect(
          find.text(SeoConsentCopy(language).notOperational),
          findsOneWidget,
        );
        await _capture(tester, '$language-390-uncertain');
        expect(repo.writes, hasLength(1));
      },
    );
  }
}
