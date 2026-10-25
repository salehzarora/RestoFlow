import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_section.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'storefront_content_section_test.dart' as fixture;

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('OFFLINE_BINDING_TEST');
}

class _GatedRepo extends fixture.ContentRepo {
  final gate = Completer<void>();
  @override
  Future<StorefrontContentWrite> saveContent(
    StorefrontContentAttempt attempt,
  ) async {
    await gate.future;
    return super.saveContent(attempt);
  }
}

class _GatedFirstReadRepo extends fixture.ContentRepo {
  final readGate = Completer<StorefrontContentRead>();
  var first = true;
  @override
  Future<StorefrontContentRead> readContent() {
    if (first) {
      first = false;
      return readGate.future;
    }
    return super.readContent();
  }
}

void main() {
  setUp(() => HttpOverrides.global = _NoNetwork());
  tearDown(() => HttpOverrides.global = null);
  testWidgets('unowned delayed read cannot enable an older profile version', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 12000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _GatedFirstReadRepo();
    final oldRead = await fixture.ContentRepo().readContent();
    final catalog = fixture.ContentCatalog();
    Widget app() => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: StorefrontContentSection(
            key: const Key('same-read-scope'),
            repository: repo,
            catalog: catalog,
            profileVersion: repo.version,
            savedBranchId: fixture.branch,
            onRefresh: () async => StorefrontContentRefresh(
              profileRead: true,
              mediaRead: true,
              version: repo.version,
              branchId: fixture.branch,
            ),
            onDraftChanged: (_) {},
            onBusyChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(app());
    await tester.pump();
    repo.version = 4;
    await tester.pumpWidget(app());
    await tester.pump();
    repo.readGate.complete(oldRead);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('content-hero-headline')), findsNothing);
    expect(find.byKey(const Key('content-save')), findsNothing);
    expect(
      find.text('Content could not be verified. Reload before editing.'),
      findsOneWidget,
    );
    expect(
      catalog.branches,
      isEmpty,
      reason: 'Stale unowned data must not start a catalog read',
    );
    await tester.tap(find.text('Reload saved content'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('content-hero-headline')))
          .enabled,
      isTrue,
    );
    expect(catalog.branches, [fixture.branch]);
    expect(repo.calls, isEmpty, reason: 'Recovery only rereads; no submit');
    expect(tester.takeException(), isNull);
  });
  for (final inFlight in [false, true]) {
    testWidgets(
      'binding replacement retains unresolved original intent; inFlight=$inFlight',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 12000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final first = inFlight ? _GatedRepo() : fixture.ContentRepo();
        first.status = inFlight
            ? StorefrontContentWriteStatus.ok
            : StorefrontContentWriteStatus.uncertain;
        final second = fixture.ContentRepo();
        final catalog = fixture.ContentCatalog();
        var refreshes = 0;
        Widget app(fixture.ContentRepo repo) => MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StorefrontContentSection(
                key: const Key('same-logical-scope'),
                repository: repo,
                catalog: catalog,
                profileVersion: repo.version,
                savedBranchId: fixture.branch,
                onRefresh: () async {
                  refreshes++;
                  return StorefrontContentRefresh(
                    profileRead: true,
                    mediaRead: true,
                    version: repo.version,
                    branchId: fixture.branch,
                  );
                },
                onDraftChanged: (_) {},
                onBusyChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpWidget(app(first));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('content-hero-headline')),
          'Original uncertain intent',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('content-save')));
        await tester.pump();
        VoidCallback? retainedRetry;
        if (!inFlight)
          retainedRetry = tester
              .widget<OutlinedButton>(
                find.byKey(const Key('content-retry-save')),
              )
              .onPressed;
        await tester.pumpWidget(app(second));
        await tester.pump();
        if (inFlight) {
          (first as _GatedRepo).gate.complete();
          await tester.pumpAndSettle();
        } else {
          retainedRetry!();
          await tester.pumpAndSettle();
        }
        final retry = find.byKey(const Key('content-retry-save'));
        expect(
          retry,
          findsOneWidget,
          reason: 'Original intent must not be discarded',
        );
        expect(tester.widget<OutlinedButton>(retry).onPressed, isNull);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('content-save')))
              .onPressed,
          isNull,
        );
        expect(first.calls.length, 1);
        expect(
          first.calls.single.document.json['hero_headline'],
          'Original uncertain intent',
        );
        expect(
          second.calls,
          isEmpty,
          reason: 'Never replay original request on replacement transport',
        );
        expect(
          refreshes,
          0,
          reason: 'Late old completion must not refresh the replacement editor',
        );
        expect(find.byKey(const Key('content-resume-read')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
