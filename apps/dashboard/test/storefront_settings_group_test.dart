import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/src/storefront/storefront_settings_group.dart';

void main() {
  testWidgets('folding keeps the draft mounted and excludes hidden focus', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'saved');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    var edits = 0;
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              StorefrontSettingsGroup(
                title: 'Appearance',
                child: TextField(
                  key: const Key('draft'),
                  controller: controller,
                  focusNode: focus,
                  onChanged: (_) => edits++,
                ),
              ),
              TextButton(onPressed: () => saves++, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('draft')), findsNothing);
    expect(find.byKey(const Key('draft'), skipOffstage: false), findsOneWidget);
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('draft')), 'unsaved');
    final fieldState = tester.state(find.byType(EditableText));
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('draft')), findsNothing);
    expect(controller.text, 'unsaved');
    expect(edits, 1);
    expect(saves, 0);
    expect(focus.hasFocus, isFalse);
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(EditableText)), same(fieldState));
    expect(controller.text, 'unsaved');
    expect(edits, 1);
    expect(saves, 0);
    await tester.tap(find.text('Save'));
    expect(saves, 1);
  });
}
