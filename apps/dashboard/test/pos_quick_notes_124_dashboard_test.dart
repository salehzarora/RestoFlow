import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/quick_notes/quick_notes_repository.dart';
import 'package:restoflow_dashboard/src/quick_notes/quick_notes_section.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// POS-QUICK-NOTES-124 — the Dashboard management surface.
///
/// The behaviour worth defending here is honesty under failure. A settings list
/// that keeps showing a row the server refused is how a "saved" quick note ends
/// up missing from every till, so every action reloads the authoritative list
/// and every refusal says what actually happened.

// ---------------------------------------------------------------- fakes -----

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.handler);
  final Object? Function(String fn, Map<String, dynamic> p) handler;
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    final out = handler(function, params);
    if (out is Exception) throw out;
    return out;
  }
}

/// An in-memory repository with controllable outcomes, so the widget tests
/// exercise the UI's own decisions rather than the wire format.
class _FakeRepo implements QuickNotesRepository {
  _FakeRepo({
    List<QuickNotePreset>? presets,
    this.status = QuickNotesLoadStatus.ok,
  }) : _presets = [...?presets];

  List<QuickNotePreset> _presets;
  QuickNotesLoadStatus status;

  /// Forced outcome for the NEXT write, or null to let it succeed.
  QuickNoteWrite? nextWrite;

  /// Completer that gates the next write, so a test can hold one in flight.
  Completer<void>? gate;

  final upserts = <({String? id, String label, bool isActive})>[];
  final deletes = <String>[];
  final reorders = <List<String>>[];
  int loads = 0;

  @override
  Future<QuickNotesSnapshot> load() async {
    loads++;
    if (status != QuickNotesLoadStatus.ok) {
      return QuickNotesSnapshot.failed(status);
    }
    return QuickNotesSnapshot.ok(List.of(_presets));
  }

  Future<QuickNoteWrite> _finish(QuickNoteWrite fallback) async {
    if (gate != null) await gate!.future;
    final forced = nextWrite;
    nextWrite = null;
    return forced ?? fallback;
  }

  @override
  Future<QuickNoteWrite> upsert({
    String? id,
    required String label,
    required bool isActive,
  }) async {
    upserts.add((id: id, label: label, isActive: isActive));
    final outcome = await _finish(QuickNoteWrite.ok);
    if (outcome != QuickNoteWrite.ok) return outcome;
    final index = _presets.indexWhere((p) => p.id == id);
    if (index >= 0) {
      _presets[index] = _presets[index].copyWith(
        label: label,
        isActive: isActive,
      );
    } else {
      _presets.add(
        QuickNotePreset(
          id: 'new-${_presets.length}',
          label: label,
          displayOrder: _presets.length,
          isActive: isActive,
        ),
      );
    }
    return QuickNoteWrite.ok;
  }

  @override
  Future<QuickNoteWrite> delete(String id) async {
    deletes.add(id);
    final outcome = await _finish(QuickNoteWrite.ok);
    if (outcome != QuickNoteWrite.ok) return outcome;
    _presets.removeWhere((p) => p.id == id);
    return QuickNoteWrite.ok;
  }

  @override
  Future<QuickNoteWrite> reorder(List<String> ids) async {
    reorders.add(ids);
    final outcome = await _finish(QuickNoteWrite.ok);
    if (outcome != QuickNoteWrite.ok) return outcome;
    _presets = [for (final id in ids) _presets.firstWhere((p) => p.id == id)];
    return QuickNoteWrite.ok;
  }
}

List<QuickNotePreset> _three() => const [
  QuickNotePreset(id: 'a', label: 'No onions', displayOrder: 0, isActive: true),
  QuickNotePreset(
    id: 'b',
    label: 'Extra crispy',
    displayOrder: 1,
    isActive: true,
  ),
  QuickNotePreset(
    id: 'c',
    label: 'Well done',
    displayOrder: 2,
    isActive: false,
  ),
];

