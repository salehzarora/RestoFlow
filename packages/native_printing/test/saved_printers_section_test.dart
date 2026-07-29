import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';

/// WIFI-PRINTER-PROFILE-LISTS-001 — regressions on the SHARED saved-printer
/// widget itself, so neither app can re-introduce the two defects that were
/// found the hard way while building the POS half:
///
///  1. disposing the dialog's text controllers when the `showDialog` future
///     completed tore them down while the exit animation still rebuilt the
///     fields (`A TextEditingController was used after being disposed`);
///  2. an indeterminate `CircularProgressIndicator` in the loading row meant an
///     enclosing settings sheet never settled — it hung four unrelated POS
///     `device_settings_test` cases with `pumpAndSettle timed out`.

const _strings = SavedPrintersStrings(
  heading: 'Saved printers',
  addAction: 'Add printer',
  editAction: 'Edit printer',
  deleteAction: 'Delete printer',
  activeBadge: 'Active',
  defaultName: 'Saved printer',
  nameLabel: 'Printer name',
  hostLabel: 'Host',
  portLabel: 'Port',
  empty: 'No saved printers',
  loading: 'Loading saved printers',
  loadFailure: 'Could not load saved printers',
  retryAction: 'Retry',
  deleteConfirmTitle: 'Delete printer?',
  deleteConfirmBody: _body,
  deleteActiveWarning: 'This is the active printer.',
  duplicateError: 'Already saved',
  nameRequired: 'Enter a name',
  invalidHost: 'Invalid host',
  invalidPort: 'Invalid port',
  saveAction: 'Save',
  cancelAction: 'Cancel',
);

String _body(String name) => '$name will be removed';

final _profile = NetworkPrinterProfile(
  id: 'p1',
  name: 'Kitchen',
  config: const NetworkPrinterConfig(host: '10.0.0.14', port: 9100),
);

/// Pumps the section with recording callbacks; nothing is persisted.
Future<List<String>> _pump(
  WidgetTester tester, {
  List<NetworkPrinterProfile> profiles = const <NetworkPrinterProfile>[],
  String? activeId,
  bool loading = false,
  bool failed = false,
  SavedPrinterSaveResult addResult = SavedPrinterSaveResult.saved,
}) async {
  final calls = <String>[];
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SavedPrintersSection(
            strings: _strings,
            profiles: profiles,
            activeId: activeId,
            loading: loading,
            failed: failed,
            onRetry: () => calls.add('retry'),
            onSelect: (id) async => calls.add('select:$id'),
            onAdd: (name, config) async {
              calls.add('add:$name:${config.host}:${config.port}');
              return addResult;
            },
            onEdit: (p) async {
              calls.add('edit:${p.id}:${p.config.host}');
              return SavedPrinterSaveResult.saved;
            },
            onRemove: (id) async => calls.add('remove:$id'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

void main() {
  testWidgets('the LOADING state carries no perpetual animation, so an '
      'enclosing sheet can still settle', (tester) async {
    // pumpAndSettle inside _pump would TIME OUT if this row animated forever.
    await _pump(tester, loading: true);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(_strings.loading), findsOneWidget);
    // ...and the misleading empty state is NOT shown in its place.
    expect(find.text(_strings.empty), findsNothing);
  });

  testWidgets('opening and CANCELLING the form disposes its controllers '
      'cleanly and mutates nothing', (tester) async {
    final calls = await _pump(tester);

    await tester.tap(find.byKey(const Key('saved-printers-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('saved-printer-host-field')),
      '10.0.0.5',
    );
    await tester.tap(find.byKey(const Key('saved-printer-cancel')));
    // Pump THROUGH the dialog's exit animation: the old code disposed the
    // controllers here while the fields were still being rebuilt.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(calls, isEmpty, reason: 'cancel never calls back');
  });

  testWidgets('a SUCCESSFUL save closes the form without a disposed-controller '
      'exception', (tester) async {
    final calls = await _pump(tester);

    await tester.tap(find.byKey(const Key('saved-printers-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('saved-printer-name-field')),
      'Grill',
    );
    await tester.enterText(
      find.byKey(const Key('saved-printer-host-field')),
      '10.0.0.5',
    );
    await tester.enterText(
      find.byKey(const Key('saved-printer-port-field')),
      '9100',
    );
    await tester.tap(find.byKey(const Key('saved-printer-save')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(calls, ['add:Grill:10.0.0.5:9100']);
    expect(find.byKey(const Key('saved-printer-save')), findsNothing);
  });

  testWidgets('validation is localized and refuses before any callback', (
    tester,
  ) async {
    final calls = await _pump(tester);

    await tester.tap(find.byKey(const Key('saved-printers-add')));
    await tester.pumpAndSettle();

    // Blank name.
    await tester.tap(find.byKey(const Key('saved-printer-save')));
    await tester.pumpAndSettle();
    expect(find.text(_strings.nameRequired), findsOneWidget);

    // Blank host.
    await tester.enterText(
      find.byKey(const Key('saved-printer-name-field')),
      'X',
    );
    await tester.tap(find.byKey(const Key('saved-printer-save')));
    await tester.pumpAndSettle();
    expect(find.text(_strings.invalidHost), findsOneWidget);

    // Out-of-range port — 9100 is the default, never the only valid value.
    await tester.enterText(
      find.byKey(const Key('saved-printer-host-field')),
      'h',
    );
    await tester.enterText(
      find.byKey(const Key('saved-printer-port-field')),
      '70000',
    );
    await tester.tap(find.byKey(const Key('saved-printer-save')));
    await tester.pumpAndSettle();
    expect(find.text(_strings.invalidPort), findsOneWidget);

    expect(calls, isEmpty, reason: 'nothing reached the store');
  });

  testWidgets('a DUPLICATE result keeps the form open with the localized '
      'message', (tester) async {
    await _pump(tester, addResult: SavedPrinterSaveResult.duplicate);

    await tester.tap(find.byKey(const Key('saved-printers-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('saved-printer-name-field')),
      'Dup',
    );
    await tester.enterText(
      find.byKey(const Key('saved-printer-host-field')),
      '10.0.0.14',
    );
    await tester.tap(find.byKey(const Key('saved-printer-save')));
    await tester.pumpAndSettle();

    expect(find.text(_strings.duplicateError), findsOneWidget);
    expect(
      find.byKey(const Key('saved-printer-save')),
      findsOneWidget,
      reason: 'the form stays open so the operator can correct it',
    );
  });

  testWidgets('delete requires confirmation and NAMES the printer; the active '
      'one adds a warning', (tester) async {
    final calls = await _pump(
      tester,
      profiles: [_profile],
      activeId: _profile.id,
    );

    await tester.tap(find.byKey(const Key('saved-printer-delete-p1')));
    await tester.pumpAndSettle();
    expect(find.text('Kitchen will be removed'), findsOneWidget);
    expect(find.text(_strings.deleteActiveWarning), findsOneWidget);
    expect(calls, isEmpty, reason: 'nothing removed before confirmation');

    await tester.tap(find.byKey(const Key('saved-printer-delete-cancel')));
    await tester.pumpAndSettle();
    expect(
      calls,
      isEmpty,
      reason: 'cancelling the confirmation removes nothing',
    );

    await tester.tap(find.byKey(const Key('saved-printer-delete-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saved-printer-delete-confirm')));
    await tester.pumpAndSettle();
    expect(calls, ['remove:p1']);
  });

  testWidgets('the active row is identifiable by TEXT, not colour alone', (
    tester,
  ) async {
    await _pump(tester, profiles: [_profile], activeId: _profile.id);
    expect(find.byKey(const Key('saved-printer-active-p1')), findsOneWidget);
    expect(find.text(_strings.activeBadge), findsOneWidget);
    expect(find.text('10.0.0.14:9100'), findsOneWidget);
  });

  testWidgets('a load FAILURE offers Retry', (tester) async {
    final calls = await _pump(tester, failed: true);
    expect(find.text(_strings.loadFailure), findsOneWidget);
    await tester.tap(find.byKey(const Key('saved-printers-retry')));
    await tester.pumpAndSettle();
    expect(calls, ['retry']);
  });
}