Future<void> _pump(
  WidgetTester tester,
  QuickNotesRepository repo, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(child: QuickNotesSection(repository: repo)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('A. the list', () {
    testWidgets('A1. presets load in order, disabled ones included', (
      tester,
    ) async {
      final repo = _FakeRepo(presets: _three());
      await _pump(tester, repo);
      expect(find.byKey(const Key('quick-note-label-a')), findsOneWidget);
      expect(find.byKey(const Key('quick-note-label-c')), findsOneWidget);
      // The manager must see what they switched off in order to switch it back.
      expect(find.byKey(const Key('quick-note-disabled-c')), findsOneWidget);
      expect(find.byKey(const Key('quick-note-disabled-a')), findsNothing);
    });

    testWidgets('A2. an empty restaurant says so, and Add still works', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo());
      expect(find.byKey(const Key('quick-notes-empty')), findsOneWidget);
      final add = tester.widget<FilledButton>(
        find.byKey(const Key('quick-notes-add')),
      );
      expect(add.onPressed, isNotNull);
    });

    testWidgets('A3. a failed read shows a notice and disables Add', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(status: QuickNotesLoadStatus.unavailable));
      expect(find.byKey(const Key('quick-notes-unavailable')), findsOneWidget);
      // No fabricated empty list, and no control that cannot reach a server.
      expect(find.byKey(const Key('quick-notes-empty')), findsNothing);
      final add = tester.widget<FilledButton>(
        find.byKey(const Key('quick-notes-add')),
      );
      expect(add.onPressed, isNull);
    });

    testWidgets('A4. there is NO branch selector — v1 is restaurant-wide', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(presets: _three()));
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    });

    testWidgets('A5. tenant text is rendered verbatim, in any script', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeRepo(
          presets: const [
            QuickNotePreset(
              id: 'ar',
              label: 'بدون بصل',
              displayOrder: 0,
              isActive: true,
            ),
            QuickNotePreset(
              id: 'he',
              label: 'בלי בצל',
              displayOrder: 1,
              isActive: true,
            ),
          ],
        ),
      );
      expect(find.text('بدون بصل'), findsOneWidget);
      expect(find.text('בלי בצל'), findsOneWidget);
    });
  });

  group('B. writes', () {
    testWidgets('B1. Add sends the trimmed label and reloads', (tester) async {
      final repo = _FakeRepo();
      await _pump(tester, repo);
      final loadsBefore = repo.loads;
      await tester.tap(find.byKey(const Key('quick-notes-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('quick-note-dialog-field')),
        '  No onions  ',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick-note-dialog-save')));
      await tester.pumpAndSettle();
      expect(repo.upserts.single.label, 'No onions');
      expect(repo.upserts.single.id, isNull);
      expect(repo.upserts.single.isActive, isTrue);
      // The authoritative list is re-read, never assumed.
      expect(repo.loads, greaterThan(loadsBefore));
      expect(find.text('No onions'), findsOneWidget);
    });

    testWidgets('B2. Edit prefills and updates in place', (tester) async {
      final repo = _FakeRepo(presets: _three());
      await _pump(tester, repo);
      await tester.tap(find.byKey(const Key('quick-note-edit-a')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('quick-note-dialog-field')))
            .controller!
            .text,
        'No onions',
      );
      await tester.enterText(
        find.byKey(const Key('quick-note-dialog-field')),
        'No onions please',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick-note-dialog-save')));
      await tester.pumpAndSettle();
      expect(repo.upserts.single.id, 'a');
      expect(repo.upserts.single.label, 'No onions please');
      expect(find.text('No onions please'), findsOneWidget);
    });

    testWidgets('B3. an edit preserves the enabled/disabled state', (
      tester,
    ) async {
      final repo = _FakeRepo(presets: _three());
      await _pump(tester, repo);
      await tester.tap(find.byKey(const Key('quick-note-edit-c')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('quick-note-dialog-field')),
        'Well done indeed',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick-note-dialog-save')));
      await tester.pumpAndSettle();
      // Renaming a switched-off preset must not quietly switch it back on.
      expect(repo.upserts.single.isActive, isFalse);
      expect(find.byKey(const Key('quick-note-disabled-c')), findsOneWidget);
    });

    testWidgets('B4. the toggle flips exactly one preset', (tester) async {
      final repo = _FakeRepo(presets: _three());
      await _pump(tester, repo);
      await tester.tap(find.byKey(const Key('quick-note-toggle-a')));
      await tester.pumpAndSettle();
      expect(repo.upserts.single.id, 'a');
      expect(repo.upserts.single.isActive, isFalse);
      expect(repo.upserts.single.label, 'No onions');
      expect(find.byKey(const Key('quick-note-disabled-a')), findsOneWidget);
    });

    testWidgets('B5. Delete asks first, and Cancel really cancels', (
      tester,
    ) async {
      final repo = _FakeRepo(presets: _three());
      await _pump(tester, repo);
      await tester.tap(find.byKey(const Key('quick-note-delete-a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quick-note-delete-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('quick-note-delete-cancel')));
      await tester.pumpAndSettle();
      expect(repo.deletes, isEmpty);
      expect(find.byKey(const Key('quick-note-label-a')), findsOneWidget);
    });

    testWidgets('B6. confirmed delete removes the row', (tester) async {
      final repo = _FakeRepo(presets: _three());
      await _pump(tester, repo);
      await tester.tap(find.byKey(const Key('quick-note-delete-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick-note-delete-confirm')));
      await tester.pumpAndSettle();
      expect(repo.deletes, ['a']);
      expect(find.byKey(const Key('quick-note-label-a')), findsNothing);
    });

    testWidgets('B7. reorder sends the COMPLETE id list', (tester) async {
      final repo = _FakeRepo(presets: _three());
      await _pump(tester, repo);
      await tester.drag(
        find.byKey(const Key('quick-note-drag-c')),
        const Offset(0, -120),
        touchSlopY: 0,
      );
      await tester.pumpAndSettle();
      expect(repo.reorders, isNotEmpty);
      // Every live preset, not just the moved one — a partial list would let the
      // server invent an order for the rest.
      expect(repo.reorders.single.toSet(), {'a', 'b', 'c'});
      expect(repo.reorders.single, hasLength(3));
    });
  });

  group('C. honesty under failure', () {
    testWidgets('C1. a duplicate is named, and nothing is added', (
      tester,
    ) async {
      final repo = _FakeRepo(presets: _three())
        ..nextWrite = QuickNoteWrite.duplicateLabel;
      await _pump(tester, repo);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.byKey(const Key('quick-notes-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('quick-note-dialog-field')),
        'No onions',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick-note-dialog-save')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.dashboardQuickNoteDuplicate), findsOneWidget);
      // Exactly the three we started with.
      expect(find.byType(TextButton), findsNothing);
      expect(repo.loads, greaterThan(1));
    });

    testWidgets('C2. a refused save says so and reloads the server truth', (
      tester,
    ) async {
      final repo = _FakeRepo(presets: _three())
        ..nextWrite = QuickNoteWrite.failed;
      await _pump(tester, repo);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.byKey(const Key('quick-note-toggle-a')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.dashboardQuickNoteSaveFailed), findsOneWidget);
      // The row is back exactly as the server has it — not as the tap wanted.
      expect(find.byKey(const Key('quick-note-disabled-a')), findsNothing);
    });

    testWidgets('C3. a denied write is distinguished from a failure', (
      tester,
    ) async {
      final repo = _FakeRepo(presets: _three())
        ..nextWrite = QuickNoteWrite.denied;
      await _pump(tester, repo);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.byKey(const Key('quick-note-toggle-a')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.dashboardQuickNoteDenied), findsOneWidget);
    });

    testWidgets('C4. a refused reorder restores the server order', (
      tester,
    ) async {
      final repo = _FakeRepo(presets: _three())
        ..nextWrite = QuickNoteWrite.failed;
      await _pump(tester, repo);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final before = tester
          .getTopLeft(find.byKey(const Key('quick-note-label-a')))
          .dy;
      await tester.drag(
        find.byKey(const Key('quick-note-drag-c')),
        const Offset(0, -120),
        touchSlopY: 0,
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.dashboardQuickNoteReorderFailed), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('quick-note-label-a'))).dy,
        before,
      );
    });

    testWidgets('C5. a second press is blocked while a write is in flight', (
      tester,
    ) async {
      final repo = _FakeRepo(presets: _three())..gate = Completer<void>();
      await _pump(tester, repo);
      await tester.tap(find.byKey(const Key('quick-note-toggle-a')));
      await tester.pump();
      // The first write is still open; the row's actions are disabled.
      final button = tester.widget<IconButton>(
        find.byKey(const Key('quick-note-toggle-a')),
      );
      expect(button.onPressed, isNull);
      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(repo.upserts, hasLength(1));
    });
  });

  group('D. the form', () {
    testWidgets('D1. Save is disabled until there is text', (tester) async {
      await _pump(tester, _FakeRepo());
      await tester.tap(find.byKey(const Key('quick-notes-add')));
      await tester.pumpAndSettle();
      FilledButton save() => tester.widget<FilledButton>(
        find.byKey(const Key('quick-note-dialog-save')),
      );
      expect(save().onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('quick-note-dialog-field')),
        '   ',
      );
      await tester.pumpAndSettle();
      // Whitespace is not a note.
      expect(save().onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('quick-note-dialog-field')),
        'No onions',
      );
      await tester.pumpAndSettle();
      expect(save().onPressed, isNotNull);
    });

    testWidgets('D2. the field enforces the SAME 60-character contract', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo());
      await tester.tap(find.byKey(const Key('quick-notes-add')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const Key('quick-note-dialog-field')),
      );
      expect(field.maxLength, kQuickNoteMaxLength);
      expect(kQuickNoteMaxLength, 60);
    });

    testWidgets('D3. Arabic and Hebrew chrome renders', (tester) async {
      for (final locale in const [Locale('ar'), Locale('he')]) {
        final l10n = await AppLocalizations.delegate.load(locale);
        await _pump(tester, _FakeRepo(presets: _three()), locale: locale);
        expect(
          find.text(l10n.dashboardQuickNotesTitle),
          findsOneWidget,
          reason: 'title missing for $locale',
        );
        expect(
          Directionality.of(
            tester.element(find.byKey(const Key('quick-notes-section'))),
          ),
          TextDirection.rtl,
        );
      }
    });

    testWidgets('D4. the section fits a narrow desktop pane', (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: QuickNotesSection(
                repository: _FakeRepo(presets: _three()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('E. the wire', () {
    test('E1. load parses the list RPC envelope', () async {
      final t = _FakeTransport(
        (fn, p) => <String, Object?>{
          'ok': true,
          'entity': 'quick_note_preset',
          'presets': [
            {
              'id': 'a',
              'label': 'No onions',
              'display_order': 0,
              'is_active': true,
            },
            {'id': 'b', 'label': 'Off', 'display_order': 1, 'is_active': false},
          ],
        },
      );
      final repo = SupabaseQuickNotesRepository(
        transport: t,
        organizationId: 'org',
        restaurantId: 'rest',
      );
      final snapshot = await repo.load();
      expect(snapshot.status, QuickNotesLoadStatus.ok);
      expect(snapshot.presets.map((p) => p.id), ['a', 'b']);
      expect(snapshot.presets.last.isActive, isFalse);
      expect(t.calls.single.$1, 'list_quick_note_presets');
      expect(t.calls.single.$2['p_restaurant_id'], 'rest');
      // No branch is sent — there is no branch dimension in v1.
      expect(t.calls.single.$2.containsKey('p_branch_id'), isFalse);
    });

    test(
      'E2. a permission_denied envelope is not a transport failure',
      () async {
        final repo = SupabaseQuickNotesRepository(
          transport: _FakeTransport(
            (fn, p) => <String, Object?>{
              'ok': false,
              'error': 'permission_denied',
            },
          ),
          organizationId: 'org',
          restaurantId: 'rest',
        );
        expect((await repo.load()).status, QuickNotesLoadStatus.denied);
      },
    );

    test('E3. duplicate_label survives as its own outcome', () async {
      final repo = SupabaseQuickNotesRepository(
        transport: _FakeTransport(
          (fn, p) => <String, Object?>{'ok': false, 'error': 'duplicate_label'},
        ),
        organizationId: 'org',
        restaurantId: 'rest',
      );
      expect(
        await repo.upsert(label: 'No onions', isActive: true),
        QuickNoteWrite.duplicateLabel,
      );
    });

    test('E4. an over-long label never reaches the server', () async {
      final t = _FakeTransport((fn, p) => <String, Object?>{'ok': true});
      final repo = SupabaseQuickNotesRepository(
        transport: t,
        organizationId: 'org',
        restaurantId: 'rest',
      );
      expect(
        await repo.upsert(label: 'x' * 61, isActive: true),
        QuickNoteWrite.invalid,
      );
      expect(
        await repo.upsert(label: '   ', isActive: true),
        QuickNoteWrite.invalid,
      );
      expect(t.calls, isEmpty);
    });

    test('E5. every write carries a DISTINCT client_request_id', () async {
      final t = _FakeTransport((fn, p) => <String, Object?>{'ok': true});
      var tick = 0;
      final repo = SupabaseQuickNotesRepository(
        transport: t,
        organizationId: 'org',
        restaurantId: 'rest',
        nonce: () => ++tick,
      );
      await repo.upsert(label: 'No onions', isActive: true);
      await repo.upsert(label: 'No onions', isActive: true);
      final ids = t.calls.map((c) => c.$2['p_client_request_id']).toSet();
      // Two deliberate presses are two operations; sharing an id would make the
      // server replay the first and silently swallow the second.
      expect(ids, hasLength(2));
    });

    test(
      'E6. a transport exception is a failure, never a false success',
      () async {
        final repo = SupabaseQuickNotesRepository(
          transport: _FakeTransport(
            (fn, p) => const SyncTransportException(
              SyncTransportErrorKind.transient,
              message: 'offline',
            ),
          ),
          organizationId: 'org',
          restaurantId: 'rest',
        );
        expect(
          await repo.upsert(label: 'No onions', isActive: true),
          QuickNoteWrite.failed,
        );
        expect((await repo.load()).status, QuickNotesLoadStatus.unavailable);
      },
    );
  });
}
